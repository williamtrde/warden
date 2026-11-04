import Foundation

/// Rules for natural-language instruction files (`CLAUDE.md`, `AGENTS.md`).
///
/// A plain command or URL is normal in these files: it stays informational and is merely
/// highlighted. Only patterns that are dangerous in themselves are critical.
public enum InstructionRules {
    /// A line this long is not prose, and patterns must not run on attacker-sized input.
    static let maxLineLength = 4_000

    /// Scans the lines a change added. `newText` provides the context needed to know
    /// whether a line sits inside a fenced code block or an HTML comment.
    public static func scan(newText: String, addedLineNumbers: Set<Int>) -> [RiskFinding] {
        let lines = LineDiff.splitLines(newText)
        let insideFence = fenceMask(lines)
        var findings: [RiskFinding] = []

        for (index, rawLine) in lines.enumerated() where addedLineNumbers.contains(index + 1) {
            if rawLine.utf8.count > maxLineLength {
                findings.append(.init(rule: .encodedPayload, evidence: String(rawLine.prefix(200))))
            } else {
                findings += scanLine(rawLine, isFirstLine: index == 0, insideFence: insideFence[index])
            }
        }
        findings += blockFindings(lines, added: addedLineNumbers)
        findings += commentFindings(lines, added: addedLineNumbers, insideFence: insideFence)
        return findings
    }

    private static func scanLine(_ raw: String, isFirstLine: Bool, insideFence: Bool) -> [RiskFinding] {
        let line = InstructionPatterns.normalize(raw)
        var findings = criticalFindings(in: line, evidence: raw)
        func add(_ rule: RuleID) { findings.append(.init(rule: rule, evidence: raw)) }

        if containsHiddenCharacters(raw, isFirstLine: isFirstLine) { add(.hiddenText) }
        if !insideFence, InstructionPatterns.linkComment.firstMatch(in: line) != nil
            || InstructionPatterns.hiddenElement.firstMatch(in: line) != nil {
            add(.hiddenText)
        }
        if containsEncodedPayload(line) { add(.encodedPayload) }

        let isCommand = insideFence || line.hasPrefix("$ ") || InstructionPatterns.inlineCommand.firstMatch(in: line) != nil
        if isCommand, InstructionPatterns.knownCommand.firstMatch(in: line) != nil { add(.shellCommandMentioned) }
        if InstructionPatterns.url.firstMatch(in: line) != nil { add(.urlMentioned) }
        return findings
    }

    /// The rules that also apply across several lines.
    private static func criticalFindings(in text: String, evidence: String) -> [RiskFinding] {
        var findings: [RiskFinding] = []
        if containsBypass(text) { findings.append(.init(rule: .bypassInstruction, evidence: evidence)) }
        if InstructionPatterns.remoteExecution.contains(where: { $0.firstMatch(in: text) != nil }) {
            findings.append(.init(rule: .remoteCodeExecution, evidence: evidence))
        }
        if containsSecretAccess(text) { findings.append(.init(rule: .secretAccess, evidence: evidence)) }
        return findings
    }

    // MARK: - Multi-line

    /// Wrapping a sentence, a shell continuation, or a base64 block must not hide it.
    private static func blockFindings(_ lines: [String], added: Set<Int>) -> [RiskFinding] {
        var findings: [RiskFinding] = []
        var block: [String] = []

        func flush() {
            defer { block = [] }
            guard block.count > 1 else { return }
            let evidence = block.joined(separator: "\n")
            guard evidence.utf8.count <= maxLineLength else { return }
            let joined = block.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasSuffix("\\") ? String(trimmed.dropLast()) : trimmed
            }.joined(separator: " ")
            findings += criticalFindings(in: InstructionPatterns.normalize(joined), evidence: evidence)
            let compact = block.map { $0.trimmingCharacters(in: .whitespaces) }
            // The last line of a wrapped block is usually shorter than the others.
            if compact.dropLast().allSatisfy({ InstructionPatterns.encodedLine.firstMatch(in: $0) != nil }),
               containsEncodedPayload(compact.joined()) {
                findings.append(.init(rule: .encodedPayload, evidence: evidence))
            }
        }

        for (index, line) in lines.enumerated() {
            if added.contains(index + 1), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                block.append(line)
            } else {
                flush()
            }
        }
        flush()
        return findings
    }

    /// Marks the lines inside a fenced code block. A fence opens with three or more backticks
    /// or tildes, and a backtick fence has no backtick in its info string: "```x```" is inline code.
    static func fenceMask(_ lines: [String]) -> [Bool] {
        var mask = Array(repeating: false, count: lines.count)
        var open: Character?
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let marker = trimmed.first
            let isFenceLine = (marker == "`" || marker == "~") && trimmed.prefix(3) == String(repeating: marker ?? " ", count: 3)
            if let current = open {
                mask[index] = true
                if isFenceLine, marker == current, trimmed.allSatisfy({ $0 == current }) { open = nil }
            } else if isFenceLine {
                let info = trimmed.drop { $0 == marker }
                if marker == "~" || !info.contains("`") {
                    open = marker
                    mask[index] = true
                }
            }
        }
        return mask
    }

    // MARK: - Hidden text

    /// Characters that render as nothing. Legitimate uses are exempted: emoji sequences,
    /// joiners inside non-Latin words, soft hyphens and a leading byte order mark.
    static func containsHiddenCharacters(_ line: String, isFirstLine: Bool) -> Bool {
        let scalars = Array(line.unicodeScalars)
        var insideTagSequence = false
        for (index, scalar) in scalars.enumerated() {
            let value = scalar.value
            if value == 0x1F3F4 { insideTagSequence = true }
            if (0xE0000...0xE007F).contains(value), insideTagSequence {
                if value == 0xE007F { insideTagSequence = false }
                continue
            }
            if value == 0xFEFF, isFirstLine, index == 0 { continue }
            if value == 0x00AD || value == 0x09 { continue }
            if value == 0x200C || value == 0x200D, isContextualJoiner(scalars, at: index) { continue }
            if value == 0xFE0E || value == 0xFE0F, index > 0, scalars[index - 1].properties.isEmoji { continue }
            if isInvisible(scalar) { return true }
        }
        return false
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        let category = scalar.properties.generalCategory
        if category == .format || category == .control { return true }
        let value = scalar.value
        return (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value)
            || [0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x180E, 0x2800, 0x3164, 0xFFA0].contains(value)
    }

    private static func isContextualJoiner(_ scalars: [Unicode.Scalar], at index: Int) -> Bool {
        guard index > 0, index + 1 < scalars.count else { return false }
        func isEmojiSide(_ scalar: Unicode.Scalar) -> Bool {
            (scalar.properties.isEmoji && scalar.value > 0xFF) || scalar.value == 0xFE0F || scalar.properties.isEmojiModifier
        }
        func isNonLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
            scalar.properties.isAlphabetic && scalar.value > 0x2FF
        }
        let previous = scalars[index - 1]
        let next = scalars[index + 1]
        return (isEmojiSide(previous) && isEmojiSide(next)) || (isNonLatinLetter(previous) && isNonLatinLetter(next))
    }

    /// HTML comments never render, which makes them a hiding place. Exact tooling directives
    /// and fenced examples do not count. An unterminated comment hides the rest of the file.
    private static func commentFindings(_ lines: [String], added: Set<Int>, insideFence: [Bool]) -> [RiskFinding] {
        var findings: [RiskFinding] = []
        var body: String?
        var touchesAddedLine = false

        func finish() {
            defer { body = nil }
            guard let text = body, touchesAddedLine else { return }
            let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let isDirective = content.isEmpty || InstructionPatterns.commentDirective.firstMatch(in: content.lowercased()) != nil
            if !isDirective { findings.append(.init(rule: .hiddenText, evidence: String(text.prefix(300)))) }
        }

        for (index, line) in lines.enumerated() {
            if body == nil, insideFence[index] { continue }
            var rest = line[...]
            while true {
                if body != nil {
                    if added.contains(index + 1) { touchesAddedLine = true }
                    guard let end = rest.range(of: "-->") else {
                        body?.append(contentsOf: rest + "\n")
                        break
                    }
                    body?.append(contentsOf: rest[..<end.lowerBound])
                    finish()
                    rest = rest[end.upperBound...]
                } else {
                    guard let start = rest.range(of: "<!--") else { break }
                    body = ""
                    touchesAddedLine = false
                    rest = rest[start.upperBound...]
                }
            }
        }
        finish()
        return findings
    }

    // MARK: - Bypass instructions

    private static func containsBypass(_ line: String) -> Bool {
        if InstructionPatterns.bypass.contains(where: { $0.firstMatch(in: line) != nil }) { return true }
        return InstructionPatterns.bypassUnlessNegated.contains { pattern in
            pattern.matchRanges(in: line).contains { !isNegated($0, in: line) }
        }
    }

    /// "Never deploy without asking for approval" forbids what the bare pattern would flag. The
    /// negation must sit within four words of the match, in the same clause: anything looser
    /// turns ordinary phrasing into a free pass.
    static func isNegated(_ range: Range<String.Index>, in line: String) -> Bool {
        let before = line[..<range.lowerBound]
        let clauseStart = before.lastIndex { ".!?;:,".contains($0) }.map { before.index(after: $0) } ?? before.startIndex
        let words = before[clauseStart...].split(whereSeparator: \.isWhitespace).suffix(4).joined(separator: " ")
        guard InstructionPatterns.falseNegation.firstMatch(in: words) == nil else { return false }
        return InstructionPatterns.negation.firstMatch(in: words) != nil
    }

    // MARK: - Secrets

    private static func containsSecretAccess(_ line: String) -> Bool {
        let readsSecretFile = InstructionPatterns.secretFileAccess.contains { pattern in
            pattern.matchRanges(in: line).contains { !isNegated($0, in: line) }
        }
        if readsSecretFile { return true }
        if InstructionPatterns.legitimateAuth.firstMatch(in: line) == nil,
           InstructionPatterns.secretSending.matchRanges(in: line).contains(where: { !isNegated($0, in: line) }) {
            return true
        }
        return InstructionPatterns.externalSending.contains { pattern in
            pattern.matchRanges(in: line).contains { !isNegated($0, in: line) && reachesExternalHost(String(line[$0])) }
        }
    }

    /// True when any host in the text is not this machine. Hosts are parsed, not prefix-matched:
    /// `https://127.0.0.1.nip.io` and `https://localhost@evil.example` are external.
    static func reachesExternalHost(_ text: String) -> Bool {
        InstructionPatterns.host.matches(in: text).contains { candidate in
            let withScheme = candidate.contains("://") ? candidate : "https://\(candidate)"
            guard let host = URLComponents(string: withScheme)?.host?.lowercased() else { return true }
            return !InstructionPatterns.localHosts.contains(host)
        }
    }

    // MARK: - Encoded payloads

    /// Long blobs an agent can decode but a person cannot read. Hashes and paths are fine.
    static func containsEncodedPayload(_ line: String) -> Bool {
        InstructionPatterns.encodedRun.matches(in: line).contains { run in
            if run.allSatisfy(\.isHexDigit) { return run.count >= 129 }
            let slashes = run.filter { $0 == "/" }.count
            if slashes * 20 > run.count { return false } // A file path, not base64.
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
