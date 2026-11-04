@testable import WardenCore
import XCTest

/// Wraps the real reader and records what passes through it.
private final class SpyReader: MetadataReader, @unchecked Sendable {
    private let inner: LocalMetadataReader
    private(set) var contentReads: [URL] = []

    init(home: URL) { inner = LocalMetadataReader(home: home) }

    func children(of directory: URL) -> [URL] { inner.children(of: directory) }
    func modificationDate(of url: URL) -> Date? { inner.modificationDate(of: url) }
    func readMetadataFile(_ url: URL) -> Data? {
        contentReads.append(url)
        return inner.readMetadataFile(url)
    }
}

final class UsageContextTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    private func makeHome() throws -> TemporaryHome {
        let home = try TemporaryHome()
        let atlas = home.url.appendingPathComponent("code/ATLAS").path
        let harbor = home.url.appendingPathComponent("code/my.harbor").path
        let old = home.url.appendingPathComponent("code/old").path
        let state = #"{"projects":{"\#(atlas)":{"lastCost":3},"\#(harbor)":{},"\#(old)":{}},"numStartups":3}"#
        try home.write(state, to: ".claude.json")
        let atlasFolder = UsageContextBuilder.claudeFolderName(for: atlas)
        let harborFolder = UsageContextBuilder.claudeFolderName(for: harbor)
        let oldFolder = UsageContextBuilder.claudeFolderName(for: old)
        try home.write("SECRET CONVERSATION", to: ".claude/projects/\(atlasFolder)/a.jsonl", modified: daysAgo(1))
        try home.write("SECRET CONVERSATION", to: ".claude/projects/\(atlasFolder)/b.jsonl", modified: daysAgo(2))
        try home.write("SECRET CONVERSATION", to: ".claude/projects/\(atlasFolder)/c.jsonl", modified: daysAgo(30))
        try home.write("SECRET CONVERSATION", to: ".claude/projects/\(harborFolder)/a.jsonl", modified: daysAgo(3))
        try home.write("SECRET CONVERSATION", to: ".claude/projects/\(oldFolder)/a.jsonl", modified: daysAgo(40))
        return home
    }

    func testActiveProjectsUseThe14DayWindow() throws {
        let home = try makeHome()
        let context = UsageContextBuilder(reader: LocalMetadataReader(home: home.url), home: home.url).build(now: now)
        let active = context.activeProjects(for: .claudeCode)
        XCTAssertEqual(active.map(\.name), ["ATLAS", "my.harbor"])
        XCTAssertEqual(active.first?.sessionsInWindow, 2)
        XCTAssertEqual(active.first?.lastUsed, daysAgo(1))
    }

    func testBoundaryOfTheWindow() {
        let inside = ProjectUsage(path: "/a", name: "a", agent: .cursor, lastUsed: daysAgo(14), sessionsInWindow: 1)
        let outside = ProjectUsage(path: "/b", name: "b", agent: .cursor, lastUsed: daysAgo(14.01), sessionsInWindow: 1)
        let context = UsageContext(projects: [inside, outside], lastAgentActivity: [:], date: now)
        XCTAssertEqual(context.activeProjects(for: .cursor).map(\.name), ["a"])
    }

    func testProjectWithoutKnownPathFallsBackOnFolderName() throws {
        let home = try TemporaryHome()
        try home.write("x", to: ".claude/projects/-Users-me-code-mystery/a.jsonl", modified: daysAgo(1))
        let context = UsageContextBuilder(reader: LocalMetadataReader(home: home.url), home: home.url).build(now: now)
        XCTAssertEqual(context.activeProjects(for: .claudeCode).map(\.name), ["mystery"])
    }

    func testHomeFolderIsNotAProject() throws {
        let home = try TemporaryHome()
        let folder = UsageContextBuilder.claudeFolderName(for: home.url.path)
        try home.write("x", to: ".claude/projects/\(folder)/a.jsonl", modified: daysAgo(1))
        try home.write(#"{"projects":{"\#(home.url.path)":{}}}"#, to: ".claude.json")
        let context = UsageContextBuilder(reader: LocalMetadataReader(home: home.url), home: home.url).build(now: now)
        XCTAssertEqual(context.projects, [])
    }

    func testCodexProjectsAreActiveWhenCodexIs() throws {
        let home = try TemporaryHome()
        try home.write("[projects.\"/code/api\"]\ntrust_level = \"trusted\"\n", to: ".codex/config.toml")
        try home.write("SECRET", to: ".codex/sessions/2026/11/01/rollout-a.jsonl", modified: daysAgo(2))
        let context = UsageContextBuilder(reader: LocalMetadataReader(home: home.url), home: home.url).build(now: now)
        XCTAssertEqual(context.activeProjects(for: .codex).map(\.name), ["api"])
        XCTAssertEqual(context.lastAgentActivity[.codex], daysAgo(2))
    }

    func testCursorWorkspaces() throws {
        let home = try TemporaryHome()
        let base = "Library/Application Support/Cursor/User/workspaceStorage"
        try home.write(#"{"folder":"file:///code/My%20App"}"#, to: "\(base)/abc/workspace.json")
        try home.write("SECRET", to: "\(base)/abc/state.vscdb")
        try FileManager.default.setAttributes([.modificationDate: daysAgo(1)], ofItemAtPath: home.url.appendingPathComponent("\(base)/abc").path)
        let context = UsageContextBuilder(reader: LocalMetadataReader(home: home.url), home: home.url).build(now: now)
        XCTAssertEqual(context.activeProjects(for: .cursor).map(\.name), ["My App"])
    }

    func testScopeForAWholeAgent() {
        let projects = (1...5).map {
            ProjectUsage(path: "/p\($0)", name: "p\($0)", agent: .claudeCode, lastUsed: daysAgo(Double($0)), sessionsInWindow: 1)
        }
        let scope = UsageContext(projects: projects, lastAgentActivity: [:], date: now).scope(agent: .claudeCode, projectPath: nil)
        XCTAssertEqual(scope.projects.map(\.name), ["p1", "p2", "p3"])
        XCTAssertEqual(scope.otherCount, 2)
        XCTAssertFalse(scope.isSingleProject)
    }

    func testScopeForOneProjectEvenIfUnknown() {
        let scope = UsageContext.empty.scope(agent: .claudeCode, projectPath: "/code/billing")
        XCTAssertEqual(scope.projects.map(\.name), ["billing"])
        XCTAssertTrue(scope.isSingleProject)
    }

    // MARK: Privacy

    /// Session files are made unreadable: any attempt to open them would fail the scan
    /// or produce no dates, and the spy proves no content read was even attempted.
    func testSessionContentIsNeverRead() throws {
        let home = try makeHome()
        let projects = home.url.appendingPathComponent(".claude/projects")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        }
        try home.write("{}", to: ".codex/sessions/2026/11/01/rollout-a.jsonl", modified: daysAgo(1))

        let spy = SpyReader(home: home.url)
        let context = UsageContextBuilder(reader: spy, home: home.url).build(now: now)

        XCTAssertEqual(context.activeProjects(for: .claudeCode).count, 2, "metadata must still work on unreadable files")
        XCTAssertFalse(spy.contentReads.contains { $0.pathExtension == "jsonl" })
        XCTAssertFalse(spy.contentReads.contains { $0.path.contains("/.claude/projects/") || $0.path.contains("/.codex/sessions/") })
    }

    func testReaderRefusesEverythingButTheAllowlist() throws {
        let home = try makeHome()
        let reader = LocalMetadataReader(home: home.url)
        let session = try home.write("SECRET", to: ".claude/projects/x/a.jsonl")
        let history = try home.write("SECRET", to: ".codex/history.jsonl")
        let database = try home.write("SECRET", to: "Library/Application Support/Cursor/User/workspaceStorage/a/state.vscdb")
        let fake = try home.write("SECRET", to: ".claude/projects/x/workspace.json")
        let traversal = home.url.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/a/../../../../../../.claude/projects/x/workspace.json")
        let deep = try home.write("SECRET", to: "Library/Application Support/Cursor/User/workspaceStorage/a/b/workspace.json")
        let link = home.url.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/b/workspace.json")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: session)
        for url in [session, history, database, fake, traversal, deep, link] {
            XCTAssertNil(reader.readMetadataFile(url), url.path)
        }
        XCTAssertNotNil(reader.readMetadataFile(home.url.appendingPathComponent(".claude.json")))
    }

    /// Guards the rule at the source level: only the reader may open files, and only through its allowlist.
    func testUsageSourcesContainNoOtherFileReads() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Sources/WardenCore/Usage")
        let forbidden = ["contentsOf:", "FileHandle", "InputStream", "fopen", "mmap", "contentsAtPath"]
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                let occurrences = source.components(separatedBy: token).count - 1
                let allowed = file.lastPathComponent == "MetadataReader.swift" && token == "contentsOf:" ? 2 : 0
                XCTAssertLessThanOrEqual(occurrences, allowed, "\(file.lastPathComponent) uses \(token)")
            }
        }
    }
}
