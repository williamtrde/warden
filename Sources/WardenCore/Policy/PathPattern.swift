import Foundation

/// A pattern over configuration key paths, written with `/` between segments because
/// keys themselves may contain dots (`terminal.integrated.env.osx`).
///
/// - `*` matches exactly one segment.
/// - `prefix*` matches one segment starting with `prefix`.
/// - a trailing `**` matches the segment's whole subtree, including the node itself.
public struct PathPattern: Hashable, Sendable, CustomStringConvertible {
    public let description: String
    private let segments: [String]

    public init(_ pattern: String) {
        description = pattern
        segments = pattern.components(separatedBy: "/")
    }

    public func matches(_ path: [String]) -> Bool {
        var index = 0
        for segment in segments {
            if segment == "**" { return true }
            guard index < path.count, Self.segment(segment, matches: path[index]) else { return false }
            index += 1
        }
        return index == path.count
    }

    private static func segment(_ pattern: String, matches key: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") { return key.hasPrefix(pattern.dropLast()) }
        return pattern == key
    }
}
