import Foundation

/// What the model is allowed to write. The recommendation is deliberately absent.
public struct ModelDraft: Equatable, Sendable {
    public let whatChanged: String
    public let impact: String

    public init(whatChanged: String, impact: String) {
        self.whatChanged = whatChanged
        self.impact = impact
    }
}

/// A thin seam over the language model, so the logic around it can be tested without Apple Intelligence.
public protocol LanguageModelClient: Sendable {
    var isAvailable: Bool { get }
    func draft(instructions: String, prompt: String) async throws -> ModelDraft
}
