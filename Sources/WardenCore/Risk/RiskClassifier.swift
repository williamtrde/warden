import Foundation

/// Turns the changes of a file into risk findings. Pure: no I/O, no model involved.
public enum RiskClassifier {
    /// Classifies structural changes. Changes matching no rule become one `otherChange` finding each.
    public static func classify(
        changes: [ConfigChange],
        old: ConfigValue?,
        new: ConfigValue?,
        rules: [ConfigRule] = ConfigRules.all
    ) -> [RiskFinding] {
        var findings: [RiskFinding] = []
        for change in changes {
            let input = ConfigRuleInput(
                change: change,
                scopedPath: scopedPath(change.path),
                oldDocument: old,
                newDocument: new
            )
            let project = projectPath(change.path)
            let matched = rules.filter { $0.matches(input) }
            if matched.isEmpty {
                findings.append(.init(rule: .otherChange, keyPath: change.path, evidence: change.dottedPath, projectPath: project))
            }
            for rule in matched {
                let evidence = "\(change.dottedPath) = \(input.text)"
                findings.append(.init(rule: rule.id, keyPath: change.path, evidence: evidence, projectPath: project, value: input.text))
            }
        }
        return findings
    }

    /// Removes the `projects.<path>.` or `profiles.<name>.` prefix, so that one rule covers every scope.
    static func scopedPath(_ path: [String]) -> [String] {
        path.count > 2 && ["projects", "profiles"].contains(path[0]) ? Array(path.dropFirst(2)) : path
    }

    static func projectPath(_ path: [String]) -> String? {
        path.count > 2 && path[0] == "projects" ? path[1] : nil
    }
}
