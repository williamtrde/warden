import Foundation

public enum EngineError: Error, Equatable {
    case noPendingChange
    case unknownFile
    /// The file changed again: the decision was about a version that is no longer the pending one.
    case changeSuperseded
    /// Restoring would change nothing: this version is the reference and the file matches it.
    case alreadyReference
}

/// Coordinates watching, analysis, explanation and decisions. Never changes a watched file
/// by itself: writes only happen in `revert` and `restore`, which only the user can trigger.
public actor WardenEngine {
    public struct Configuration: Sendable {
        public let home: URL
        public let store: WardenStore
        public let watcher: FileWatching
        public let usage: UsageContextBuilder
        /// Builds the on-device generator. Nil when unavailable on this Mac.
        public let onDeviceGenerator: @Sendable () -> ExplanationGenerator?
        public let language: @Sendable () -> ExplanationLanguage
        public let now: @Sendable () -> Date
        public let scanInterval: TimeInterval
        /// How long to wait before believing a file is really malformed: it may be mid-write.
        public let malformedGracePeriod: TimeInterval

        public init(
            home: URL,
            store: WardenStore,
            watcher: FileWatching,
            usage: UsageContextBuilder,
            onDeviceGenerator: @escaping @Sendable () -> ExplanationGenerator?,
            language: @escaping @Sendable () -> ExplanationLanguage = { .current() },
            now: @escaping @Sendable () -> Date = { Date() },
            scanInterval: TimeInterval = 30,
            malformedGracePeriod: TimeInterval = 2
        ) {
            self.home = home
            self.store = store
            self.watcher = watcher
            self.usage = usage
            self.onDeviceGenerator = onDeviceGenerator
            self.language = language
            self.now = now
            self.scanInterval = scanInterval
            self.malformedGracePeriod = malformedGracePeriod
        }
    }

    private let configuration: Configuration
    private var state: WardenState
    private var history: [HistoryEntry]
    private var scanning = Set<String>()
    private var rescanRequested = Set<String>()
    private var malformedSeen = Set<String>()
    private var scanTask: Task<Void, Never>?

    public nonisolated let snapshots: AsyncStream<EngineSnapshot>
    private let snapshotContinuation: AsyncStream<EngineSnapshot>.Continuation
    /// Emits each new or updated change, to be turned into a notification.
    public nonisolated let alerts: AsyncStream<PendingChange>
    private let alertContinuation: AsyncStream<PendingChange>.Continuation

    private var store: WardenStore { configuration.store }

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        let loaded = try configuration.store.loadStateRecovering()
        let history = configuration.store.loadHistory()
        self.history = history
        // No files with a history behind them means the state was removed, which is damage too.
        let isDamaged = loaded.wasDamaged || (loaded.state.files.isEmpty && !history.isEmpty)
        state = isDamaged
            ? Self.rebuiltState(from: history, home: configuration.home, date: configuration.now())
            : loaded.state
        (snapshots, snapshotContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (alerts, alertContinuation) = AsyncStream.makeStream()
    }

    /// Rebuilds what the history proves, so that damaging the state cannot turn a modified file
    /// into its own reference. A file with no proven version counts as "did not exist": if it is
    /// there, it gets reported instead of absorbed. `history` is newest first.
    private static func rebuiltState(from history: [HistoryEntry], home: URL, date: Date) -> WardenState {
        var state = WardenState()
        state.stateResetAt = date
        state.files = WatchCatalog.defaultTargets.map { WatchedFileRecord(target: $0, isBuiltIn: true) }
        for entry in history where !state.files.contains(where: { $0.path == entry.path }) {
            let url = entry.path.hasPrefix("/") ? URL(fileURLWithPath: entry.path) : home.appendingPathComponent(entry.path)
            state.files.append(WatchedFileRecord(target: WatchCatalog.customTarget(url: url, home: home), isBuiltIn: false))
        }
        for entry in history where [.baselineCreated, .accepted, .restored].contains(entry.kind) && state.baselines[entry.path] == nil {
            state.baselines[entry.path] = FileVersionRef(sha256: entry.versionSHA, date: entry.date)
        }
        for record in state.files where state.baselines[record.path] == nil {
            state.baselines[record.path] = FileVersionRef(sha256: nil, date: date)
        }
        return state
    }

    // MARK: - Lifecycle

    /// Registers the default files on first launch, then scans and starts watching.
    public func start() async {
        if state.files.isEmpty {
            state.files = WatchCatalog.defaultTargets.map { WatchedFileRecord(target: $0, isBuiltIn: true) }
        }
        persist()
        await scanAll()
        restartWatching()
        scanTask?.cancel()
        let interval = configuration.scanInterval
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.scanAll()
            }
        }
    }

    public func stop() {
        scanTask?.cancel()
        scanTask = nil
        configuration.watcher.stop()
    }

    private func restartWatching() {
        configuration.watcher.stop()
        guard !state.isPaused else { return }
        let paths = state.files.map { $0.target.url(home: configuration.home).path }
        configuration.watcher.start(paths: paths) { [weak self] changed in
            Task { await self?.handleEvents(changed) }
        }
    }

    private func handleEvents(_ paths: [String]) async {
        let changed = Set(paths)
        for record in state.files {
            let url = record.target.url(home: configuration.home).resolvingSymlinksInPath()
            if changed.contains(url.path) { await scan(record.target) }
        }
    }

    // MARK: - Scanning

    public func scanAll() async {
        guard !state.isPaused else { return }
        for record in state.files {
            await scan(record.target)
        }
    }

    /// Scans are serialized per file: explaining a change takes seconds, during which more writes can land.
    private func scan(_ target: WatchTarget) async {
        guard !scanning.contains(target.path) else {
            rescanRequested.insert(target.path)
            return
        }
        scanning.insert(target.path)
        repeat {
            rescanRequested.remove(target.path)
            await scanOnce(target)
        } while rescanRequested.contains(target.path)
        scanning.remove(target.path)
    }

    private func read(_ target: WatchTarget) -> Data? {
        try? Data(contentsOf: target.url(home: configuration.home))
    }

    private func scanOnce(_ target: WatchTarget) async {
        let current = read(target)
        guard let baseline = state.baselines[target.path] else {
            createBaseline(target, data: current)
            return
        }
        let reference = baseline.sha256.flatMap { try? store.loadVersion($0) }
        guard let analysis = ChangeAnalyzer.analyze(target: target, old: reference, new: current) else {
            malformedSeen.remove(target.path)
            resolveExternally(target)
            return
        }
        if analysis.isMalformed, !malformedSeen.contains(target.path) {
            malformedSeen.insert(target.path)
            scheduleRescan(target)
            return
        }
        if state.pending[target.path]?.fingerprint == analysis.fingerprint { return }
        await raise(analysis, target: target, reference: baseline, current: current)
    }

    private func scheduleRescan(_ target: WatchTarget) {
        let delay = configuration.malformedGracePeriod
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.scan(target)
        }
    }

    private func createBaseline(_ target: WatchTarget, data: Data?) {
        let sha = data.flatMap { try? store.saveVersion($0) }
        state.baselines[target.path] = FileVersionRef(sha256: sha, date: configuration.now())
        if let sha {
            record(.init(date: configuration.now(), path: target.path, kind: .baselineCreated, versionSHA: sha))
        }
        persist()
    }

    /// The file matches its reference again, whoever did it.
    private func resolveExternally(_ target: WatchTarget) {
        guard state.pending.removeValue(forKey: target.path) != nil else { return }
        record(.init(date: configuration.now(), path: target.path, kind: .resolvedExternally))
        persist()
    }

    private func raise(_ analysis: ChangeAnalysis, target: WatchTarget, reference: FileVersionRef, current: Data?) async {
        let date = configuration.now()
        let request = ExplanationRequestBuilder.make(
            target: target,
            analysis: analysis,
            usage: configuration.usage.build(now: date),
            language: configuration.language(),
            date: date
        )
        let generator = state.isOnDeviceAIEnabled ? configuration.onDeviceGenerator() : nil
        let explanation = await ExplanationService(primary: generator).explain(request)

        let afterSHA = current.flatMap { try? store.saveVersion($0) }
        let change = PendingChange(
            path: target.path,
            detectedAt: date,
            beforeSHA: reference.sha256,
            afterSHA: afterSHA,
            fingerprint: analysis.fingerprint,
            severity: analysis.severity,
            findings: analysis.findings,
            explanation: explanation
        )
        state.pending[target.path] = change
        record(.init(
            date: date,
            path: target.path,
            kind: .changeDetected,
            severity: change.severity,
            versionSHA: afterSHA,
            summary: explanation.fullText
        ))
        persist()
        alertContinuation.yield(change)
    }

    // MARK: - Decisions

    private func pendingChange(path: String, fingerprint: String?) throws -> PendingChange {
        guard let change = state.pending[path] else { throw EngineError.noPendingChange }
        if let fingerprint, fingerprint != change.fingerprint { throw EngineError.changeSuperseded }
        return change
    }

    /// Makes the version the user reviewed the new reference. If the file changed again
    /// since then, the next scan raises that newer change instead of silently accepting it.
    /// Pass the `fingerprint` of the change the user saw: a newer one is never decided unseen.
    public func accept(path: String, fingerprint: String? = nil) async throws {
        let change = try pendingChange(path: path, fingerprint: fingerprint)
        let date = configuration.now()
        state.baselines[path] = FileVersionRef(sha256: change.afterSHA, date: date)
        state.pending[path] = nil
        record(.init(date: date, path: path, kind: .accepted, severity: change.severity, versionSHA: change.afterSHA))
        persist()
        if let record = state.files.first(where: { $0.path == path }) { await scan(record.target) }
    }

    /// Restores the reference, after saving the modified version.
    public func revert(path: String, fingerprint: String? = nil) throws {
        let change = try pendingChange(path: path, fingerprint: fingerprint)
        guard let record = state.files.first(where: { $0.path == path }) else { throw EngineError.unknownFile }
        let reference = try state.baselines[path]?.sha256.map(store.loadVersion)
        let backup = try overwrite(record.target, with: reference)
        state.pending[path] = nil
        self.record(.init(
            date: configuration.now(),
            path: path,
            kind: .reverted,
            severity: change.severity,
            versionSHA: state.baselines[path]?.sha256,
            backupSHA: backup
        ))
        persist()
    }

    /// Brings back any stored version and makes it the reference.
    public func restore(path: String, sha: String) throws {
        guard let record = state.files.first(where: { $0.path == path }) else { throw EngineError.unknownFile }
        let version = try store.loadVersion(sha)
        if state.baselines[path]?.sha256 == sha,
           ChangeAnalyzer.analyze(target: record.target, old: version, new: read(record.target)) == nil {
            throw EngineError.alreadyReference
        }
        let backup = try overwrite(record.target, with: version)
        let date = configuration.now()
        state.baselines[path] = FileVersionRef(sha256: sha, date: date)
        state.pending[path] = nil
        self.record(.init(date: date, path: path, kind: .restored, versionSHA: sha, backupSHA: backup))
        persist()
    }

    /// Saves the current content, then writes the new one. Returns the backup's hash.
    private func overwrite(_ target: WatchTarget, with reference: Data?) throws -> String? {
        let current = read(target)
        let backup = try current.map(store.saveVersion)
        let url = target.url(home: configuration.home)
        if let content = try FileRestorer.restoredContent(target: target, reference: reference, current: current) {
            try AtomicFile.write(content, to: url)
        } else if current != nil {
            try FileManager.default.removeItem(at: url)
        }
        return backup
    }

    // MARK: - Reading for the interface

    /// The diff of a pending change, between the reference and the version under review.
    public func diff(for change: PendingChange) -> LineDiff? {
        diff(path: change.path, fromSHA: change.beforeSHA, toSHA: change.afterSHA)
    }

    /// The diff between two stored versions, masked and with emphasis.
    public func diff(path: String, fromSHA: String?, toSHA: String?) -> LineDiff? {
        guard let record = state.files.first(where: { $0.path == path }) else { return nil }
        let old = fromSHA.flatMap { try? store.loadVersion($0) }
        let new = toSHA.flatMap { try? store.loadVersion($0) }
        return ChangeAnalyzer.analyze(target: record.target, old: old, new: new)?.diff
    }

    public func currentSnapshot() -> EngineSnapshot {
        var snapshot = EngineSnapshot()
        snapshot.isPaused = state.isPaused
        snapshot.isOnDeviceAIEnabled = state.isOnDeviceAIEnabled
        snapshot.stateResetAt = state.stateResetAt
        snapshot.history = history
        snapshot.files = state.files.map { record in
            FileStatus(
                record: record,
                exists: FileManager.default.fileExists(atPath: record.target.url(home: configuration.home).path),
                baselineDate: state.baselines[record.path]?.date,
                baselineSHA: state.baselines[record.path]?.sha256,
                pending: state.pending[record.path]
            )
        }
        return snapshot
    }

    // MARK: - Settings

    public func setPaused(_ paused: Bool) async {
        state.isPaused = paused
        persist()
        restartWatching()
        // Changes made during the pause are caught here.
        if !paused { await scanAll() }
    }

    public func acknowledgeStateReset() {
        state.stateResetAt = nil
        persist()
    }

    public func setOnDeviceAIEnabled(_ enabled: Bool) {
        state.isOnDeviceAIEnabled = enabled
        persist()
    }

    public func addFile(url: URL) async {
        let target = WatchCatalog.customTarget(url: url, home: configuration.home)
        guard !state.files.contains(where: { $0.path == target.path }) else { return }
        let isBuiltIn = WatchCatalog.defaultTargets.contains { $0.path == target.path }
        state.files.append(WatchedFileRecord(target: target, isBuiltIn: isBuiltIn))
        persist()
        await scan(state.files[state.files.count - 1].target)
        restartWatching()
    }

    public func removeFile(path: String) {
        state.files.removeAll { $0.path == path }
        state.baselines[path] = nil
        state.pending[path] = nil
        persist()
        restartWatching()
    }

    // MARK: - Persistence

    private func record(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        try? store.append(entry)
    }

    private func persist() {
        try? store.saveState(state)
        snapshotContinuation.yield(currentSnapshot())
    }
}
