import Foundation

/// The fallback: clear explanations with no model at all.
public struct RuleBasedExplanationGenerator: ExplanationGenerator {
    public init() {}

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        Self.make(request)
    }

    public static func make(_ request: ExplanationRequest) -> Explanation {
        let language = request.language
        let primary = request.rules.first ?? .otherChange
        let wording = FallbackTemplates.wording(for: primary, language: language)
        let others = request.rules.dropFirst()
            .filter { $0 != .otherChange }
            .map { FallbackTemplates.wording(for: $0, language: language).label }

        var impact = fill(wording.impact, rule: primary, request: request)
        if !others.isEmpty {
            impact += " " + FallbackTemplates.alsoFound(others, language: language)
        }
        let action = recommendedAction(for: request)
        return Explanation(
            whatChanged: fill(wording.what, rule: primary, request: request),
            impact: impact,
            recommendation: FallbackTemplates.recommendation(for: action, severity: request.severity, language: language),
            recommendedAction: action,
            source: .builtInRules,
            language: language
        )
    }

    /// The advice depends on the rules alone, so a crafted diff cannot talk the model into "accept".
    public static func recommendedAction(for request: ExplanationRequest) -> RecommendedAction {
        if request.severity == .critical { return .revert }
        return request.rules.contains(where: { $0 == .fileDeleted || $0 == .malformedConfig }) ? .revert : .accept
    }

    static func fill(_ template: String, rule: RuleID, request: ExplanationRequest) -> String {
        let detail = request.details[rule] ?? ""
        let scope = ScopeWording.phrase(for: request.scope, now: request.date, language: request.language)
        return template
            .replacingOccurrences(of: " ({detail})", with: detail.isEmpty ? "" : " (\(detail))")
            .replacingOccurrences(of: "{detail}", with: detail)
            .replacingOccurrences(of: "{agent}", with: agentName(request))
            .replacingOccurrences(of: "{file}", with: request.fileName)
            .replacingOccurrences(of: "{scope}", with: scope)
    }

    private static func agentName(_ request: ExplanationRequest) -> String {
        if request.agent != .other { return request.agent.displayName }
        return request.language == .french ? "ton agent" : "your agent"
    }
}
