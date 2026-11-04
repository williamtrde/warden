@testable import WardenCore
import XCTest

final class PathPatternTests: XCTestCase {
    func testLiteralAndWildcard() {
        XCTAssertTrue(PathPattern("projects/*/mcpServers").matches(["projects", "/a.b/c", "mcpServers"]))
        XCTAssertFalse(PathPattern("projects/*/mcpServers").matches(["projects", "mcpServers"]))
    }

    func testDeepWildcardIncludesTheNodeItself() {
        XCTAssertTrue(PathPattern("hooks/**").matches(["hooks"]))
        XCTAssertTrue(PathPattern("hooks/**").matches(["hooks", "a", "0", "b"]))
        XCTAssertFalse(PathPattern("hooks/**").matches(["hook"]))
    }

    func testPrefixSegmentAndDottedKeys() {
        XCTAssertTrue(PathPattern("terminal.integrated.env.*/**").matches(["terminal.integrated.env.osx", "PATH"]))
        XCTAssertFalse(PathPattern("terminal.integrated.env.*/**").matches(["terminal.integrated.fontSize"]))
    }
}

final class WatchPolicyTests: XCTestCase {
    private var claudeState: WatchTarget { WatchCatalog.defaultTargets.first { $0.path == ".claude.json" }! }
    private var cursorSettings: WatchTarget { WatchCatalog.defaultTargets.first { $0.format == .jsonc }! }

    private func relevant(_ target: WatchTarget, _ old: String, _ new: String) throws -> [ConfigChange] {
        let changes = StructuralDiff.compute(
            old: try ConfigParser.parse(Data(old.utf8), format: target.format),
            new: try ConfigParser.parse(Data(new.utf8), format: target.format)
        )
        return target.policy.relevantChanges(in: changes)
    }

    func testCatalogCoversTheEightFilesOfTheBrief() {
        XCTAssertEqual(WatchCatalog.defaultTargets.count, 8)
        XCTAssertEqual(WatchCatalog.defaultTargets.filter(\.policy.isFiltered).count, 2)
    }

    func testHundredRoutineClaudeWritesAreSilent() throws {
        var previous = #"{"numStartups":0,"projects":{"/p":{"lastCost":0,"allowedTools":[]}}}"#
        for count in 1...100 {
            let next = """
            {"numStartups":\(count),"tipsHistory":{"tip\(count)":\(count)},"cachedGrowthBookFeatures":{"f":\(count)},\
            "changelogLastFetched":\(count),"skillUsage":{"build":{"n":\(count)}},\
            "projects":{"/p":{"lastCost":\(count),"lastSessionId":"s\(count)","lastModelUsage":{"m":\(count)},"allowedTools":[]},\
            "/new\(count)":{"allowedTools":[],"mcpServers":{},"enabledMcpjsonServers":[],"disabledMcpjsonServers":[],\
            "hasTrustDialogAccepted":false,"mcpContextUris":[]}}}
            """
            XCTAssertEqual(try relevant(claudeState, previous, next), [])
            previous = next
        }
    }

    func testSecurityKeysAreWatchedAtBothLevels() throws {
        for key in ["mcpServers", "env", "hooks", "permissions"] {
            XCTAssertFalse(try relevant(claudeState, "{}", #"{"\#(key)":{"x":"y"}}"#).isEmpty, key)
            XCTAssertFalse(try relevant(claudeState, #"{"projects":{"/p":{}}}"#, #"{"projects":{"/p":{"\#(key)":{"x":"y"}}}}"#).isEmpty, key)
        }
        for key in ["enabledMcpjsonServers", "disabledMcpjsonServers", "allowedTools"] {
            XCTAssertFalse(try relevant(claudeState, #"{"projects":{"/p":{}}}"#, #"{"projects":{"/p":{"\#(key)":["x"]}}}"#).isEmpty, key)
        }
        XCTAssertFalse(try relevant(
            claudeState,
            #"{"projects":{"/p":{"hasTrustDialogAccepted":false}}}"#,
            #"{"projects":{"/p":{"hasTrustDialogAccepted":true}}}"#
        ).isEmpty)
    }

    func testCursorThemeAndFontStaySilent() throws {
        let new = #"{"workbench.colorTheme":"Dark","editor.fontSize":14,"terminal.integrated.fontSize":13}"#
        XCTAssertEqual(try relevant(cursorSettings, "{}", new), [])
    }

    func testCursorAIAndTerminalKeysAlert() throws {
        let cases = [
            #"{"cursor.composer.shouldAutoRun":true}"#,
            #"{"chat.tools.autoApprove":true}"#,
            #"{"mcp":{"servers":{"x":{"url":"http://x"}}}}"#,
            #"{"terminal.integrated.env.osx":{"HTTPS_PROXY":"http://x"}}"#,
            #"{"terminal.integrated.defaultProfile.osx":"evil"}"#,
            #"{"http.proxy":"http://x"}"#
        ]
        for new in cases {
            XCTAssertFalse(try relevant(cursorSettings, "{}", new).isEmpty, new)
        }
    }

    func testProjectionKeepsOnlyWatchedKeys() throws {
        let value = try ConfigParser.parse(
            Data(#"{"numStartups":1,"mcpServers":{"a":{"url":"u"}},"projects":{"/p":{"lastCost":1,"allowedTools":["x"]},"/q":{"lastCost":1}}}"#.utf8),
            format: .json
        )
        let projected = claudeState.policy.projection(of: value)
        XCTAssertNil(projected.value(at: ["numStartups"]))
        XCTAssertNotNil(projected.value(at: ["mcpServers", "a", "url"]))
        XCTAssertNotNil(projected.value(at: ["projects", "/p", "allowedTools"]))
        XCTAssertNil(projected.value(at: ["projects", "/p", "lastCost"]))
        XCTAssertNil(projected.value(at: ["projects", "/q"]))
    }

    func testEveryChangePolicyKeepsEverything() {
        let change = ConfigChange(kind: .added, path: ["theme"], oldValue: nil, newValue: .string("x"))
        XCTAssertEqual(WatchPolicy.everyChange.relevantChanges(in: [change]), [change])
    }

    func testCustomTargetGuessesFromPath() {
        let home = URL(fileURLWithPath: "/tmp/h")
        let target = WatchCatalog.customTarget(url: URL(fileURLWithPath: "/tmp/h/.codex/rules.toml"), home: home)
        XCTAssertEqual(target.path, ".codex/rules.toml")
        XCTAssertEqual(target.agent, .codex)
        XCTAssertEqual(target.format, .toml)
        XCTAssertEqual(WatchCatalog.customTarget(url: URL(fileURLWithPath: "/etc/x.json"), home: home).path, "/etc/x.json")
    }
}
