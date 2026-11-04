import Foundation

/// What Warden knows about one project, from metadata only.
public struct ProjectUsage: Equatable, Codable, Sendable, Identifiable {
    public let path: String
    public let name: String
    public let agent: Agent
    public let lastUsed: Date?
    public let sessionsInWindow: Int

    public var id: String { "\(agent.rawValue):\(path)" }

    public init(path: String, name: String, agent: Agent, lastUsed: Date?, sessionsInWindow: Int) {
        self.path = path
        self.name = name
        self.agent = agent
        self.lastUsed = lastUsed
        self.sessionsInWindow = sessionsInWindow
    }
}

/// The projects a change reaches, ready to be put into words.
public struct AffectedScope: Equatable, Sendable {
    public let agent: Agent
    public let projects: [ProjectUsage]
    /// Number of projects beyond `projects`, for "and 3 others".
    public let otherCount: Int
    /// True when the change targets one project rather than the agent as a whole.
    public let isSingleProject: Bool
    /// Most recent use among `projects`.
    public let lastUsed: Date?

    public init(agent: Agent, projects: [ProjectUsage], otherCount: Int, isSingleProject: Bool, lastUsed: Date?) {
        self.agent = agent
        self.projects = projects
        self.otherCount = otherCount
        self.isSingleProject = isSingleProject
        self.lastUsed = lastUsed
    }
}

/// A picture of which agents are used on which projects.
public struct UsageContext: Equatable, Sendable {
    public static let activeWindow: TimeInterval = 14 * 24 * 3600
    private static let namedProjectLimit = 3

    public let projects: [ProjectUsage]
    /// Last session date per agent, known even when it cannot be tied to a project (Codex).
    public let lastAgentActivity: [Agent: Date]
    public let date: Date

    public init(projects: [ProjectUsage], lastAgentActivity: [Agent: Date], date: Date) {
        self.projects = projects
        self.lastAgentActivity = lastAgentActivity
        self.date = date
    }

    public static let empty = UsageContext(projects: [], lastAgentActivity: [:], date: .distantPast)

    private func isRecent(_ value: Date?) -> Bool {
        guard let value else { return false }
        return date.timeIntervalSince(value) <= Self.activeWindow
    }

    /// Projects used in the last 14 days, most recent first. Codex sessions cannot be tied to a
    /// project without reading them, so its known projects count as active when Codex itself is.
    public func activeProjects(for agent: Agent) -> [ProjectUsage] {
        projects
            .filter { $0.agent == agent && (isRecent($0.lastUsed) || ($0.lastUsed == nil && isRecent(lastAgentActivity[agent]))) }
            .sorted {
                if $0.sessionsInWindow != $1.sessionsInWindow, $0.lastUsed == $1.lastUsed {
                    return $0.sessionsInWindow > $1.sessionsInWindow
                }
                return ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast)
            }
    }

    /// The projects reached by a change to `agent`'s configuration.
    public func scope(agent: Agent, projectPath: String?) -> AffectedScope {
        if let projectPath {
            let name = (projectPath as NSString).lastPathComponent
            let known = projects.first { $0.agent == agent && $0.path == projectPath }
            let project = known ?? ProjectUsage(path: projectPath, name: name, agent: agent, lastUsed: nil, sessionsInWindow: 0)
            return AffectedScope(agent: agent, projects: [project], otherCount: 0, isSingleProject: true, lastUsed: project.lastUsed)
        }
        let active = activeProjects(for: agent)
        let named = Array(active.prefix(Self.namedProjectLimit))
        return AffectedScope(
            agent: agent,
            projects: named,
            otherCount: active.count - named.count,
            isSingleProject: false,
            lastUsed: named.compactMap(\.lastUsed).max() ?? lastAgentActivity[agent]
        )
    }
}
