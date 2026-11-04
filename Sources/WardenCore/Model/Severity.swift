import Foundation

/// How urgently a change needs a human decision.
public enum Severity: Int, Codable, Comparable, Sendable, CaseIterable {
    case info = 0
    case critical = 1

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
