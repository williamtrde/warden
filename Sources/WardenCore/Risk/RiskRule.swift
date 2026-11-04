import Foundation

/// Identifies why a change was classified the way it was.
/// Adding a rule: add a case here, then implement it in `ConfigRules` or `InstructionRules`,
/// then add its wording in `FallbackTemplates`. Tests fail if a case has no wording.
public enum RuleID: String, Codable, CaseIterable, Sendable {
    // Configuration files.
    case hookChanged
    case mcpServerAdded
    case mcpServerChanged
    case sensitiveEnvironment
    case credentialHelper
    case commandSetting
    case allProjectMcpServersEnabled
    case projectMcpServerApproved
    case permissionWidened
    case projectTrustGranted
    case pluginAdded
    // Instruction files.
    case hiddenText
    case bypassInstruction
    case remoteCodeExecution
    case secretAccess
    case encodedPayload
    case shellCommandMentioned
    case urlMentioned
    // Whole file events and catch-all.
    case fileCreated
    case fileDeleted
    case malformedConfig
    case otherChange

    public var severity: Severity {
        switch self {
        case .hookChanged, .mcpServerAdded, .mcpServerChanged, .sensitiveEnvironment, .credentialHelper, .commandSetting,
             .allProjectMcpServersEnabled, .projectMcpServerApproved, .permissionWidened, .projectTrustGranted,
             .pluginAdded, .hiddenText, .bypassInstruction, .remoteCodeExecution, .secretAccess, .encodedPayload,
             .malformedConfig:
            // A file Warden cannot read may still be read by the agent, so it gets no benefit of the doubt.
            return .critical
        case .shellCommandMentioned, .urlMentioned, .fileCreated, .fileDeleted, .otherChange:
            return .info
        }
    }

    /// Rules that deserve a highlight in the diff even though they are informational.
    public var isNotable: Bool {
        self == .shellCommandMentioned || self == .urlMentioned
    }
}

/// One reason a change was flagged.
public struct RiskFinding: Equatable, Codable, Sendable {
    public let rule: RuleID
    /// Key path for configuration files; nil for instruction files.
    public let keyPath: [String]?
    /// The exact text that triggered the rule. May contain secrets: mask before displaying.
    public let evidence: String
    /// Set when the change targets a single project, as in `projects.<path>.mcpServers`.
    public let projectPath: String?
    /// The changed value, without its key, used to find the line to highlight.
    public let value: String?

    public init(rule: RuleID, keyPath: [String]? = nil, evidence: String, projectPath: String? = nil, value: String? = nil) {
        self.rule = rule
        self.keyPath = keyPath
        self.evidence = evidence
        self.projectPath = projectPath
        self.value = value
    }

    /// A copy safe to store and display.
    var masked: RiskFinding {
        RiskFinding(
            rule: rule,
            keyPath: keyPath,
            evidence: SecretRedactor.redact(evidence),
            projectPath: projectPath,
            value: value.map(SecretRedactor.redact)
        )
    }

    public var severity: Severity { rule.severity }
}

extension Array where Element == RiskFinding {
    /// The worst severity among the findings.
    public var severity: Severity { map(\.severity).max() ?? .info }

    /// Rules in priority order: critical first, without duplicates.
    public var orderedRules: [RuleID] {
        var seen = Set<RuleID>()
        let unique = map(\.rule).filter { seen.insert($0).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return RuleID.allCases.firstIndex(of: lhs) ?? 0 < RuleID.allCases.firstIndex(of: rhs) ?? 0
        }
    }
}
