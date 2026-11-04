import Foundation

/// A parsed configuration document, independent of its source format.
public indirect enum ConfigValue: Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([ConfigValue])
    case object([String: ConfigValue])

    /// A short, human-readable rendering used by diffs and explanations.
    public var displayString: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .array, .object:
            return (try? serialized()).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// True for values that carry no meaning of their own: `null`, `false`, `[]`, `{}`, `""`.
    public var isBlank: Bool {
        switch self {
        case .null: return true
        case .bool(let value): return !value
        case .string(let value): return value.isEmpty
        case .array(let value): return value.isEmpty
        case .object(let value): return value.isEmpty
        case .int, .double: return false
        }
    }

    /// Returns the value at `path`, if any. Array elements are addressed by decimal index.
    public func value(at path: [String]) -> ConfigValue? {
        guard let head = path.first else { return self }
        let rest = Array(path.dropFirst())
        switch self {
        case .object(let members):
            return members[head]?.value(at: rest)
        case .array(let elements):
            guard let index = Int(head), elements.indices.contains(index) else { return nil }
            return elements[index].value(at: rest)
        default:
            return nil
        }
    }

    // MARK: - Foundation bridging

    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value.isFinite ? value : String(value) // JSON cannot hold `nan` or `inf`.
        case .string(let value): return value
        case .array(let value): return value.map(\.foundationObject)
        case .object(let value): return value.mapValues(\.foundationObject)
        }
    }

    /// Stable, pretty-printed JSON. Keys are sorted so that equal values serialize identically.
    public func serialized() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: foundationObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
    }
}

/// Compares bytes, not meaning. Swift's `==` treats canonically equivalent strings as equal, so a
/// path swapped for a Unicode lookalike would otherwise count as unchanged.
extension ConfigValue: Equatable {
    public static func == (lhs: ConfigValue, rhs: ConfigValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let left), .bool(let right)): return left == right
        case (.int(let left), .int(let right)): return left == right
        case (.double(let left), .double(let right)): return left.bitPattern == right.bitPattern
        case (.string(let left), .string(let right)): return left.utf8.elementsEqual(right.utf8)
        case (.array(let left), .array(let right)): return left == right
        case (.object(let left), .object(let right)): return left == right
        default: return false
        }
    }
}
