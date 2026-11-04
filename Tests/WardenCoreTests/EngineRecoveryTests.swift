@testable import WardenCore
import XCTest

/// Damaged state, decisions about a superseded change, and restoring the reference.
extension EngineTests {
    // MARK: - Damaged state

    private var stateFile: URL { store.root.appendingPathComponent("state.json") }

    func testDamagedStateDoesNotStopMonitoringAndStaysVisible() async throws {
        try home.write("{}", to: settings)
        try await start()
        await engine.stop()
        try Data("not json".utf8).write(to: stateFile)

        try await start()
        let snapshot = await engine.currentSnapshot()
        XCTAssertNotNil(snapshot.stateResetAt)
        XCTAssertEqual(snapshot.shield, .pending)
        XCTAssertFalse(snapshot.files.isEmpty)
        XCTAssertFalse(watcher.paths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.root.appendingPathComponent("state.damaged.json").path))

        await engine.acknowledgeStateReset()
        let acknowledged = await engine.currentSnapshot()
        XCTAssertNil(acknowledged.stateResetAt)
        XCTAssertEqual(acknowledged.shield, .secure)
    }

    /// The attack: damage the state so that Warden forgets, then change the file.
    func testDamagingTheStateCannotLaunderAModifiedFile() async throws {
        try home.write("{}", to: settings)
        try await start()
        await engine.stop()
        try Data("not json".utf8).write(to: stateFile)
        try home.write(#"{"hooks":{"Stop":[{"command":"evil"}]}}"#, to: settings)

        try await start()
        let change = try await XCTUnwrapAsync(await pending(settings))
        XCTAssertEqual(change.severity, .critical)
        try await engine.revert(path: settings)
        XCTAssertEqual(try home.read(settings), "{}")
    }

    func testDeletingTheStateCannotLaunderAModifiedFile() async throws {
        try home.write("{}", to: settings)
        try await start()
        await engine.stop()
        try FileManager.default.removeItem(at: stateFile)
        try home.write(#"{"hooks":{"Stop":[{"command":"evil"}]}}"#, to: settings)

        try await start()
        let change = try await XCTUnwrapAsync(await pending(settings))
        XCTAssertEqual(change.severity, .critical)
        let reset = await engine.currentSnapshot().stateResetAt
        XCTAssertNotNil(reset)
    }

    func testEmptyingTheStateCountsAsDamage() async throws {
        try home.write("{}", to: settings)
        try await start()
        await engine.stop()
        try Data("{}".utf8).write(to: stateFile)
        try home.write(#"{"hooks":{"Stop":[{"command":"evil"}]}}"#, to: settings)

        try await start()
        let change = try await XCTUnwrapAsync(await pending(settings))
        XCTAssertEqual(change.severity, .critical)
    }

    /// A file that did not exist has no history: it must not become its own reference.
    func testFileCreatedWhileTheStateIsDamagedIsReported() async throws {
        try home.write("{}", to: settings)
        try await start()
        await engine.stop()
        try Data("not json".utf8).write(to: stateFile)
        let local = ".claude/settings.local.json"
        try home.write(#"{"hooks":{"Stop":[{"command":"evil"}]}}"#, to: local)

        try await start()
        let change = try await XCTUnwrapAsync(await pending(local))
        XCTAssertEqual(change.severity, .critical)
        try await engine.revert(path: local)
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.url.appendingPathComponent(local).path))
    }

    func testCustomFilesSurviveAReset() async throws {
        let custom = "notes/agent.md"
        try home.write("hello", to: custom)
        try await start()
        await engine.addFile(url: home.url.appendingPathComponent(custom))
        await engine.stop()
        try Data("not json".utf8).write(to: stateFile)

        try await start()
        let paths = await engine.currentSnapshot().files.map(\.record.path)
        XCTAssertTrue(paths.contains(custom))
        let change = await pending(custom)
        XCTAssertNil(change)
    }

    func testRebuiltReferenceIsTheLatestAcceptedVersion() async throws {
        try home.write("{}", to: settings)
        try await start()
        try home.write(#"{"a":1}"#, to: settings)
        await engine.scanAll()
        try await engine.accept(path: settings)
        await engine.stop()
        try Data("not json".utf8).write(to: stateFile)

        try await start()
        let change = await pending(settings)
        XCTAssertNil(change)
    }

    // MARK: - Decisions about a version the user saw

    func testDecisionsOnASupersededChangeDoNothing() async throws {
        try home.write("{}", to: settings)
        try await start()
        try home.write(#"{"a":1}"#, to: settings)
        await engine.scanAll()
        let seen = try await XCTUnwrapAsync(await pending(settings))
        let evil = #"{"a":1,"hooks":{"Stop":[{"command":"evil"}]}}"#
        try home.write(evil, to: settings)
        await engine.scanAll()

        await XCTAssertThrowsErrorAsync(try await self.engine.accept(path: self.settings, fingerprint: seen.fingerprint)) {
            XCTAssertEqual($0 as? EngineError, .changeSuperseded)
        }
        await XCTAssertThrowsErrorAsync(try await self.engine.revert(path: self.settings, fingerprint: seen.fingerprint)) {
            XCTAssertEqual($0 as? EngineError, .changeSuperseded)
        }
        let change = try await XCTUnwrapAsync(await pending(settings))
        XCTAssertEqual(change.severity, .critical)
        XCTAssertEqual(try home.read(settings), evil)
    }

    func testDecisionWithTheCurrentFingerprintApplies() async throws {
        try home.write("{}", to: settings)
        try await start()
        try home.write(#"{"a":1}"#, to: settings)
        await engine.scanAll()
        let change = try await XCTUnwrapAsync(await pending(settings))
        try await engine.accept(path: settings, fingerprint: change.fingerprint)
        let remaining = await pending(settings)
        XCTAssertNil(remaining)
    }

    // MARK: - Restoring the current reference

    /// Found by hand: after an accept, restoring that same version did nothing, yet added
    /// a line to the history and looked as if the change had been undone.
    func testRestoringTheCurrentReferenceIsRefusedAndLeavesNoTrace() async throws {
        let evil = #"{"hooks":{"Stop":[{"command":"evil"}]}}"#
        try home.write("{}", to: settings)
        try await start()
        try home.write(evil, to: settings)
        await engine.scanAll()
        try await engine.accept(path: settings)
        let accepted = WardenStore.hash(Data(evil.utf8))
        let before = await engine.currentSnapshot().history.count

        await XCTAssertThrowsErrorAsync(try await self.engine.restore(path: self.settings, sha: accepted)) {
            XCTAssertEqual($0 as? EngineError, .alreadyReference)
        }
        let snapshot = await engine.currentSnapshot()
        XCTAssertEqual(snapshot.history.count, before)
        XCTAssertFalse(snapshot.history.contains { $0.kind == .restored })
        XCTAssertEqual(try home.read(settings), evil)
    }

    func testSnapshotExposesTheReferenceSoTheInterfaceCanTellThem() async throws {
        try home.write("{}", to: settings)
        try await start()
        let status = await engine.currentSnapshot().files.first { $0.record.path == settings }
        XCTAssertEqual(status?.baselineSHA, WardenStore.hash(Data("{}".utf8)))
    }

    /// The reference is the same but the file is not: restoring still has a job to do.
    func testRestoringTheReferenceStillWorksWhenTheFileDiffers() async throws {
        try home.write("{}", to: settings)
        try await start()
        let reference = WardenStore.hash(Data("{}".utf8))
        try home.write(#"{"a":1}"#, to: settings)
        try await engine.restore(path: settings, sha: reference)
        XCTAssertEqual(try home.read(settings), "{}")
    }

    func testRestoringAnotherVersionAfterAnAcceptUndoesIt() async throws {
        try home.write("{}", to: settings)
        try await start()
        try home.write(#"{"hooks":{"Stop":[{"command":"evil"}]}}"#, to: settings)
        await engine.scanAll()
        try await engine.accept(path: settings)
        try await engine.restore(path: settings, sha: WardenStore.hash(Data("{}".utf8)))
        XCTAssertEqual(try home.read(settings), "{}")
        let last = await engine.currentSnapshot().history.first?.kind
        XCTAssertEqual(last, .restored)
    }
}
