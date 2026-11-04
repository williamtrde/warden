import Foundation

/// One line of a rendered diff.
public struct DiffLine: Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case context, added, removed
    }

    /// Why a line deserves visual attention.
    public enum Emphasis: String, Codable, Sendable {
        case none
        /// Worth a look, but not dangerous by itself (a plain URL in CLAUDE.md).
        case notable
        /// Triggered a critical rule.
        case critical
    }

    public let id: Int
    public let kind: Kind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
    public var emphasis: Emphasis

    public init(id: Int, kind: Kind, oldNumber: Int?, newNumber: Int?, text: String, emphasis: Emphasis = .none) {
        self.id = id
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
        self.emphasis = emphasis
    }
}

/// A contiguous group of changed lines with surrounding context.
public struct DiffHunk: Equatable, Sendable, Identifiable {
    public var id: Int { lines.first?.id ?? 0 }
    public var lines: [DiffLine]
}

/// A line-based diff, built on the standard library's Myers implementation.
public struct LineDiff: Equatable, Sendable {
    public var hunks: [DiffHunk]

    public var isEmpty: Bool { hunks.isEmpty }
    public var allLines: [DiffLine] { hunks.flatMap(\.lines) }
    public var addedLines: [DiffLine] { allLines.filter { $0.kind == .added } }
    public var removedLines: [DiffLine] { allLines.filter { $0.kind == .removed } }

    public static func compute(old: String, new: String, context: Int = 3) -> LineDiff {
        let oldLines = splitLines(old)
        let newLines = splitLines(new)
        let difference = newLines.difference(from: oldLines)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var lines: [DiffLine] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < oldLines.count || newIndex < newLines.count {
            let id = lines.count
            if removed.contains(oldIndex) {
                lines.append(.init(id: id, kind: .removed, oldNumber: oldIndex + 1, newNumber: nil, text: oldLines[oldIndex]))
                oldIndex += 1
            } else if inserted.contains(newIndex) {
                lines.append(.init(id: id, kind: .added, oldNumber: nil, newNumber: newIndex + 1, text: newLines[newIndex]))
                newIndex += 1
            } else {
                lines.append(.init(id: id, kind: .context, oldNumber: oldIndex + 1, newNumber: newIndex + 1, text: newLines[newIndex]))
                oldIndex += 1
                newIndex += 1
            }
        }
        return LineDiff(hunks: groupIntoHunks(lines, context: context))
    }

    /// Splits on newlines without inventing an empty last line for a trailing newline.
    static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    private static func groupIntoHunks(_ lines: [DiffLine], context: Int) -> [DiffHunk] {
        let changed = lines.indices.filter { lines[$0].kind != .context }
        guard let first = changed.first, let last = changed.last else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start = first
        var end = first
        for index in changed.dropFirst() {
            if index - end > context * 2 {
                ranges.append(start...end)
                start = index
            }
            end = index
        }
        ranges.append(start...last)

        return ranges.map { range in
            let lower = max(range.lowerBound - context, 0)
            let upper = min(range.upperBound + context, lines.count - 1)
            return DiffHunk(lines: Array(lines[lower...upper]))
        }
    }

    /// A compact unified rendering, used as model input.
    public var unifiedText: String {
        hunks.map { hunk in
            hunk.lines.map { line in
                switch line.kind {
                case .added: return "+ \(line.text)"
                case .removed: return "- \(line.text)"
                case .context: return "  \(line.text)"
                }
            }.joined(separator: "\n")
        }.joined(separator: "\n...\n")
    }
}
