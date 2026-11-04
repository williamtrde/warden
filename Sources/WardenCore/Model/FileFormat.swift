import Foundation

/// How Warden should read a watched file.
public enum FileFormat: String, Codable, Sendable, CaseIterable {
    case json
    /// JSON with comments and trailing commas, as VS Code and Cursor write it.
    case jsonc
    case toml
    /// Natural-language instructions for an agent (CLAUDE.md, AGENTS.md).
    case instructions
    /// Anything else: compared line by line, no structure.
    case plainText

    /// Guesses a format from a file name, for files the user adds by hand.
    public static func guess(fromFileName name: String) -> FileFormat {
        let lowered = name.lowercased()
        if lowered.hasSuffix(".jsonc") { return .jsonc }
        if lowered.hasSuffix(".json") { return .json }
        if lowered.hasSuffix(".toml") { return .toml }
        if lowered.hasSuffix(".md") || lowered.hasSuffix(".mdc") { return .instructions }
        return .plainText
    }

    public var isStructured: Bool {
        switch self {
        case .json, .jsonc, .toml: return true
        case .instructions, .plainText: return false
        }
    }
}
