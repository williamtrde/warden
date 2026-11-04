import Foundation
import NaturalLanguage

/// Reasons a model draft is thrown away for the built-in explanation.
public enum DraftRejection: Error, Equatable {
    case empty
    case tooLong
    case tooManySentences
    case reassurance(String)
    case verdict(String)
    case unknownURL(String)
    case wrongLanguage
}

/// Treats model output as untrusted. A prompt injection in the diff that gets past the
/// instructions still has to get past these checks, and severity never depends on them.
enum ExplanationValidator {
    private static let maxFieldLength = 320
    private static let maxSentencesPerField = 2

    private static let reassurances = Pattern(
        #"\b(safe|harmless|benign|no risk|nothing to worry|not a concern|routine|"#
            + #"sans danger|sans risque|inoffensi\w+|anodin\w*|aucun risque|rien d'inquiétant|sûr|sûre|pas de risque)\b"#
    )
    private static let verdicts = Pattern(
        #"\b(you should|you can|recommend\w*|accept|approve|ignore|dismiss|keep this|"#
            + #"tu peux|tu devrais|recommand\w*|accepte\w*|approuve\w*|ignore\w*|garde\w*)\b"#
    )

    static func validate(_ draft: ModelDraft, for request: ExplanationRequest) throws {
        let fields = [draft.whatChanged, draft.impact].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.allSatisfy({ !$0.isEmpty }) else { throw DraftRejection.empty }
        guard fields.allSatisfy({ $0.count <= maxFieldLength }) else { throw DraftRejection.tooLong }
        guard fields.allSatisfy({ Explanation.sentences(in: $0).count <= maxSentencesPerField }) else {
            throw DraftRejection.tooManySentences
        }

        let text = fields.joined(separator: " ")
        if request.severity == .critical, let word = reassurances.firstMatch(in: text) {
            throw DraftRejection.reassurance(word)
        }
        if let word = verdicts.firstMatch(in: text) {
            throw DraftRejection.verdict(word)
        }
        for match in InstructionPatterns.url.matches(in: text) {
            let url = match.trimmingCharacters(in: CharacterSet(charactersIn: "'\"`.,;:!?"))
            if !request.maskedDiff.contains(url) { throw DraftRejection.unknownURL(url) }
        }
        if !isWritten(in: request.language, text) {
            throw DraftRejection.wrongLanguage
        }
    }

    /// The model sometimes forgets the projects, which are the whole point of the sentence.
    static func mentionsProjects(_ draft: ModelDraft, for request: ExplanationRequest) -> Bool {
        let names = request.scope.projects.map(\.name)
        return names.isEmpty || names.contains { draft.impact.localizedCaseInsensitiveContains($0) }
    }

    private static func isWritten(in language: ExplanationLanguage, _ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .french]
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return true }
        return dominant.rawValue == language.rawValue
    }
}
