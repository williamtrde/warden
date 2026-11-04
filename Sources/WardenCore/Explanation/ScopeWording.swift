import Foundation

/// Puts an `AffectedScope` into words: "in ATLAS and HARBOR, which you used this week".
enum ScopeWording {
    static func phrase(for scope: AffectedScope, now: Date, language: ExplanationLanguage) -> String {
        let french = language == .french
        let names = scope.projects.map(\.name)
        guard !names.isEmpty else {
            return french ? "dans tous tes projets" : "in all your projects"
        }
        var list = join(names, otherCount: scope.otherCount, language: language)
        list = (french ? "dans " : "in ") + list
        guard let recency = recency(of: scope, now: now, language: language) else { return list }
        return "\(list)\(recency)"
    }

    private static func join(_ names: [String], otherCount: Int, language: ExplanationLanguage) -> String {
        let french = language == .french
        let and = french ? "et" : "and"
        if otherCount > 0 {
            let others: String
            if french {
                others = otherCount == 1 ? "1 autre projet" : "\(otherCount) autres projets"
            } else {
                others = otherCount == 1 ? "1 other project" : "\(otherCount) other projects"
            }
            return "\(names.joined(separator: ", ")) \(and) \(others)"
        }
        guard let last = names.last, names.count > 1 else { return names.first ?? "" }
        return "\(names.dropLast().joined(separator: ", ")) \(and) \(last)"
    }

    private static func recency(of scope: AffectedScope, now: Date, language: ExplanationLanguage) -> String? {
        guard let lastUsed = scope.lastUsed, lastUsed > .distantPast else { return nil }
        let days = now.timeIntervalSince(lastUsed) / 86_400
        guard days <= UsageContext.activeWindow / 86_400 else { return nil }
        let plural = scope.projects.count + scope.otherCount > 1
        let thisWeek = days <= 7
        if language == .french {
            let verb = plural ? "que tu as utilisés" : "que tu as utilisé"
            return " \(verb) \(thisWeek ? "cette semaine" : "ces deux dernières semaines")"
        }
        return ", which you used \(thisWeek ? "this week" : "in the last two weeks")"
    }
}
