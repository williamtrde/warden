@testable import WardenCore
import XCTest

final class FallbackExplanationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func scope(names: [String] = ["ATLAS", "HARBOR"], daysAgo: Double = 2, others: Int = 0, single: Bool = false) -> AffectedScope {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let projects = names.map { ProjectUsage(path: "/\($0)", name: $0, agent: .claudeCode, lastUsed: date, sessionsInWindow: 3) }
        return AffectedScope(agent: .claudeCode, projects: projects, otherCount: others, isSingleProject: single, lastUsed: names.isEmpty ? nil : date)
    }

    private func request(_ rules: [RuleID], language: ExplanationLanguage = .english, scope: AffectedScope? = nil, agent: Agent = .claudeCode) -> ExplanationRequest {
        ExplanationRequest(
            fileName: "~/.claude/settings.json",
            agent: agent,
            severity: rules.map(\.severity).max() ?? .info,
            rules: rules,
            details: Dictionary(uniqueKeysWithValues: rules.map { ($0, "detail-\($0.rawValue)") }),
            changeCount: rules.count,
            maskedDiff: "+ x",
            scope: scope ?? self.scope(),
            language: language,
            date: now
        )
    }

    /// One pass per rule and language: complete, personalized, 2 to 4 sentences, no leftovers.
    func testEveryRuleHasAClearExplanationInEveryLanguage() {
        for rule in RuleID.allCases {
            for language in ExplanationLanguage.allCases {
                let explanation = RuleBasedExplanationGenerator.make(request([rule], language: language))
                let context = "\(rule) \(language)"
                XCTAssertFalse(explanation.fullText.contains("{"), context)
                XCTAssertFalse(explanation.fullText.contains("}"), context)
                XCTAssertTrue(explanation.fullText.contains("ATLAS"), context)
                XCTAssertTrue(explanation.fullText.contains("HARBOR"), context)
                let sentenceCount = Explanation.sentences(in: explanation.fullText).count
                XCTAssertTrue((2...4).contains(sentenceCount), "\(context): \(sentenceCount)")
                XCTAssertEqual(explanation.source, .builtInRules, context)
                XCTAssertEqual(explanation.language, language, context)
                XCTAssertFalse(explanation.recommendation.isEmpty, context)
            }
        }
    }

    func testRulesHaveDistinctWordingPerLanguage() {
        for language in ExplanationLanguage.allCases {
            let texts = RuleID.allCases.map { FallbackTemplates.wording(for: $0, language: language).what }
            XCTAssertEqual(Set(texts).count, RuleID.allCases.count)
        }
        for rule in RuleID.allCases {
            XCTAssertNotEqual(
                FallbackTemplates.wording(for: rule, language: .english).what,
                FallbackTemplates.wording(for: rule, language: .french).what
            )
        }
    }

    func testHookExample() {
        let explanation = RuleBasedExplanationGenerator.make(request([.hookChanged], language: .french))
        XCTAssertTrue(explanation.impact.contains("chaque session Claude Code"))
        XCTAssertTrue(explanation.impact.contains("dans ATLAS et HARBOR que tu as utilisés cette semaine"), explanation.impact)
    }

    func testRecommendationsComeFromSeverity() {
        XCTAssertEqual(RuleBasedExplanationGenerator.make(request([.hookChanged])).recommendedAction, .revert)
        XCTAssertEqual(RuleBasedExplanationGenerator.make(request([.otherChange])).recommendedAction, .accept)
        XCTAssertEqual(RuleBasedExplanationGenerator.make(request([.fileDeleted])).recommendedAction, .revert)
    }

    func testScopeWording() {
        let english = ExplanationLanguage.english
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: []), now: now, language: english), "in all your projects")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: ["A"]), now: now, language: english), "in A, which you used this week")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: ["A", "B", "C"], daysAgo: 10), now: now, language: english), "in A, B and C, which you used in the last two weeks")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: ["A", "B"], others: 2), now: now, language: english), "in A, B and 2 other projects, which you used this week")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: ["A"], daysAgo: 30), now: now, language: english), "in A")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: ["A"]), now: now, language: .french), "dans A que tu as utilisé cette semaine")
        XCTAssertEqual(ScopeWording.phrase(for: scope(names: []), now: now, language: .french), "dans tous tes projets")
    }

    func testSeveralRulesAreListedWithoutExceedingFourSentences() {
        let explanation = RuleBasedExplanationGenerator.make(request([.hookChanged, .pluginAdded, .otherChange]))
        XCTAssertTrue(explanation.impact.contains("Warden also found: a new plugin."))
        XCTAssertLessThanOrEqual(Explanation.sentences(in: explanation.fullText).count, 4)
    }

    func testMissingDetailDisappearsCleanly() {
        var base = request([.hookChanged])
        base = ExplanationRequest(
            fileName: base.fileName, agent: base.agent, severity: base.severity, rules: base.rules, details: [:],
            changeCount: 1, maskedDiff: "", scope: base.scope, language: .english, date: now
        )
        XCTAssertEqual(RuleBasedExplanationGenerator.make(base).whatChanged, "A hook was added or changed in ~/.claude/settings.json.")
    }

    func testOtherAgentIsWordedGenerically() {
        let explanation = RuleBasedExplanationGenerator.make(request([.otherChange], agent: .other))
        XCTAssertTrue(explanation.impact.contains("your agent"))
    }

    func testFirstSentenceKeepsFileNames() {
        let explanation = RuleBasedExplanationGenerator.make(request([.hookChanged]))
        XCTAssertEqual(explanation.firstSentence, explanation.whatChanged)
        XCTAssertTrue(explanation.firstSentence.contains("settings.json"))
    }

    func testLanguageFollowsTheSystem() {
        XCTAssertEqual(ExplanationLanguage.current(preferred: ["fr-FR"]), .french)
        XCTAssertEqual(ExplanationLanguage.current(preferred: ["en-US"]), .english)
        XCTAssertEqual(ExplanationLanguage.current(preferred: ["de-DE"]), .english)
        XCTAssertEqual(ExplanationLanguage.current(preferred: []), .english)
    }
}
