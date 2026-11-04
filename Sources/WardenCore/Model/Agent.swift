import Foundation

/// An AI coding agent whose configuration Warden protects.
public enum Agent: String, Codable, CaseIterable, Sendable, Hashable {
    case claudeCode
    case codex
    case cursor
    /// A file the user added by hand: Warden does not know which agent reads it.
    case other

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .other: return "Other"
        }
    }
}
