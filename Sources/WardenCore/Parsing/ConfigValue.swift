import Foundation

/// A parsed configuration document, independent of its source format.
public indirect enum ConfigValue: Equatable, Sendable {
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

    init(foundationObject object: Any) {
        switch object {
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues(ConfigValue.init(foundationObject:)))
        case let array as [Any]:
            self = .array(array.map(ConfigValue.init(foundationObject:)))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.int64Value)
            }
        case let string as String:
            self = .string(string)
        default:
            self = .null
        }
    }

    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
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
