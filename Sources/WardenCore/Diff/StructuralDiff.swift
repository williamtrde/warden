import Foundation

/// A change to a single leaf of a configuration document.
public struct ConfigChange: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case added, removed, modified
    }

    public let kind: Kind
    /// Path segments from the root. Array elements use `StructuralDiff.setElement` for
    /// arrays of scalars (compared as sets) and a decimal index otherwise.
    public let path: [String]
    public let oldValue: ConfigValue?
    public let newValue: ConfigValue?

    public init(kind: Kind, path: [String], oldValue: ConfigValue?, newValue: ConfigValue?) {
        self.kind = kind
        self.path = path
        self.oldValue = oldValue
        self.newValue = newValue
    }

    public var dottedPath: String { path.joined(separator: ".") }
}

/// Compares two parsed documents and reports leaf-level changes.
///
/// Whole subtrees are always expanded to their leaves, so a rule written for
/// `mcpServers.*.url` also fires when the entire `mcpServers` object is new.
public enum StructuralDiff {
    /// Path segment standing for "an element of this set-like array".
    public static let setElement = "[]"

    public static func compute(old: ConfigValue?, new: ConfigValue?) -> [ConfigChange] {
        var changes: [ConfigChange] = []
        walk(old, new, path: [], into: &changes)
        return changes.sorted { $0.dottedPath < $1.dottedPath }
    }

    private static func walk(_ old: ConfigValue?, _ new: ConfigValue?, path: [String], into changes: inout [ConfigChange]) {
        switch (old, new) {
        case (nil, nil):
            return
        case (nil, let value?):
            expand(value, kind: .added, path: path, into: &changes)
        case (let value?, nil):
            expand(value, kind: .removed, path: path, into: &changes)
        case (.object(let lhs)?, .object(let rhs)?):
            for key in Set(lhs.keys).union(rhs.keys) {
                walk(lhs[key], rhs[key], path: path + [key], into: &changes)
            }
        case (.array(let lhs)?, .array(let rhs)?):
            compareArrays(lhs, rhs, path: path, into: &changes)
        case (let lhs?, let rhs?):
            if lhs != rhs {
                changes.append(.init(kind: .modified, path: path, oldValue: lhs, newValue: rhs))
            }
        }
    }

    private static func compareArrays(_ old: [ConfigValue], _ new: [ConfigValue], path: [String], into changes: inout [ConfigChange]) {
        guard old != new else { return }
        if isScalarArray(old), isScalarArray(new) {
            for value in new where !old.contains(value) {
                changes.append(.init(kind: .added, path: path + [setElement], oldValue: nil, newValue: value))
            }
            for value in old where !new.contains(value) {
                changes.append(.init(kind: .removed, path: path + [setElement], oldValue: value, newValue: nil))
            }
            if Set(old.map(\.displayString)) == Set(new.map(\.displayString)) {
                // Same elements in a new order: order matters for `args`, so it still counts.
                changes.append(.init(kind: .modified, path: path, oldValue: .array(old), newValue: .array(new)))
            }
            return
        }
        for index in 0..<max(old.count, new.count) {
            walk(
                old.indices.contains(index) ? old[index] : nil,
                new.indices.contains(index) ? new[index] : nil,
                path: path + [String(index)],
                into: &changes
            )
        }
    }

    private static func isScalarArray(_ array: [ConfigValue]) -> Bool {
        array.allSatisfy { value in
            switch value {
            case .array, .object: return false
            default: return true
            }
        }
    }

    private static func expand(_ value: ConfigValue, kind: ConfigChange.Kind, path: [String], into changes: inout [ConfigChange]) {
        func leaf(_ leafPath: [String], _ leafValue: ConfigValue) -> ConfigChange {
            ConfigChange(
                kind: kind,
                path: leafPath,
                oldValue: kind == .removed ? leafValue : nil,
                newValue: kind == .added ? leafValue : nil
            )
        }
        switch value {
        case .object(let members) where !members.isEmpty:
            for (key, member) in members {
                expand(member, kind: kind, path: path + [key], into: &changes)
            }
        case .array(let elements) where !elements.isEmpty:
            if isScalarArray(elements) {
                changes.append(contentsOf: elements.map { leaf(path + [setElement], $0) })
            } else {
                for (index, element) in elements.enumerated() {
                    expand(element, kind: kind, path: path + [String(index)], into: &changes)
                }
            }
        default:
            changes.append(leaf(path, value))
        }
    }
}
