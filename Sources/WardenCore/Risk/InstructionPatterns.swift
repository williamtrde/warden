import Foundation

// Regular expressions read better unbroken.
// swiftlint:disable line_length

/// A precompiled, case-insensitive regular expression with a String-friendly API.
struct Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ source: String) {
        // A pattern that does not compile is a programming error caught by the first test run.
        // swiftlint:disable:next force_try
        regex = try! NSRegularExpression(pattern: source, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    func firstMatch(in text: String) -> String? {
        matches(in: text).first
    }

    func matches(in text: String) -> [String] {
        matchRanges(in: text).map { String(text[$0]) }
    }

    func matchRanges(in text: String) -> [Range<String.Index>] {
        regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }
    }
}

/// The patterns behind `InstructionRules`, in English and French.
enum InstructionPatterns {
    /// Straight apostrophes make the French patterns simpler.
    static func normalize(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{2019}", with: "'")
    }

    static let bypass: [Pattern] = [
        // English: discarding earlier instructions.
        Pattern(#"\b(ignore|disregard|forget|override)\b[^.\n]{0,30}\b(previous|prior|above|earlier|system|your|all other)\b[^.\n]{0,20}\b(instructions?|prompts?|guidelines?|directives?)\b"#),
        Pattern(#"\b(ignore|disregard|forget)\s+(all|any|every)\s+(instructions?|prompts?)\b"#),
        // English: removing human confirmation.
        Pattern(#"\b(do not|don't|dont|never)(\s+\w+){0,2}\s+(ask|prompt|request|seek|wait)\b[^.\n]{0,25}\b(confirmation|confirm|permission|approval|consent)\b"#),
        // English: hiding actions.
        Pattern(#"\b(do not|don't|dont|never)\b[^.\n]{0,20}\b(tell|inform|mention|notify|alert|reveal|disclose)\b[^.\n]{0,25}\b(user|human|owner|developer|anyone)\b"#),
        Pattern(#"\b(hide|conceal)\b[^.\n]{0,40}\bfrom\b[^.\n]{0,15}\b(user|human|owner|developer)\b"#),
        // French.
        Pattern(#"\b(ignore|oublie|ne tiens pas compte)\b[^.\n]{0,30}\b(instructions?|consignes?|règles?)\b[^.\n]{0,20}(précédentes?|antérieures?|ci-dessus|système)"#),
        Pattern(#"\bne\s+(me\s+|lui\s+|leur\s+)?demande\s+(pas|jamais|aucune?)\b[^.\n]{0,20}\b(confirmation|permission|autorisation|validation|accord)\b"#),
        Pattern(#"\b(cache|dissimule|masque)\b[^.\n]{0,40}\bà l'utilisateur\b"#),
        Pattern(#"\bne\s+(dis|mentionne|signale|préviens|informe)\b[^.\n]{0,15}\b(pas|jamais|rien)\b[^.\n]{0,25}(utilisateur|personne)"#)
    ]

    /// Same intent, but the sentence may well forbid it: "never auto-approve".
    static let bypassUnlessNegated: [Pattern] = [
        Pattern(#"\bwithout\s+(asking|requesting|seeking|waiting for)\b[^.\n]{0,25}\b(confirmation|permission|approval|consent|the user)\b"#),
        Pattern(#"\bwithout\s+(telling|informing|notifying|alerting)\b[^.\n]{0,15}\b(user|human|owner|developer|anyone)\b"#),
        Pattern(#"\b(auto[- ]?approve|automatically\s+(approve|accept|confirm)|always\s+(approve|accept|say yes|answer yes))\b"#),
        Pattern(#"\bsans\s+demander\b[^.\n]{0,25}\b(confirmation|permission|autorisation|validation|accord)\b"#),
        Pattern(#"\bsans\s+(prévenir|informer|avertir)\b[^.\n]{0,15}(l'utilisateur|personne)"#),
        Pattern(#"\b(approuve|accepte|valide|confirme)r?\b[^.\n]{0,15}\bautomatiquement\b"#)
    ]

    static let negation = Pattern(#"\b(never|do not|don't|dont|must not|mustn't|should not|shouldn't|cannot|can't|avoid|jamais|ne)\b|\bn'"#)
    /// "Do not hesitate to read .env" is an encouragement, not a prohibition.
    static let falseNegation = Pattern(#"h[eé]sit"#)

    static let remoteExecution: [Pattern] = [
        Pattern(#"\b(curl|wget|fetch)\b[^\n|;]*\|\s*(sudo\s+)?(env\s+)?((ba|z|da|k|fi)?sh|python[0-9.]*|perl|ruby|node|php)\b"#),
        Pattern(#"\b((ba|z)?sh)\b[^\n|;]{0,10}(<\(|\$\()\s*(curl|wget)\b"#),
        Pattern(#"\beval\b[^\n]{0,5}\$\(\s*(curl|wget)\b"#),
        Pattern(#"\b(curl|wget)\b[^\n]*&&[^\n]*\b(chmod\s+\+x|(ba|z)?sh\s|\./)"#)
    ]

    private static let secretFiles = #"(\.env\b|~/\.ssh|\.ssh/|id_rsa|id_ed25519|~/\.aws|\.aws/credentials|~/\.netrc|keychain|trousseau|find-generic-password)"#
    private static let genericSecrets = #"(api[ _-]?keys?|clés? d'?api|tokens?|credentials?|passwords?|mots? de passe|secrets?|identifiants?)"#
    private static let readVerbs = #"(read|cat|print|dump|copy|collect|grep|open|load|lis|lire|copie|copier|récupère|récupérer|affiche|afficher)"#
    private static let sendVerbs = #"(send|post|upload|forward|transmit|exfiltrate|leak|envoie|envoyer|transmets|transmettre|publie|publier)"#

    static let secretFileAccess = Pattern("\\b\(readVerbs)\\b[^.\\n]{0,50}\(secretFiles)")
    static let secretSending = Pattern("\\b\(sendVerbs)\\b[^.\\n]{0,50}(\(secretFiles)|\\b\(genericSecrets)\\b)")

    static let externalSending: [Pattern] = [
        Pattern(#"\b(curl|wget)\b[^\n]*(\s-d\b|\s--data\S*|\s-F\b|\s--form\b|\s-T\b|\s--upload-file\b|\s--post-\w+\b|\s-X\s*(POST|PUT))[^\n]*https?://\S+"#),
        Pattern(#"\b(curl|wget)\b[^\n]*https?://\S+[^\n]*(\s-d\b|\s--data\S*|\s-F\b|\s--form\b|\s-T\b|\s--upload-file\b|\s-X\s*(POST|PUT))"#),
        Pattern("\\b\(sendVerbs)\\b[^.\\n]{0,60}https?://\\S+")
    ]

    static let localURL = Pattern(#"https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\])"#)

    static let htmlComment = Pattern(#"<!--.*?-->"#)
    static let commentDirectives = [
        "prettier-ignore", "markdownlint", "toc", "omit in toc", "vale ", "cspell", "eslint", "end", "begin", "start"
    ]

    /// Runs of base64, URL-safe base64 or hexadecimal text.
    static let encodedRun = Pattern(#"[A-Za-z0-9+/_=-]{80,}"#)

    static let inlineCommand = Pattern(#"`[^`]+`"#)
    static let knownCommand = Pattern(#"(^|[`\s$])(sudo|rm|curl|wget|chmod|chown|ssh|scp|npm|npx|pnpm|yarn|pip3?|brew|git|bash|sh|zsh|python3?|node|docker|kubectl|make|osascript)\s+\S"#)
    static let url = Pattern(#"https?://[^\s)>\]]+"#)
}
// swiftlint:enable line_length
