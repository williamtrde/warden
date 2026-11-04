import Foundation

/// Rules for natural-language instruction files (`CLAUDE.md`, `AGENTS.md`).
///
/// A plain command or URL is normal in these files: it stays informational and is merely
/// highlighted. Only patterns that are dangerous in themselves are critical.
public enum InstructionRules {
    /// Scans the lines a change added. `newText` provides the context needed to know
    /// whether a line sits inside a fenced code block.
    public static func scan(newText: String, addedLineNumbers: Set<Int>) -> [RiskFinding] {
        let lines = LineDiff.splitLines(newText)
        var findings: [RiskFinding] = []
        var insideFence = false
        var addedBlock: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let isFenceMarker = rawLine.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            defer { if isFenceMarker { insideFence.toggle() } }
            guard addedLineNumbers.contains(index + 1) else { continue }

            let line = InstructionPatterns.normalize(rawLine)
            addedBlock.append(insideFence ? "" : line)
            findings += scanLine(line, raw: rawLine, isFirstLine: index == 0, insideFence: insideFence && !isFenceMarker)
        }
        findings += htmlCommentFindings(in: addedBlock.joined(separator: "\n"))
        return findings
    }

    private static func scanLine(_ line: String, raw: String, isFirstLine: Bool, insideFence: Bool) -> [RiskFinding] {
        var findings: [RiskFinding] = []
        func add(_ rule: RuleID) { findings.append(.init(rule: rule, evidence: raw)) }

        if containsHiddenCharacters(raw, isFirstLine: isFirstLine) { add(.hiddenText) }
        if containsBypass(line) { add(.bypassInstruction) }
        if InstructionPatterns.remoteExecution.contains(where: { $0.firstMatch(in: line) != nil }) { add(.remoteCodeExecution) }
        if containsSecretAccess(line) { add(.secretAccess) }
        if containsEncodedPayload(line) { add(.encodedPayload) }

        let isCommand = insideFence || line.hasPrefix("$ ") || InstructionPatterns.inlineCommand.firstMatch(in: line) != nil
        if isCommand, InstructionPatterns.knownCommand.firstMatch(in: line) != nil { add(.shellCommandMentioned) }
        if InstructionPatterns.url.firstMatch(in: line) != nil { add(.urlMentioned) }
        return findings
    }

    // MARK: - Hidden text

    /// Format and tag characters that render as nothing. Joiners inside emoji sequences
    /// and a leading byte order mark are legitimate.
    static func containsHiddenCharacters(_ line: String, isFirstLine: Bool) -> Bool {
        let scalars = Array(line.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let value = scalar.value
            if value == 0xFEFF, isFirstLine, index == 0 { continue }
            if value == 0x200D, isEmojiJoiner(scalars, at: index) { continue }
            let isHidden = (0x200B...0x200F).contains(value) || (0x202A...0x202E).contains(value)
                || (0x2060...0x2064).contains(value) || (0x2066...0x2069).contains(value)
                || value == 0xFEFF || value == 0x00AD || (0xE0000...0xE007F).contains(value)
            if isHidden { return true }
        }
        return false
    }

    private static func isEmojiJoiner(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index > 0, index + 1 < scalars.count else { return false }
        func isEmojiSide(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.isEmoji && scalar.value > 0xFF || scalar.value == 0xFE0F
                || scalar.properties.isEmojiModifier
        }
        return isEmojiSide(scalars[index - 1]) && isEmojiSide(scalars[index + 1])
    }

    /// HTML comments never render, which makes them a hiding place. Tooling directives
    /// (`<!-- prettier-ignore -->`) and fenced examples do not count.
    private static func htmlCommentFindings(in text: String) -> [RiskFinding] {
        InstructionPatterns.htmlComment.matches(in: text).compactMap { comment in
            let body = comment.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isDirective = body.isEmpty || InstructionPatterns.commentDirectives.contains { body.hasPrefix($0) }
            return isDirective ? nil : RiskFinding(rule: .hiddenText, evidence: comment)
        }
    }

    // MARK: - Bypass instructions

    private static func containsBypass(_ line: String) -> Bool {
        if InstructionPatterns.bypass.contains(where: { $0.firstMatch(in: line) != nil }) { return true }
        return InstructionPatterns.bypassUnlessNegated.contains { pattern in
            pattern.matchRanges(in: line).contains { !isNegated($0, in: line) }
        }
    }

    /// "Never deploy without asking for approval" forbids what the bare pattern would flag.
    static func isNegated(_ range: Range<String.Index>, in line: String) -> Bool {
        let before = line[..<range.lowerBound]
        let sentence = before.split(whereSeparator: { ".!?;".contains($0) }).last.map(String.init) ?? ""
        guard InstructionPatterns.falseNegation.firstMatch(in: sentence) == nil else { return false }
        return InstructionPatterns.negation.firstMatch(in: sentence) != nil
    }

    // MARK: - Secrets

    private static func containsSecretAccess(_ line: String) -> Bool {
        if InstructionPatterns.secretFileAccess.matchRanges(in: line).contains(where: { !isNegated($0, in: line) }) { return true }
        if InstructionPatterns.secretSending.matchRanges(in: line).contains(where: { !isNegated($0, in: line) }) { return true }
        for pattern in InstructionPatterns.externalSending {
            for range in pattern.matchRanges(in: line) where !isNegated(range, in: line) {
                if InstructionPatterns.localURL.firstMatch(in: String(line[range])) == nil { return true }
            }
        }
        return false
    }

    // MARK: - Encoded payloads

    /// Long blobs an agent can decode but a person cannot read. Short hashes are fine.
    static func containsEncodedPayload(_ line: String) -> Bool {
        InstructionPatterns.encodedRun.matches(in: line).contains { run in
            if run.allSatisfy(\.isHexDigit) { return run.count >= 128 }
            let hasDigit = run.contains(where: \.isNumber)
            let hasUpper = run.contains(where: \.isUppercase)
            let hasLower = run.contains(where: \.isLowercase)
            return hasDigit && hasUpper && hasLower && shannonEntropy(run) >= 4.0
        }
    }

    static func shannonEntropy(_ text: String) -> Double {
        var counts: [Character: Int] = [:]
        for character in text { counts[character, default: 0] += 1 }
        let total = Double(text.count)
        return counts.values.reduce(0) { entropy, count in
            let probability = Double(count) / total
            return entropy - probability * log2(probability)
        }
    }
}
