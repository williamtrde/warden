import Foundation

/// What a config rule can look at.
public struct ConfigRuleInput: Sendable {
    public let change: ConfigChange
    /// The change path with any `projects.<path>.` prefix removed, so that a rule
    /// written once covers both global and per-project settings.
    public let scopedPath: [String]
    public let oldDocument: ConfigValue?
    public let newDocument: ConfigValue?

    var head: String { scopedPath.first ?? "" }
    var isRemoval: Bool { change.kind == .removed }
    var newBool: Bool? { change.newValue?.boolValue }
    var newString: String? { change.newValue?.stringValue }
    /// The string this change introduces or takes away.
    var text: String { (change.newValue ?? change.oldValue)?.displayString ?? "" }

    /// The prefix of `change.path` removed to compute `scopedPath`.
    var scopePrefix: [String] { Array(change.path.prefix(change.path.count - scopedPath.count)) }
}

/// A single classification rule for structured configuration files.
public struct ConfigRule: Sendable {
    public let id: RuleID
    public let matches: @Sendable (ConfigRuleInput) -> Bool

    public init(id: RuleID, matches: @escaping @Sendable (ConfigRuleInput) -> Bool) {
        self.id = id
        self.matches = matches
    }
}

/// Critical rules for JSON and TOML configuration. Everything that matches none of them is INFO.
public enum ConfigRules {
    public static let all: [ConfigRule] = [
        hooks, mcpServerAdded, mcpServerChanged, sensitiveEnvironment, credentialHelper, commandSetting,
        allProjectMcpServers, projectMcpServerApproved, permissionWidened, projectTrust, pluginAdded
    ]

    /// Runs on `hooks.*`, including Codex `hooks.state` trust hashes, and on Codex `notify`.
    static let hooks = ConfigRule(id: .hookChanged) { input in
        if input.head == "disableAllHooks" { return input.newBool == true }
        return !input.isRemoval && (input.head == "hooks" || input.head == "notify")
    }

    static let mcpServerAdded = ConfigRule(id: .mcpServerAdded) { input in
        guard !input.isRemoval, let server = mcpServerPath(input) else { return false }
        return input.oldDocument?.value(at: input.scopePrefix + server) == nil
    }

    /// Any change to an existing server counts, unless the field is known to be harmless:
    /// a denylist of dangerous fields would silently miss each new way to configure a server.
    static let mcpServerChanged = ConfigRule(id: .mcpServerChanged) { input in
        guard let server = mcpServerPath(input), input.scopedPath.count > server.count else { return false }
        guard input.oldDocument?.value(at: input.scopePrefix + server) != nil,
              input.newDocument?.value(at: input.scopePrefix + server) != nil else { return false }
        return !harmlessMcpKeys.contains(input.scopedPath[server.count])
    }

    private static let harmlessMcpKeys: Set<String> = [
        "timeout", "startup_timeout_sec", "startup_timeout_ms", "tool_timeout_sec", "description", "name"
    ]

    /// Returns the scoped path of the server a change belongs to.
    private static func mcpServerPath(_ input: ConfigRuleInput) -> [String]? {
        let path = input.scopedPath
        if ["mcpServers", "mcp_servers", "mcp.servers"].contains(input.head), path.count >= 2 {
            return Array(path.prefix(2))
        }
        if input.head == "mcp", path.count >= 3, path[1] == "servers" {
            return Array(path.prefix(3))
        }
        return nil
    }

    static let sensitiveEnvironment = ConfigRule(id: .sensitiveEnvironment) { input in
        let path = input.scopedPath
        if let name = environmentVariableName(path) {
            return isSensitiveVariable(name)
        }
        if ["openai_base_url", "chatgpt_base_url", "http.proxy", "model_provider"].contains(input.head) { return !input.isRemoval }
        if input.head == "http.proxyStrictSSL" { return input.newBool == false }
        if input.head == "shell_environment_policy", path.last == "inherit" { return input.newString == "all" }
        if input.head == "otel" { return path.last == "endpoint" }
        return input.head == "model_providers" && path.last == "base_url"
    }

    private static func environmentVariableName(_ path: [String]) -> String? {
        guard let head = path.first else { return nil }
        let isEnvironment = head == "env" || head.hasPrefix("terminal.integrated.env.") || head == "claudeCode.environmentVariables"
        if path.count >= 2, isEnvironment { return path[1] }
        if path.count == 3, head == "shell_environment_policy", path[1] == "set" { return path[2] }
        return nil
    }

    private static let sensitiveVariables: Set<String> = [
        "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_CUSTOM_HEADERS", "OPENAI_API_BASE", "OPENAI_API_KEY",
        "CLAUDE_CODE_API_KEY_HELPER_TTL_MS", "CLAUDE_CODE_SHELL_PREFIX", "OTEL_EXPORTER_OTLP_HEADERS",
        "NODE_EXTRA_CA_CERTS", "NODE_TLS_REJECT_UNAUTHORIZED", "SSL_CERT_FILE", "REQUESTS_CA_BUNDLE",
        "BASH_ENV", "ENV", "ZDOTDIR", "PATH", "PYTHONPATH", "PYTHONSTARTUP"
    ]

    private static func isSensitiveVariable(_ name: String) -> Bool {
        let upper = name.uppercased()
        if sensitiveVariables.contains(upper) { return true }
        let suffixes = ["_PROXY", "_BASE_URL", "_ENDPOINT", "_OPTIONS"]
        return suffixes.contains(where: upper.hasSuffix) || upper.hasPrefix("DYLD_") || upper.hasPrefix("LD_")
    }

    static let credentialHelper = ConfigRule(id: .credentialHelper) { input in
        let helpers: Set<String> = ["apiKeyHelper", "otelHeadersHelper", "awsAuthRefresh", "awsCredentialExport", "gcpAuthRefresh"]
        return !input.isRemoval && helpers.contains(input.head)
    }

    /// Settings that name a program or a file the agent will execute or obey.
    static let commandSetting = ConfigRule(id: .commandSetting) { input in
        guard !input.isRemoval else { return false }
        let commands: Set<String> = ["statusLine", "fileSuggestion"]
        if commands.contains(input.head) { return input.scopedPath.last == "command" }
        return ["experimental_instructions_file", "claudeCode.claudeProcessWrapper"].contains(input.head)
    }

    static let allProjectMcpServers = ConfigRule(id: .allProjectMcpServersEnabled) { input in
        input.head == "enableAllProjectMcpServers" && input.newBool == true
    }

    static let projectMcpServerApproved = ConfigRule(id: .projectMcpServerApproved) { input in
        switch input.head {
        case "enabledMcpjsonServers": return input.change.kind == .added
        case "disabledMcpjsonServers": return input.isRemoval
        default: return false
        }
    }

    static let permissionWidened = ConfigRule(id: .permissionWidened) { input in
        let path = input.scopedPath
        switch input.head {
        case "permissions":
            return claudePermissionWidened(input, path: path)
        case "allowedTools":
            return input.change.kind == .added && isPowerfulToolRule(input.text)
        case "bypassPermissionsModeAccepted", "skipDangerousModePermissionPrompt":
            return input.newBool == true
        case "approval_policy":
            return input.newString == "never"
        case "profile", "claudeCode.initialPermissionMode":
            return !input.isRemoval // A profile can carry its own approval and sandbox policy.
        case "sandbox_mode":
            return !input.isRemoval && input.newString != "read-only"
        case "sandbox_workspace_write":
            if path.last == "network_access" { return input.newBool == true }
            return path.contains("writable_roots") && input.change.kind == .added
        case "sandbox":
            return path.last == "enabled" && input.newBool == false
        case "security.workspace.trust.enabled":
            return input.newBool == false
        default:
            return isEditorAutoRun(input)
        }
    }

    private static func claudePermissionWidened(_ input: ConfigRuleInput, path: [String]) -> Bool {
        guard path.count >= 2 else { return false }
        switch path[1] {
        case "defaultMode":
            return ["bypassPermissions", "dontAsk", "acceptEdits"].contains(input.newString ?? "")
        case "allow":
            return input.change.kind == .added && isPowerfulToolRule(input.text)
        case "deny", "ask":
            return input.isRemoval
        case "additionalDirectories":
            return input.change.kind == .added
        case "disableBypassPermissionsMode":
            return input.isRemoval
        default:
            return false
        }
    }

    /// `Bash(...)`, network tools, every MCP tool, an unrestricted wildcard, or anything on sensitive paths.
    private static func isPowerfulToolRule(_ rule: String) -> Bool {
        let tool = rule.prefix { $0 != "(" }.trimmingCharacters(in: .whitespaces)
        if ["Bash", "WebFetch", "WebSearch", "*", "mcp__*"].contains(tool) { return true }
        let sensitivePaths = [".claude", ".codex", ".cursor", ".ssh", ".aws", ".env", ".gnupg", ".netrc", ".npmrc"]
        return rule.contains("(") && sensitivePaths.contains(where: rule.contains)
    }

    private static func isEditorAutoRun(_ input: ConfigRuleInput) -> Bool {
        guard input.newBool == true else { return false }
        let key = input.scopedPath.joined(separator: ".").lowercased()
        return ["autoapprove", "autorun", "yolo", "dangerouslyskip"].contains { key.contains($0) }
    }

    static let projectTrust = ConfigRule(id: .projectTrustGranted) { input in
        switch input.head {
        case "hasTrustDialogAccepted", "hasClaudeMdExternalIncludesApproved": return input.newBool == true
        case "trust_level": return input.newString == "trusted"
        default: return false
        }
    }

    static let pluginAdded = ConfigRule(id: .pluginAdded) { input in
        switch input.head {
        case "enabledPlugins":
            guard input.scopedPath.count >= 2 else { return false }
            return !input.isRemoval && input.newBool != false
        case "extraKnownMarketplaces", "marketplaces":
            return !input.isRemoval
        case "plugins":
            return !input.isRemoval && input.newBool != false
        default:
            return false
        }
    }
}
