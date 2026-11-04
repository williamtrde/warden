import CryptoKit
import Foundation

/// Masks anything that looks like a secret. Runs on every text before it reaches the
/// on-device model and before it is displayed.
///
/// Each secret becomes `[masked:ab12]`, where the suffix is derived from the secret. A swapped
/// API key therefore remains visible in a diff, while the value itself never leaves this type.
public enum SecretRedactor {
    public static func redact(_ text: String) -> String {
        var result = text
        for pattern in wholeMatchPatterns {
            result = replace(pattern, in: result, group: 0)
        }
        for pattern in valueGroupPatterns {
            result = replace(pattern, in: result, group: 1)
        }
        return maskHighEntropyRuns(in: result)
    }

    /// Well-known credential shapes, masked entirely.
    private static let wholeMatchPatterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\z)"#,
        #"\bsk-ant-[A-Za-z0-9_-]{8,}"#,
        #"\bsk-[A-Za-z0-9_-]{16,}"#,
        #"\bgh[pousr]_[A-Za-z0-9]{16,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{16,}"#,
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,
        #"\b(AKIA|ASIA)[A-Z0-9]{16}\b"#,
        #"\bAIza[A-Za-z0-9_-]{30,}"#,
        #"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*"#,
        #"\bnpm_[A-Za-z0-9]{20,}"#
    ].map(compile)

    /// Patterns where capture group 1 is the secret and the rest is useful context.
    private static let valueGroupPatterns: [NSRegularExpression] = [
        // Authorization headers, in any quoting style.
        #"\b(?:bearer|basic|token)\s+([A-Za-z0-9._~+/=-]{8,})"#,
        // Credentials embedded in URLs.
        #"[a-z][a-z0-9+.-]*://[^\s/:@"']+:([^\s/@"']+)@"#,
        // Query parameters.
        #"[?&](?:token|key|secret|password|api[_-]?key|access[_-]?token|auth)=([^\s&"']+)"#,
        // Assignments whose key names a secret: JSON, TOML, YAML, shell.
        #"[\w.-]*(?:token|secret|passw(?:or)?d|passphrase|api[_-]?key|apikey|auth|authorization|credential|private[_-]?key|cookie)[\w.-]*"#
            + #"["']?\s*[:=]\s*["']?([^\s"',}\]]{4,}(?:[ \t]+[^\s"',}\]]+)*)"#
    ].map(compile)

    private static func compile(_ source: String) -> NSRegularExpression {
        // A pattern that does not compile is a programming error caught by the first test run.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: source, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, group: Int) -> String {
        var result = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range(at: group), in: result) else { continue }
            let secret = String(result[range])
            guard !secret.hasPrefix(markerPrefix), !isBenignValue(secret) else { continue }
            result.replaceSubrange(range, with: marker(for: secret))
        }
        return result
    }

    /// Values that sit behind a secret-sounding key but reveal nothing.
    private static func isBenignValue(_ value: String) -> Bool {
        ["true", "false", "null", "none", "required", "optional", "oauth", "bearer", "basic"].contains(value.lowercased())
    }

    private static let markerPrefix = "[masked:"

    private static func marker(for secret: String) -> String {
        let digest = SHA256.hash(data: Data(secret.utf8))
        let suffix = digest.prefix(2).map { String(format: "%02x", $0) }.joined()
        return "\(markerPrefix)\(suffix)]"
    }

    // MARK: - Unknown formats

    private static let longRun = compile(#"[A-Za-z0-9+/_=-]{32,}"#)

    /// Catches tokens of unknown shape: long, mixed and random-looking.
    private static func maskHighEntropyRuns(in text: String) -> String {
        var result = text
        for match in longRun.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = String(result[range])
            if looksRandom(run) { result.replaceSubrange(range, with: marker(for: run)) }
        }
        return result
    }

    private static func looksRandom(_ run: String) -> Bool {
        // Paths and kebab-case names are long but not random.
        let separators = run.filter { "/-_".contains($0) }.count
        guard separators * 8 < run.count else { return false }
        let hasDigit = run.contains(where: \.isNumber)
        let hasLetter = run.contains(where: \.isLetter)
        return hasDigit && hasLetter && InstructionRules.shannonEntropy(run) >= 3.5
    }
}
