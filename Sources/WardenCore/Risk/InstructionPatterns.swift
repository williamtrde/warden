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
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
            .flatMap { Range($0.range, in: text) }
            .map { String(text[$0]) }
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
        Pattern(#"\b(do not|don't|dont|never)\s+ask\s+(me\s+|the user\s+)?(before|first|again)\b"#),
        Pattern(#"\bskip\b[^.\n]{0,20}\b(permission|approval|confirmation)s?\b"#),
        Pattern(#"--dangerously-skip-permissions\b"#),
        // English: hiding actions.
        Pattern(#"\b(do not|don't|dont|never)\b[^.\n]{0,15}\b(tell|inform|notify|alert)\b[^.\n]{0,25}\b(the user|the human|the owner|the developer|anyone)\b"#),
        Pattern(#"\b(do not|don't|dont|never)\s+(mention|reveal|disclose)\s+(this|it|that)\b"#),
        Pattern(#"\b(hide|conceal)\s+(this|these|that|it|the|your)?\s*(action|actions|step|steps|change|changes|command|commands|activity|it)?\b[^.\n]{0,15}\bfrom\b[^.\n]{0,15}\b(user|human|owner|developer)\b"#),
        // French.
        Pattern(#"\b(ignore|oublie|ne tiens pas compte)\b[^.\n]{0,30}\b(instructions?|consignes?|règles?)\b[^.\n]{0,20}(pr[ée]c[ée]dentes?|ant[ée]rieures?|ci-dessus|syst[èe]me)"#),
        Pattern(#"\bne\s+(me\s+|lui\s+|leur\s+)?demande\s+(pas|jamais|aucune?)\b[^.\n]{0,20}\b(confirmation|permission|autorisation|validation|accord)\b"#),
        Pattern(#"\b(cache|dissimule|masque)\s+(cette action|cette étape|cette commande|ce changement|ceci|cela)\b[^.\n]{0,15}à l'utilisateur\b"#),
        Pattern(#"\bne\s+(dis|mentionne|signale|préviens|informe)\b[^.\n]{0,15}\b(pas|jamais|rien)\b[^.\n]{0,25}(l'utilisateur|personne)"#)
    ]

    /// Same intent, but the sentence may well forbid it: "never auto-approve".
    static let bypassUnlessNegated: [Pattern] = [
        Pattern(#"\bwithout\s+(asking|requesting|seeking|waiting for)\b[^.\n]{0,25}\b(confirmation|permission|approval|consent|the user)\b"#),
        Pattern(#"\bwithout\s+(telling|informing|notifying|alerting)\b[^.\n]{0,15}\b(user|human|owner|developer|anyone)\b"#),
        Pattern(#"\b(auto[- ]?approve|automatically\s+(approve|accept|confirm)|always\s+(approve|accept|say yes|answer yes))\s+(all|every|any|each|tool|tools|command|commands|change|changes|prompt|prompts|permission|permissions|request|requests|action|actions)\b"#),
        Pattern(#"\bsans\s+demander\b[^.\n]{0,25}\b(confirmation|permission|autorisation|validation|accord)\b"#),
        Pattern(#"\bsans\s+(prévenir|informer|avertir)\b[^.\n]{0,15}(l'utilisateur|personne)"#),
        Pattern(#"\b(approuve|accepte|valide|confirme)r?\b[^.\n]{0,15}\bautomatiquement\b"#)
    ]

    /// A negation only counts when it sits right before the matched action, in the same clause.
    static let negation = Pattern(#"\b(never|do not|don't|dont|must not|mustn't|should not|shouldn't|cannot|can't|avoid|jamais|ne)\b|\bn'"#)
    /// "Do not forget to read .env" is an order, not a prohibition.
    static let falseNegation = Pattern(#"h[eé]sit|forget|fail|skip|stop|delay|oubli|manque"#)

    static let remoteExecution: [Pattern] = [
        Pattern(#"\b(curl|wget|fetch)\b[^\n]{0,300}\|&?\s*(sudo(\s+-\S+)*\s+)?(env\s+)?(\S{0,60}/)?((ba|z|da|k|fi)?sh|python[0-9.]*|perl|ruby|node|php)\b"#),
        Pattern(#"\b((ba|z)?sh|python[0-9.]*|source)\b[^\n|;]{0,10}(<\(|\$\()\s*(curl|wget)\b"#),
        Pattern(#"\beval\b[^\n]{0,5}\$\(\s*(curl|wget)\b"#),
        Pattern(#"\b(curl|wget)\b[^\n]{0,300}(&&|;)\s*(chmod\s+\+x|(ba|z)?sh\s|python[0-9.]*\s|\./)"#)
    ]

    private static let credentialFiles = #"(~/\.ssh|\.ssh/|id_rsa|id_ed25519|~/\.aws|\.aws/credentials|~/\.netrc|\.credentials\.json|~/\.npmrc|\.config/gh/hosts\.yml)"#
    private static let dotEnv = #"(?<![\w.])\.env\b(?!\.(example|sample|template))"#
    private static let genericSecrets = #"(api[ _-]?keys?|clés? d'?api|tokens?|credentials?|passwords?|mots? de passe|secrets?|identifiants?)"#
    private static let readVerbs = #"(read|cat|print|dump|grep|lis|lire|affiche|afficher|récupère|récupérer)"#
    private static let copyVerbs = #"(copy|cp|tar|zip|scp|rsync|base64|collect|open|load|copie|copier)"#
    private static let sendVerbs = #"(send|upload|forward|transmit|exfiltrate|leak|envoie|envoyer|transmets|transmettre|publie|publier)"#

    static let secretFileAccess: [Pattern] = [
        Pattern("\\b(\(readVerbs)|\(copyVerbs))\\b[^\\n]{0,50}\(credentialFiles)"),
        Pattern("\\b\(readVerbs)\\b[^\\n]{0,50}\(dotEnv)"),
        Pattern(#"\b(dump|export|print|affiche)\b[^\n]{0,30}\b(keychain|trousseau)\b"#),
        Pattern(#"\bfind-generic-password\b"#),
        Pattern(#"\becho\s+\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD)\b"#)
    ]
    static let secretSending = Pattern("\\b\(sendVerbs)\\b[^.\\n]{0,50}(\(credentialFiles)|\(dotEnv)|\\b\(genericSecrets)\\b)")
    /// Sending a credential to the place it belongs is ordinary API usage.
    static let legitimateAuth = Pattern(#"\b(authorization|auth)\s+header\b|\bbearer\b|\ben-tête\b"#)

    static let dataFlags = #"(\s-d|\s--data\S*|\s-F|\s--form\b|\s-T|\s--upload-file\b|\s--post-\w+\b|\s-X\s*(POST|PUT)\b)"#
    /// Commands that push data somewhere. The destination is checked by `externalHosts`.
    static let externalSending: [Pattern] = [
        Pattern("\\b(curl|wget)\\b[^\\n]{0,300}\(dataFlags)[^\\n]{0,300}"),
        Pattern("\\b\(sendVerbs)\\b[^.\\n]{0,60}https?://\\S+")
    ]

    /// Anything shaped like a host, with or without a scheme.
    static let host = Pattern(#"(?<![\w@./-])(https?://)?([a-z0-9-]+\.)+[a-z]{2,}\b|https?://\S+"#)
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]

    /// Comments that are instructions to a tool, matched in full so that they cannot carry text.
    static let commentDirective = Pattern(
        #"^(prettier-ignore(-start|-end)?|markdownlint-(disable|enable|capture|restore)(-next-line|-file)?( [\w, -]{0,80})?|cspell:\S{0,80}|toc|omit in toc|eslint-(disable|enable)( [\w, /-]{0,80})?)$"#
    )
    static let linkComment = Pattern(#"^\s{0,3}\[[^\]]{0,40}\]:\s*(#|<>)\s*[("']"#)
    static let hiddenElement = Pattern(#"<\w{1,20}[^>]{0,200}(\shidden\b|display\s*:\s*none|visibility\s*:\s*hidden)"#)

    /// Runs of base64, URL-safe base64 or hexadecimal text.
    static let encodedRun = Pattern(#"[A-Za-z0-9+/_=-]{80,}"#)
    static let encodedLine = Pattern(#"^[A-Za-z0-9+/_=-]{40,}$"#)

    static let inlineCommand = Pattern(#"`[^`]+`"#)
    static let knownCommand = Pattern(#"(^|[`\s$])(sudo|rm|curl|wget|chmod|chown|ssh|scp|npm|npx|pnpm|yarn|pip3?|brew|git|bash|sh|zsh|python3?|node|docker|kubectl|make|osascript)\s+\S"#)
    static let url = Pattern(#"https?://[^\s)>\]]+"#)
}
// swiftlint:enable line_length
