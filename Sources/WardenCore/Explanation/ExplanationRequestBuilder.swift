import Foundation

/// Turns an analysis into the input of an explanation generator.
enum ExplanationRequestBuilder {
    private static let maxDetailLength = 60

    static func make(
        target: WatchTarget,
        analysis: ChangeAnalysis,
        usage: UsageContext,
        language: ExplanationLanguage,
        date: Date
    ) -> ExplanationRequest {
        let findings = analysis.findings
        let projects = Set(findings.compactMap(\.projectPath))
        var details: [RuleID: String] = [:]
        for finding in findings where details[finding.rule] == nil {
            details[finding.rule] = detail(of: finding)
        }
        return ExplanationRequest(
            fileName: target.displayName,
            agent: target.agent,
            severity: analysis.severity,
            rules: findings.orderedRules,
            details: details,
            changeCount: findings.count,
            maskedDiff: analysis.diff.unifiedText,
            scope: usage.scope(agent: target.agent, projectPath: projects.count == 1 ? projects.first : nil),
            language: language,
            date: date
        )
    }

    /// A short name for what changed: the server, the variable, the plugin.
    static func detail(of finding: RiskFinding) -> String {
        let raw: String
        if let keyPath = finding.keyPath {
            raw = keyDetail(rule: finding.rule, scoped: RiskClassifier.scopedPath(keyPath), value: finding.value)
        } else {
            raw = textDetail(rule: finding.rule, evidence: finding.evidence)
        }
        let masked = SecretRedactor.redact(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return masked.count > maxDetailLength ? String(masked.prefix(maxDetailLength - 1)) + "…" : masked
    }

    private static func keyDetail(rule: RuleID, scoped: [String], value: String?) -> String {
        func segment(_ index: Int) -> String { scoped.indices.contains(index) ? scoped[index] : scoped.last ?? "" }
        switch rule {
        case .hookChanged:
            return segment(scoped.first == "hooks" && scoped.count > 2 && scoped[1] == "state" ? 2 : 1)
        case .mcpServerAdded, .mcpServerChanged:
            return scoped.first == "mcp" ? segment(2) : segment(1)
        case .pluginAdded:
            return segment(1)
        case .sensitiveEnvironment:
            return scoped.last ?? ""
        case .credentialHelper:
            return segment(0)
        case .permissionWidened, .projectMcpServerApproved:
            return scoped.last == StructuralDiff.setElement ? (value ?? "") : scoped.joined(separator: ".")
        default:
            return scoped.filter { $0 != StructuralDiff.setElement }.joined(separator: ".")
        }
    }

    private static func textDetail(rule: RuleID, evidence: String) -> String {
        switch rule {
        case .urlMentioned:
            return InstructionPatterns.url.firstMatch(in: evidence) ?? ""
        case .shellCommandMentioned:
            return evidence.trimmingCharacters(in: CharacterSet(charactersIn: "$` \t"))
        default:
            return ""
        }
    }
}
