import Foundation

/// A file Warden knows how to protect.
public struct WatchTarget: Equatable, Sendable, Identifiable {
    /// Path relative to the home directory, or absolute for files outside of it.
    public let path: String
    public let agent: Agent
    public let format: FileFormat
    public let policy: WatchPolicy

    public var id: String { path }

    public init(path: String, agent: Agent, format: FileFormat, policy: WatchPolicy) {
        self.path = path
        self.agent = agent
        self.format = format
        self.policy = policy
    }

    public var displayName: String {
        path.hasPrefix("/") ? path : "~/\(path)"
    }

    public func url(home: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
    }
}

/// The single source of truth for what Warden watches and which keys trigger an alert.
/// To support a new file or key, edit this file only; the README table is checked against it.
public enum WatchCatalog {
    /// Keys Claude Code reads from `~/.claude.json`, at top level and per project.
    public static let claudeStateKeys: [String] = [
        "mcpServers/**",
        "mcpContextUris/**",
        "enabledMcpjsonServers/**",
        "disabledMcpjsonServers/**",
        "enableAllProjectMcpServers",
        "allowedTools/**",
        "hasTrustDialogAccepted",
        "hasClaudeMdExternalIncludesApproved",
        "bypassPermissionsModeAccepted",
        "skipDangerousModePermissionPrompt",
        "customApiKeyResponses/**",
        "env/**",
        "hooks/**",
        "permissions/**",
        "apiKeyHelper",
        "otelHeadersHelper",
        "enabledPlugins/**",
        "extraKnownMarketplaces/**"
    ]

    /// Cursor settings related to AI, agents, MCP, the network and the terminal.
    /// Themes, fonts and editor preferences stay silent.
    public static let cursorSettingsKeys: [String] = [
        "cursor*/**",
        "aiSettings*/**",
        "chat.*/**",
        "mcp*/**",
        "github.copilot*/**",
        "http.proxy*",
        "security.workspace.trust.*",
        "task.allowAutomaticTasks",
        "terminal.integrated.env.*/**",
        "terminal.integrated.profiles.*/**",
        "terminal.integrated.defaultProfile.*",
        "terminal.integrated.automationProfile.*/**",
        "terminal.integrated.shell*/**",
        "terminal.external.*"
    ]

    static var claudeStatePolicy: WatchPolicy {
        .filtered(claudeStateKeys.flatMap { [PathPattern($0), PathPattern("projects/*/\($0)")] })
    }

    static var cursorSettingsPolicy: WatchPolicy {
        .filtered(cursorSettingsKeys.map(PathPattern.init))
    }

    public static let defaultTargets: [WatchTarget] = [
        .init(path: ".claude/settings.json", agent: .claudeCode, format: .json, policy: .everyChange),
        .init(path: ".claude/settings.local.json", agent: .claudeCode, format: .json, policy: .everyChange),
        .init(path: ".claude.json", agent: .claudeCode, format: .json, policy: claudeStatePolicy),
        .init(path: ".claude/CLAUDE.md", agent: .claudeCode, format: .instructions, policy: .everyChange),
        .init(path: ".codex/config.toml", agent: .codex, format: .toml, policy: .everyChange),
        .init(path: ".codex/AGENTS.md", agent: .codex, format: .instructions, policy: .everyChange),
        .init(path: ".cursor/mcp.json", agent: .cursor, format: .json, policy: .everyChange),
        .init(
            path: "Library/Application Support/Cursor/User/settings.json",
            agent: .cursor,
            format: .jsonc,
            policy: cursorSettingsPolicy
        )
    ]

    /// Builds a target for a file the user adds by hand: every change alerts.
    public static func customTarget(url: URL, home: URL) -> WatchTarget {
        let homePath = home.standardizedFileURL.path + "/"
        let fullPath = url.standardizedFileURL.path
        let path = fullPath.hasPrefix(homePath) ? String(fullPath.dropFirst(homePath.count)) : fullPath
        return WatchTarget(
            path: path,
            agent: agent(forPath: path),
            format: FileFormat.guess(fromFileName: url.lastPathComponent),
            policy: .everyChange
        )
    }

    private static func agent(forPath path: String) -> Agent {
        if path.hasPrefix(".claude") { return .claudeCode }
        if path.hasPrefix(".codex") { return .codex }
        if path.hasPrefix(".cursor") || path.contains("/Cursor/") { return .cursor }
        return .other
    }
}
