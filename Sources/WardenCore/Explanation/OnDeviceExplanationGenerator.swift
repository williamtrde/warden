import Foundation

/// Asks the on-device model to phrase an explanation. The recommendation is appended
/// from the rules: the model writes, but it does not judge.
public struct OnDeviceExplanationGenerator: ExplanationGenerator {
    private let client: LanguageModelClient

    public init(client: LanguageModelClient) {
        self.client = client
    }

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        let draft = try await client.draft(
            instructions: ExplanationPrompt.instructions(language: request.language),
            prompt: ExplanationPrompt.prompt(for: request)
        )
        try ExplanationValidator.validate(draft, for: request)
        let builtIn = RuleBasedExplanationGenerator.make(request)
        return Explanation(
            whatChanged: draft.whatChanged.trimmingCharacters(in: .whitespacesAndNewlines),
            impact: ExplanationValidator.mentionsProjects(draft, for: request)
                ? draft.impact.trimmingCharacters(in: .whitespacesAndNewlines)
                : builtIn.impact,
            recommendation: builtIn.recommendation,
            recommendedAction: builtIn.recommendedAction,
            source: .onDeviceAI,
            language: request.language
        )
    }
}

/// The generator the app uses: the model when possible, the rules otherwise. Never throws.
public struct ExplanationService: Sendable {
    public static let defaultTimeout: TimeInterval = 12

    private let primary: ExplanationGenerator?
    private let timeout: TimeInterval

    public init(primary: ExplanationGenerator?, timeout: TimeInterval = ExplanationService.defaultTimeout) {
        self.primary = primary
        self.timeout = timeout
    }

    public func explain(_ request: ExplanationRequest) async -> Explanation {
        guard let primary else { return RuleBasedExplanationGenerator.make(request) }
        do {
            return try await withTimeout { try await primary.explain(request) }
        } catch {
            return RuleBasedExplanationGenerator.make(request)
        }
    }

    private struct TimedOut: Error {}

    private func withTimeout(_ work: @escaping @Sendable () async throws -> Explanation) async throws -> Explanation {
        let seconds = timeout
        return try await withThrowingTaskGroup(of: Explanation.self) { group in
            group.addTask(operation: work)
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}
