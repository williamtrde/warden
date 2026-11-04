import Foundation

/// Derives a `UsageContext` from metadata. Session files are only ever listed and dated.
public struct UsageContextBuilder: Sendable {
    private let reader: MetadataReader
    private let home: URL

    public init(reader: MetadataReader, home: URL) {
        self.reader = reader
        self.home = home
    }

    public func build(now: Date = Date()) -> UsageContext {
        let cutoff = now.addingTimeInterval(-UsageContext.activeWindow)
        var activity: [Agent: Date] = [:]

        let claude = claudeProjects(cutoff: cutoff)
        activity[.claudeCode] = claude.compactMap(\.lastUsed).max()

        let codexActivity = codexLastSession()
        activity[.codex] = codexActivity

        let cursor = cursorProjects(cutoff: cutoff)
        activity[.cursor] = cursor.compactMap(\.lastUsed).max()

        return UsageContext(projects: claude + codexProjects() + cursor, lastAgentActivity: activity, date: now)
    }

    // MARK: - Claude Code

    private func claudeProjects(cutoff: Date) -> [ProjectUsage] {
        let knownPaths = claudeKnownPaths()
        let knownByFolder = Dictionary(knownPaths.map { (Self.claudeFolderName(for: $0), $0) }) { first, _ in first }
        var usages: [String: ProjectUsage] = [:]

        for folder in reader.children(of: home.appendingPathComponent(UsagePaths.claudeProjects)) {
            let path = knownByFolder[folder.lastPathComponent]
            let sessionDates = reader.children(of: folder)
                .filter { $0.pathExtension == "jsonl" }
                .compactMap(reader.modificationDate(of:))
            let identity = path ?? folder.lastPathComponent
            usages[identity] = ProjectUsage(
                path: identity,
                name: path.map(Self.displayName(forPath:)) ?? Self.displayName(forFolder: folder.lastPathComponent),
                agent: .claudeCode,
                lastUsed: sessionDates.max(),
                sessionsInWindow: sessionDates.filter { $0 >= cutoff }.count
            )
        }
        for path in knownPaths where usages[path] == nil {
            usages[path] = ProjectUsage(
                path: path, name: Self.displayName(forPath: path), agent: .claudeCode, lastUsed: .distantPast, sessionsInWindow: 0
            )
        }
        let homePath = home.standardizedFileURL.path
        return usages.values.filter { $0.path != homePath && $0.path != Self.claudeFolderName(for: homePath) }
            .sorted { $0.path < $1.path }
    }

    private func claudeKnownPaths() -> [String] {
        let url = home.appendingPathComponent(UsagePaths.claudeState)
        guard let data = reader.readMetadataFile(url),
              case .object(let root)? = try? ConfigParser.parse(data, format: .json),
              case .object(let projects)? = root["projects"] else { return [] }
        return projects.keys.sorted()
    }

    /// Claude Code stores each project under its path with every non-alphanumeric character replaced by `-`.
    static func claudeFolderName(for path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    private static func displayName(forPath path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// Folder names are lossy. Without a known path, the last segment is the best guess.
    private static func displayName(forFolder folder: String) -> String {
        folder.split(separator: "-").last.map(String.init) ?? folder
    }

    // MARK: - Codex

    private func codexProjects() -> [ProjectUsage] {
        let url = home.appendingPathComponent(UsagePaths.codexConfig)
        guard let data = reader.readMetadataFile(url),
              case .object(let root)? = try? ConfigParser.parse(data, format: .toml),
              case .object(let projects)? = root["projects"] else { return [] }
        return projects.keys.sorted().map {
            ProjectUsage(path: $0, name: Self.displayName(forPath: $0), agent: .codex, lastUsed: nil, sessionsInWindow: 0)
        }
    }

    /// Sessions live in `sessions/YYYY/MM/DD/`. Their project is only written inside them, so
    /// Warden keeps the date of the latest one and nothing else.
    private func codexLastSession() -> Date? {
        var latest: Date?
        func visit(_ directory: URL, depth: Int) {
            for child in reader.children(of: directory) {
                if depth > 0 {
                    visit(child, depth: depth - 1)
                } else if child.pathExtension == "jsonl", let date = reader.modificationDate(of: child) {
                    latest = max(latest ?? date, date)
                }
            }
        }
        visit(home.appendingPathComponent(UsagePaths.codexSessions), depth: 3)
        return latest
    }

    // MARK: - Cursor

    private func cursorProjects(cutoff: Date) -> [ProjectUsage] {
        var usages: [String: ProjectUsage] = [:]
        for workspace in reader.children(of: home.appendingPathComponent(UsagePaths.cursorWorkspaces)) {
            guard let data = reader.readMetadataFile(workspace.appendingPathComponent("workspace.json")),
                  let folder = (try? ConfigParser.parse(data, format: .json))?.value(at: ["folder"])?.stringValue,
                  let path = URL(string: folder)?.path, !path.isEmpty else { continue }
            let date = reader.modificationDate(of: workspace)
            if let existing = usages[path], (existing.lastUsed ?? .distantPast) >= (date ?? .distantPast) { continue }
            usages[path] = ProjectUsage(
                path: path,
                name: Self.displayName(forPath: path),
                agent: .cursor,
                lastUsed: date,
                sessionsInWindow: (date ?? .distantPast) >= cutoff ? 1 : 0
            )
        }
        return usages.values.sorted { $0.path < $1.path }
    }
}
