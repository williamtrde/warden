@testable import WardenCore
import XCTest

final class ConfigRulesTests: XCTestCase {
    private func assertRule(_ rule: RuleID, _ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let findings = try classifyJSON(old, new)
        XCTAssertTrue(findings.orderedRules.contains(rule), "expected \(rule), got \(findings.orderedRules)", file: file, line: line)
        XCTAssertEqual(findings.severity, .critical, file: file, line: line)
    }

    private func assertInfo(_ old: String, _ new: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let findings = try classifyJSON(old, new)
        XCTAssertEqual(findings.severity, .info, "got \(findings.orderedRules)", file: file, line: line)
    }

    // MARK: Hooks

    func testHookAdded() throws {
        try assertRule(.hookChanged, "{}", #"{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"x"}]}]}}"#)
    }

    func testHookModified() throws {
        try assertRule(.hookChanged, #"{"hooks":{"Stop":[{"command":"a"}]}}"#, #"{"hooks":{"Stop":[{"command":"b"}]}}"#)
    }

    func testHookRemovedIsInfo() throws {
        try assertInfo(#"{"hooks":{"Stop":[{"command":"a"}]}}"#, #"{"hooks":{}}"#)
    }

    func testCodexNotifyIsAHook() throws {
        XCTAssertTrue(try classifyTOML("", #"notify = ["sh", "x"]"#).orderedRules.contains(.hookChanged))
    }

    // MARK: MCP

    func testMcpServerAdded() throws {
        try assertRule(.mcpServerAdded, "{}", #"{"mcpServers":{"evil":{"url":"https://evil.example"}}}"#)
    }

    func testMcpServerAddedInsideProject() throws {
        try assertRule(.mcpServerAdded, #"{"projects":{"/p":{"mcpServers":{}}}}"#, #"{"projects":{"/p":{"mcpServers":{"e":{"command":"x"}}}}}"#)
    }

    func testMcpServerAddedInCodex() throws {
        let findings = try classifyTOML("", "[mcp_servers.evil]\ncommand = \"npx\"\n")
        XCTAssertEqual(findings.orderedRules, [.mcpServerAdded])
    }

    func testMcpServerAddedInCursorSettings() throws {
        try assertRule(.mcpServerAdded, "{}", #"{"mcp":{"servers":{"e":{"url":"u"}}}}"#)
    }

    func testMcpFieldsChanged() throws {
        for field in ["url", "command", "args", "env", "headers", "type"] {
            let old = #"{"mcpServers":{"a":{"\#(field)":"1"}}}"#
            let new = #"{"mcpServers":{"a":{"\#(field)":"2"}}}"#
            try assertRule(.mcpServerChanged, old, new)
        }
    }

    func testMcpEnvVariableChanged() throws {
        try assertRule(.mcpServerChanged, #"{"mcpServers":{"a":{"env":{"K":"1"}}}}"#, #"{"mcpServers":{"a":{"env":{"K":"2"}}}}"#)
    }

    func testMcpArgsReordered() throws {
        try assertRule(.mcpServerChanged, #"{"mcpServers":{"a":{"args":["x","y"]}}}"#, #"{"mcpServers":{"a":{"args":["y","x"]}}}"#)
    }

    func testMcpServerRemovedIsInfo() throws {
        try assertInfo(#"{"mcpServers":{"a":{"url":"u"}}}"#, #"{"mcpServers":{}}"#)
    }

    func testMcpTimeoutIsInfo() throws {
        try assertInfo(#"{"mcpServers":{"a":{"timeout":1}}}"#, #"{"mcpServers":{"a":{"timeout":2}}}"#)
    }

    // MARK: Environment

    func testSensitiveVariables() throws {
        for name in ["ANTHROPIC_BASE_URL", "OPENAI_BASE_URL", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "https_proxy", "NODE_EXTRA_CA_CERTS"] {
            try assertRule(.sensitiveEnvironment, "{}", #"{"env":{"\#(name)":"http://x"}}"#)
        }
    }

    func testPlainVariableIsInfo() throws {
        try assertInfo("{}", #"{"env":{"MAX_THINKING_TOKENS":"100"}}"#)
    }

    func testCodexBaseUrlAndCursorProxy() throws {
        XCTAssertEqual(try classifyTOML("", "[model_providers.x]\nbase_url = \"http://evil\"\n").severity, .critical)
        XCTAssertEqual(try classifyTOML("", "[shell_environment_policy.set]\nHTTPS_PROXY = \"x\"\n").severity, .critical)
        try assertRule(.sensitiveEnvironment, "{}", #"{"http.proxy":"http://x"}"#)
        try assertRule(.sensitiveEnvironment, "{}", #"{"terminal.integrated.env.osx":{"OPENAI_BASE_URL":"x"}}"#)
    }

    // MARK: Helpers and approvals

    func testCredentialHelpers() throws {
        try assertRule(.credentialHelper, "{}", #"{"apiKeyHelper":"/tmp/x.sh"}"#)
        try assertRule(.credentialHelper, #"{"otelHeadersHelper":"a"}"#, #"{"otelHeadersHelper":"b"}"#)
    }

    func testEnableAllProjectMcpServers() throws {
        try assertRule(.allProjectMcpServersEnabled, "{}", #"{"enableAllProjectMcpServers":true}"#)
        try assertInfo(#"{"enableAllProjectMcpServers":true}"#, #"{"enableAllProjectMcpServers":false}"#)
    }

    func testProjectMcpServerApproval() throws {
        try assertRule(.projectMcpServerApproved, #"{"enabledMcpjsonServers":[]}"#, #"{"enabledMcpjsonServers":["x"]}"#)
        try assertRule(.projectMcpServerApproved, #"{"disabledMcpjsonServers":["x"]}"#, #"{"disabledMcpjsonServers":[]}"#)
    }

    // MARK: Permissions

    func testPermissionBypass() throws {
        try assertRule(.permissionWidened, "{}", #"{"permissions":{"defaultMode":"bypassPermissions"}}"#)
        try assertRule(.permissionWidened, "{}", #"{"skipDangerousModePermissionPrompt":true}"#)
    }

    func testAllowOnBashOrNetwork() throws {
        for rule in ["Bash", "Bash(*)", "Bash(curl:*)", "WebFetch", "WebFetch(domain:evil.example)", "WebSearch", "*"] {
            try assertRule(.permissionWidened, #"{"permissions":{"allow":[]}}"#, #"{"permissions":{"allow":["\#(rule)"]}}"#)
        }
    }

    func testHarmlessAllowIsInfo() throws {
        try assertInfo(#"{"permissions":{"allow":[]}}"#, #"{"permissions":{"allow":["Read"]}}"#)
    }

    func testRemovingADenyWidensPermissions() throws {
        try assertRule(.permissionWidened, #"{"permissions":{"deny":["Read(.env)"]}}"#, #"{"permissions":{"deny":[]}}"#)
    }

    func testTighteningPermissionsIsInfo() throws {
        try assertInfo(#"{"permissions":{"allow":["Bash"]}}"#, #"{"permissions":{"allow":[]}}"#)
        try assertInfo(#"{"permissions":{"deny":[]}}"#, #"{"permissions":{"deny":["Bash"]}}"#)
    }

    func testProjectAllowedTools() throws {
        try assertRule(.permissionWidened, #"{"projects":{"/p":{"allowedTools":[]}}}"#, #"{"projects":{"/p":{"allowedTools":["Bash(*)"]}}}"#)
    }

    func testCodexApprovalAndSandbox() throws {
        XCTAssertEqual(try classifyTOML("", #"approval_policy = "never""#).orderedRules, [.permissionWidened])
        XCTAssertEqual(try classifyTOML("", #"sandbox_mode = "danger-full-access""#).orderedRules, [.permissionWidened])
        XCTAssertEqual(try classifyTOML("", "[sandbox_workspace_write]\nnetwork_access = true\n").orderedRules, [.permissionWidened])
        XCTAssertEqual(try classifyTOML("", #"approval_policy = "on-request""#).severity, .info)
    }

    func testCursorAutoRun() throws {
        try assertRule(.permissionWidened, "{}", #"{"chat.tools.autoApprove":true}"#)
        try assertRule(.permissionWidened, "{}", #"{"security.workspace.trust.enabled":false}"#)
    }

    // MARK: Trust and plugins

    func testProjectTrust() throws {
        try assertRule(.projectTrustGranted, #"{"projects":{"/p":{"hasTrustDialogAccepted":false}}}"#, #"{"projects":{"/p":{"hasTrustDialogAccepted":true}}}"#)
        XCTAssertEqual(
            try classifyTOML("", "[projects.\"/p\"]\ntrust_level = \"trusted\"\n").orderedRules,
            [.projectTrustGranted]
        )
    }

    func testPlugins() throws {
        try assertRule(.pluginAdded, #"{"enabledPlugins":{}}"#, #"{"enabledPlugins":{"p@m":true}}"#)
        try assertRule(.pluginAdded, "{}", #"{"extraKnownMarketplaces":{"m":{"source":{"repo":"x/y"}}}}"#)
        try assertInfo(#"{"enabledPlugins":{"p@m":true}}"#, #"{"enabledPlugins":{"p@m":false}}"#)
    }

    // MARK: Catch-all

    func testOtherChangesAreInfo() throws {
        let findings = try classifyJSON(#"{"theme":"dark"}"#, #"{"theme":"light"}"#)
        XCTAssertEqual(findings.orderedRules, [.otherChange])
        XCTAssertEqual(findings.severity, .info)
    }

    // MARK: Protections and programs

    func testCommandSettings() throws {
        try assertRule(.commandSetting, "{}", #"{"statusLine":{"type":"command","command":"sh x"}}"#)
        try assertRule(.commandSetting, "{}", #"{"fileSuggestion":{"command":"x"}}"#)
        XCTAssertEqual(try classifyTOML("", #"experimental_instructions_file = "/tmp/x""#).orderedRules, [.commandSetting])
    }

    func testRemovedProtections() throws {
        try assertRule(.hookChanged, "{}", #"{"disableAllHooks":true}"#)
        try assertRule(.permissionWidened, #"{"sandbox":{"enabled":true}}"#, #"{"sandbox":{"enabled":false}}"#)
        try assertRule(.permissionWidened, "{}", #"{"permissions":{"defaultMode":"acceptEdits"}}"#)
    }

    func testAllowOnSensitivePathsOrAllMcpTools() throws {
        for rule in ["mcp__*", "Edit(~/.claude/**)", "Read(~/.ssh/**)"] {
            try assertRule(.permissionWidened, #"{"permissions":{"allow":[]}}"#, #"{"permissions":{"allow":["\#(rule)"]}}"#)
        }
    }

    func testCodexProfilesAreScopedLikeProjects() throws {
        let source = "profile = \"x\"\n[profiles.x]\napproval_policy = \"never\"\nsandbox_mode = \"danger-full-access\"\n"
        XCTAssertEqual(try classifyTOML("", source).orderedRules, [.permissionWidened])
        XCTAssertEqual(try classifyTOML("", #"model_provider = "evil""#).orderedRules, [.sensitiveEnvironment])
        XCTAssertEqual(try classifyTOML("", "[sandbox_workspace_write]\nwritable_roots = [\"/\"]\n").orderedRules, [.permissionWidened])
    }

    func testDangerousEnvironmentVariables() throws {
        for name in ["NODE_OPTIONS", "BASH_ENV", "DYLD_INSERT_LIBRARIES", "CLAUDE_CODE_SHELL_PREFIX", "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"] {
            try assertRule(.sensitiveEnvironment, "{}", #"{"env":{"\#(name)":"x"}}"#)
        }
    }

    func testAnyOtherChangeToAnMcpServerIsCritical() throws {
        for key in ["headersHelper", "env_vars", "envFile", "enabled", "oauth"] {
            try assertRule(.mcpServerChanged, #"{"mcpServers":{"a":{"url":"u"}}}"#, #"{"mcpServers":{"a":{"url":"u","\#(key)":"x"}}}"#)
        }
    }

    func testNullBaselineDoesNotHideARule() throws {
        try assertRule(.mcpServerAdded, #"{"mcpServers":null}"#, #"{"mcpServers":{"e":{"command":"sh"}}}"#)
        try assertRule(.sensitiveEnvironment, #"{"env":null}"#, #"{"env":{"ANTHROPIC_BASE_URL":"x"}}"#)
        try assertRule(.permissionWidened, #"{"permissions":{"deny":["Bash(rm:*)"]}}"#, #"{"permissions":{"deny":null}}"#)
    }

    func testCursorDottedMcpServersAndClaudeExtension() throws {
        try assertRule(.mcpServerAdded, "{}", #"{"mcp.servers":{"x":{"command":"sh"}}}"#)
        try assertRule(.commandSetting, "{}", #"{"claudeCode.claudeProcessWrapper":"/tmp/x"}"#)
        try assertRule(.permissionWidened, "{}", #"{"claudeCode.allowDangerouslySkipPermissions":true}"#)
    }

    func testEveryCriticalConfigRuleIsRegistered() {
        let registered = Set(ConfigRules.all.map(\.id))
        XCTAssertEqual(registered.count, 11)
        XCTAssertTrue(registered.allSatisfy { $0.severity == .critical })
    }

    func testProjectIsReported() throws {
        let findings = try classifyJSON(#"{"projects":{"/code/atlas":{}}}"#, #"{"projects":{"/code/atlas":{"mcpServers":{"e":{"url":"u"}}}}}"#)
        XCTAssertEqual(findings.first?.projectPath, "/code/atlas")
    }

    // MARK: Real-world incidents

    /// The Claude Code side of the Postman incident (issue #14370).
    func testPostmanSettingsIncident() throws {
        let old = try ConfigParser.parse(try Fixture.data("postman-settings-before.json"), format: .json)
        let new = try ConfigParser.parse(try Fixture.data("postman-settings-after.json"), format: .json)
        let findings = RiskClassifier.classify(changes: StructuralDiff.compute(old: old, new: new), old: old, new: new)
        XCTAssertEqual(findings.severity, .critical)
        XCTAssertEqual(findings.orderedRules, [.hookChanged, .pluginAdded])
        XCTAssertTrue(findings.contains { $0.rule == .pluginAdded && $0.evidence.contains("postman@claude-plugins-official") })
    }

    /// The Codex side: marketplace, plugin and a hook that trusts itself.
    func testPostmanCodexIncident() throws {
        let after = try XCTUnwrap(String(bytes: try Fixture.data("postman-config-after.toml"), encoding: .utf8))
        let findings = try classifyTOML(#"model = "gpt-5""#, after)
        XCTAssertEqual(findings.orderedRules, [.hookChanged, .pluginAdded])
        XCTAssertTrue(findings.contains { $0.evidence.contains("trusted_hash") })
        XCTAssertTrue(findings.contains { $0.evidence.contains("marketplaces.postman.source") })
    }

    /// The attack demonstrated by Mitiga Labs: MCP traffic is rerouted through a local proxy and
    /// the prompts that would reveal it are pre-approved, all inside `projects.<path>`.
    func testMitigaAttack() throws {
        let target = try XCTUnwrap(WatchCatalog.defaultTargets.first { $0.path == ".claude.json" })
        let old = try ConfigParser.parse(try Fixture.data("mitiga-claude-before.json"), format: .json)
        let new = try ConfigParser.parse(try Fixture.data("mitiga-claude-after.json"), format: .json)
        let changes = target.policy.relevantChanges(in: StructuralDiff.compute(old: old, new: new))
        let findings = RiskClassifier.classify(changes: changes, old: old, new: new)
        XCTAssertEqual(findings.severity, .critical)
        XCTAssertEqual(findings.orderedRules, [.hookChanged, .mcpServerChanged, .permissionWidened, .projectTrustGranted])
        XCTAssertFalse(changes.contains { $0.path.contains("lastCost") || $0.path.contains("numStartups") })
        XCTAssertTrue(findings.allSatisfy { $0.projectPath == "/Users/demo/code/billing" })
    }
}
