import Foundation

/// Language of generated text.
public enum ExplanationLanguage: String, Codable, Sendable, CaseIterable {
    case english = "en"
    case french = "fr"

    /// Follows the system's preferred language, English otherwise.
    public static func current(preferred: [String] = Locale.preferredLanguages) -> ExplanationLanguage {
        preferred.first?.lowercased().hasPrefix("fr") == true ? .french : .english
    }

    /// The name used when instructing the model.
    var modelName: String { self == .french ? "French" : "English" }
}

/// Where an explanation came from. Shown discreetly in the interface.
public enum ExplanationSource: String, Codable, Sendable {
    case onDeviceAI
    case builtInRules

    public var label: String {
        switch self {
        case .onDeviceAI: return "On-device AI"
        case .builtInRules: return "Built-in rules"
        }
    }
}

/// What Warden advises. Always decided by rules, never by the model.
public enum RecommendedAction: String, Codable, Sendable {
    case accept
    case revert
}

/// A plain-language explanation of one change.
public struct Explanation: Equatable, Codable, Sendable {
    public let whatChanged: String
    public let impact: String
    public let recommendation: String
    public let recommendedAction: RecommendedAction
    public let source: ExplanationSource
    public let language: ExplanationLanguage

    public init(
        whatChanged: String,
        impact: String,
        recommendation: String,
        recommendedAction: RecommendedAction,
        source: ExplanationSource,
        language: ExplanationLanguage
    ) {
        self.whatChanged = whatChanged
        self.impact = impact
        self.recommendation = recommendation
        self.recommendedAction = recommendedAction
        self.source = source
        self.language = language
    }

    public var fullText: String {
        [whatChanged, impact, recommendation].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The first sentence, for notifications.
    public var firstSentence: String {
        Self.sentences(in: whatChanged).first ?? whatChanged
    }

    /// Sentences end at `.`, `!` or `?` followed by a space, which leaves `settings.json` intact.
    static func sentences(in text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let isEnd = ".!?".contains(character) && (index + 1 == characters.count || characters[index + 1] == " ")
            if isEnd {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }
}

/// Everything needed to explain a change. All text fields are already masked.
public struct ExplanationRequest: Equatable, Sendable {
    public let fileName: String
    public let agent: Agent
    public let severity: Severity
    public let rules: [RuleID]
    /// Masked key paths or snippets, one per finding, aligned with nothing in particular.
    public let details: [RuleID: String]
    public let changeCount: Int
    public let maskedDiff: String
    public let scope: AffectedScope
    public let language: ExplanationLanguage
    public let date: Date

    public init(
        fileName: String,
        agent: Agent,
        severity: Severity,
        rules: [RuleID],
        details: [RuleID: String],
        changeCount: Int,
        maskedDiff: String,
        scope: AffectedScope,
        language: ExplanationLanguage,
        date: Date
    ) {
        self.fileName = fileName
        self.agent = agent
        self.severity = severity
        self.rules = rules
        self.details = details
        self.changeCount = changeCount
        self.maskedDiff = maskedDiff
        self.scope = scope
        self.language = language
        self.date = date
    }
}

/// The common interface of the on-device model and the built-in rules.
public protocol ExplanationGenerator: Sendable {
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}
