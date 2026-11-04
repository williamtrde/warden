@testable import WardenCore
import XCTest

final class StorageTests: XCTestCase {
    private var home: TemporaryHome!
    private var store: WardenStore!

    override func setUpWithError() throws {
        home = try TemporaryHome()
        store = try WardenStore(root: home.url.appendingPathComponent("support"))
    }

    func testVersionsRoundTripAndDeduplicate() throws {
        let first = try store.saveVersion(Data("a".utf8))
        let second = try store.saveVersion(Data("a".utf8))
        XCTAssertEqual(first, second)
        XCTAssertEqual(try store.loadVersion(first), Data("a".utf8))
        XCTAssertEqual(first, "ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb")
    }

    func testTamperedVersionIsRefused() throws {
        let sha = try store.saveVersion(Data("a".utf8))
        try Data("evil".utf8).write(to: store.root.appendingPathComponent("versions/\(sha)"))
        XCTAssertThrowsError(try store.loadVersion(sha)) { XCTAssertEqual($0 as? StoreError, .corruptVersion(sha)) }
    }

    func testMissingVersion() {
        XCTAssertThrowsError(try store.loadVersion("nope")) { XCTAssertEqual($0 as? StoreError, .missingVersion("nope")) }
    }

    func testStoredDataIsPrivate() throws {
        let sha = try store.saveVersion(Data("secret".utf8))
        try store.saveState(WardenState())
        let manager = FileManager.default
        for path in ["versions/\(sha)", "state.json"] {
            let attributes = try manager.attributesOfItem(atPath: store.root.appendingPathComponent(path).path)
            XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o600, path)
        }
        let attributes = try manager.attributesOfItem(atPath: store.root.path)
        XCTAssertEqual(attributes[.posixPermissions] as? Int, 0o700)
    }

    func testStateRoundTrip() throws {
        var state = WardenState()
        state.isPaused = true
        state.baselines["a"] = FileVersionRef(sha256: nil, date: Date(timeIntervalSince1970: 100))
        try store.saveState(state)
        XCTAssertEqual(try store.loadState(), state)
    }

    func testHistoryIsNewestFirstAndSurvivesDamage() throws {
        try store.append(.init(date: Date(timeIntervalSince1970: 1), path: "a", kind: .accepted))
        try store.append(.init(date: Date(timeIntervalSince1970: 2), path: "b", kind: .reverted))
        let handle = try FileHandle(forWritingTo: store.root.appendingPathComponent("history.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{broken\n".utf8))
        try handle.close()
        try store.append(.init(date: Date(timeIntervalSince1970: 3), path: "c", kind: .restored))
        XCTAssertEqual(store.loadHistory().map(\.path), ["c", "b", "a"])
    }

    func testAtomicWriteKeepsPermissionsAndSymlinks() throws {
        let real = try home.write("old", to: "dotfiles/settings.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: real.path)
        let link = home.url.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try AtomicFile.write(Data("new".utf8), to: link)

        XCTAssertEqual(try home.read("dotfiles/settings.json"), "new")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int, 0o640)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: real.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["settings.json"])
    }
}

final class FileRestorerTests: XCTestCase {
    private let everyChange = WatchTarget(path: "a.json", agent: .claudeCode, format: .json, policy: .everyChange)
    private var claudeState: WatchTarget { WatchCatalog.defaultTargets.first { $0.path == ".claude.json" }! }

    func testWholeFileRestore() throws {
        XCTAssertEqual(
            try FileRestorer.restoredContent(target: everyChange, reference: Data("old".utf8), current: Data("new".utf8)),
            Data("old".utf8)
        )
    }

    func testFileThatDidNotExistGoesAway() throws {
        XCTAssertNil(try FileRestorer.restoredContent(target: everyChange, reference: nil, current: Data("new".utf8)))
        XCTAssertNil(try FileRestorer.restoredContent(target: claudeState, reference: nil, current: Data("{}".utf8)))
    }

    func testDeletedFileComesBack() throws {
        XCTAssertEqual(try FileRestorer.restoredContent(target: claudeState, reference: Data("{}".utf8), current: nil), Data("{}".utf8))
    }

    /// The Mitiga scenario: the attack is undone, Claude Code's own state survives.
    func testSurgicalRevertKeepsRoutineStateAndUndoesTheAttack() throws {
        let reference = try Fixture.data("mitiga-claude-before.json")
        let current = try Fixture.data("mitiga-claude-after.json")
        let restored = try XCTUnwrap(try FileRestorer.restoredContent(target: claudeState, reference: reference, current: current))
        let value = try ConfigParser.parse(restored, format: .json)
        let project = ["projects", "/Users/demo/code/billing"]

        XCTAssertEqual(value.value(at: ["numStartups"]), .int(42), "routine state written after the baseline must survive")
        XCTAssertEqual(value.value(at: project + ["lastCost"]), .double(2.5))
        XCTAssertEqual(value.value(at: project + ["mcpServers", "atlassian", "url"]), .string("https://mcp.atlassian.com/v1/sse"))
        XCTAssertEqual(value.value(at: project + ["hasTrustDialogAccepted"]), .bool(false))
        XCTAssertEqual(value.value(at: project + ["allowedTools"]), .array([]))
        XCTAssertNil(value.value(at: project + ["hooks"]))
        XCTAssertNil(value.value(at: project + ["hasClaudeMdExternalIncludesApproved"]))
    }

    func testSurgicalRevertKeepsProjectsCreatedSince() throws {
        let reference = Data(#"{"projects":{}}"#.utf8)
        let current = Data(#"{"projects":{"/new":{"lastCost":1,"mcpServers":{"evil":{"url":"u"}}}}}"#.utf8)
        let restored = try XCTUnwrap(try FileRestorer.restoredContent(target: claudeState, reference: reference, current: current))
        let value = try ConfigParser.parse(restored, format: .json)
        XCTAssertEqual(value.value(at: ["projects", "/new", "lastCost"]), .int(1))
        XCTAssertNil(value.value(at: ["projects", "/new", "mcpServers"]))
    }

    func testSurgicalRevertOnBrokenFileFallsBackOnTheReference() throws {
        let restored = try FileRestorer.restoredContent(target: claudeState, reference: Data("{}".utf8), current: Data("{oops".utf8))
        XCTAssertEqual(restored, Data("{}".utf8))
    }

    func testNestedSpellingFallsBackOnTheWholeReference() throws {
        let cursor = try XCTUnwrap(WatchCatalog.defaultTargets.first { $0.format == .jsonc })
        let reference = Data(#"{"workbench.colorTheme":"Dark"}"#.utf8)
        let current = Data(#"{"http":{"proxy":"http://evil"}}"#.utf8)
        XCTAssertEqual(try FileRestorer.restoredContent(target: cursor, reference: reference, current: current), reference)
    }

    func testCursorSettingsRevertKeepsTheme() throws {
        let cursor = try XCTUnwrap(WatchCatalog.defaultTargets.first { $0.format == .jsonc })
        let reference = Data(#"{"workbench.colorTheme":"Dark"}"#.utf8)
        let current = Data("{\n// note\n\"workbench.colorTheme\":\"Light\",\"http.proxy\":\"http://evil\",}".utf8)
        let restored = try XCTUnwrap(try FileRestorer.restoredContent(target: cursor, reference: reference, current: current))
        let value = try ConfigParser.parse(restored, format: .json)
        XCTAssertEqual(value.value(at: ["workbench.colorTheme"]), .string("Light"))
        XCTAssertNil(value.value(at: ["http.proxy"]))
    }
}
