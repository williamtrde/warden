import Foundation

/// The result of comparing a file with its reference.
public struct ChangeAnalysis: Equatable, Sendable {
    /// Masked findings, safe to store and display.
    public let findings: [RiskFinding]
    /// Diff of masked text, with emphasis applied.
    public let diff: LineDiff
    public let fingerprint: String
    public let isMalformed: Bool

    public var severity: Severity { findings.severity }
}

/// Pure comparison of two versions of a file: parsing, policy, classification and diff.
public enum ChangeAnalyzer {
    /// Agent configs are kilobytes. Anything far beyond that is refused rather than parsed.
    static let maxFileSize = 4_000_000

    /// Returns nil when nothing relevant changed.
    public static func analyze(target: WatchTarget, old: Data?, new: Data?) -> ChangeAnalysis? {
        guard old != new else { return nil }
        if let new, new.count > maxFileSize {
            return ChangeAnalysis(
                findings: [RiskFinding(rule: .malformedConfig, evidence: "")],
                diff: LineDiff(hunks: []),
                fingerprint: WardenStore.hash(new),
                isMalformed: true
            )
        }
        switch target.format {
        case .json, .jsonc, .toml:
            return analyzeStructured(target: target, old: old, new: new)
        case .instructions:
            return analyzeInstructions(old: old, new: new)
        case .plainText:
            return finish(findings: wholeFileFindings(old: old, new: new) ?? [otherChange()], oldText: text(old), newText: text(new))
        }
    }

    private static func text(_ data: Data?) -> String {
        data.map { String(decoding: $0, as: UTF8.self) } ?? "" // swiftlint:disable:this optional_data_string_conversion
    }

    private static func otherChange() -> RiskFinding {
        RiskFinding(rule: .otherChange, evidence: "")
    }

    private static func wholeFileFindings(old: Data?, new: Data?) -> [RiskFinding]? {
        if new == nil { return [RiskFinding(rule: .fileDeleted, evidence: "")] }
        if old == nil { return [RiskFinding(rule: .fileCreated, evidence: "")] }
        return nil
    }

    // MARK: - Structured files

    private static func analyzeStructured(target: WatchTarget, old: Data?, new: Data?) -> ChangeAnalysis? {
        let oldValue = old.flatMap { parse($0, target: target) }
        var newValue: ConfigValue?
        if let new {
            guard let parsed = parse(new, target: target) else {
                return malformed(target: target, oldValue: oldValue, old: old, new: new)
            }
            newValue = parsed
        }

        let all = StructuralDiff.compute(old: oldValue, new: newValue)
        let changes = target.policy.relevantChanges(in: all)
        if target.policy.isFiltered, changes.isEmpty, old != nil, new != nil { return nil }

        var findings = RiskClassifier.classify(changes: changes, old: oldValue, new: newValue)
        if let wholeFile = wholeFileFindings(old: old, new: new) { findings = wholeFile + findings }
        if findings.isEmpty { findings = [otherChange()] } // Formatting only.

        return finish(
            findings: findings,
            oldText: displayText(target: target, value: oldValue, raw: old),
            newText: displayText(target: target, value: newValue, raw: new)
        )
    }

    private static func parse(_ data: Data, target: WatchTarget) -> ConfigValue? {
        guard let value = try? ConfigParser.parse(data, format: target.format) else { return nil }
        return target.format == .jsonc ? target.policy.foldingNestedKeys(of: value) : value
    }

    /// Filtered files show only their watched keys: the rest would drown the signal.
    private static func displayText(target: WatchTarget, value: ConfigValue?, raw: Data?) -> String {
        guard target.policy.isFiltered else { return text(raw) }
        guard let value, let data = try? target.policy.projection(of: value).serialized() else { return "" }
        return text(data)
    }

    private static func malformed(target: WatchTarget, oldValue: ConfigValue?, old: Data?, new: Data) -> ChangeAnalysis {
        let findings = [RiskFinding(rule: .malformedConfig, evidence: "")]
        let newText = target.policy.isFiltered ? "" : text(new)
        let analysis = finish(findings: findings, oldText: displayText(target: target, value: oldValue, raw: old), newText: newText)
        return ChangeAnalysis(findings: analysis.findings, diff: analysis.diff, fingerprint: analysis.fingerprint, isMalformed: true)
    }

    // MARK: - Instruction files

    private static func analyzeInstructions(old: Data?, new: Data?) -> ChangeAnalysis {
        let oldText = text(old)
        let newText = text(new)
        let added = Set(LineDiff.compute(old: oldText, new: newText, context: 0).addedLines.compactMap(\.newNumber))
        var findings = InstructionRules.scan(newText: newText, addedLineNumbers: added)
        if let wholeFile = wholeFileFindings(old: old, new: new) { findings = wholeFile + findings }
        if findings.isEmpty { findings = [otherChange()] }
        return finish(findings: findings, oldText: oldText, newText: newText)
    }

    // MARK: - Shared

    private static func finish(findings: [RiskFinding], oldText: String, newText: String) -> ChangeAnalysis {
        let masked = findings.map(\.masked)
        var diff = LineDiff.compute(old: SecretRedactor.redact(oldText), new: SecretRedactor.redact(newText))
        applyEmphasis(to: &diff, findings: masked)
        return ChangeAnalysis(
            findings: masked,
            diff: diff,
            fingerprint: WardenStore.hash(Data(diff.unifiedText.utf8)),
            isMalformed: false
        )
    }

    private static func applyEmphasis(to diff: inout LineDiff, findings: [RiskFinding]) {
        for hunkIndex in diff.hunks.indices {
            for lineIndex in diff.hunks[hunkIndex].lines.indices {
                let line = diff.hunks[hunkIndex].lines[lineIndex]
                guard line.kind != .context else { continue }
                let matching = findings.filter { $0.severity == .critical || $0.rule.isNotable }.filter { matches($0, line: line.text) }
                if matching.contains(where: { $0.severity == .critical }) {
                    diff.hunks[hunkIndex].lines[lineIndex].emphasis = .critical
                } else if !matching.isEmpty {
                    diff.hunks[hunkIndex].lines[lineIndex].emphasis = .notable
                }
            }
        }
    }

    private static func matches(_ finding: RiskFinding, line: String) -> Bool {
        if finding.keyPath == nil { return line.contains(finding.evidence) || finding.evidence.contains(line) }
        if let value = finding.value, !value.isEmpty, line.contains(value) { return true }
        guard let key = finding.keyPath?.last(where: { Int($0) == nil && $0 != StructuralDiff.setElement }) else { return false }
        return line.contains(key)
    }
}
