import Foundation

/// An in-house JSON reader, because a security tool must see what agents see.
///
/// `JSONSerialization` keeps the first of two duplicate keys while Node keeps the last, which
/// would let `{"hooks":{},"hooks":{...}}` hide a hook. Here duplicates are an error, and an
/// unreadable config raises a critical alert. In tolerant mode the reader accepts what Cursor's
/// parser accepts: comments ending at `\n` or `\r`, trailing commas and missing commas.
struct JSONReader {
    static let maxDepth = 128

    private let bytes: [UInt8]
    private let tolerant: Bool
    private var index = 0

    static func parse(_ data: Data, tolerant: Bool) throws -> ConfigValue {
        var reader = JSONReader(bytes: Array(data), tolerant: tolerant)
        reader.skipByteOrderMark()
        try reader.skipTrivia()
        if reader.peek == nil { return .object([:]) }
        let value = try reader.readValue(depth: 0)
        try reader.skipTrivia()
        guard reader.peek == nil else { throw reader.failure("trailing content") }
        return value
    }

    private init(bytes: [UInt8], tolerant: Bool) {
        self.bytes = bytes
        self.tolerant = tolerant
    }

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    private func failure(_ reason: String) -> ConfigParseError {
        .invalidJSON("\(reason) at byte \(index)")
    }

    private mutating func skipByteOrderMark() {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
    }

    private mutating func skipTrivia() throws {
        while let byte = peek {
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                index += 1
            } else if tolerant, byte == UInt8(ascii: "/") {
                try skipComment()
            } else {
                return
            }
        }
    }

    private mutating func skipComment() throws {
        let next = index + 1 < bytes.count ? bytes[index + 1] : nil
        if next == UInt8(ascii: "/") {
            while let byte = peek, byte != 0x0A, byte != 0x0D { index += 1 }
        } else if next == UInt8(ascii: "*") {
            index += 2
            while index + 1 < bytes.count, !(bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/")) {
                index += 1
            }
            index = min(index + 2, bytes.count)
        } else {
            throw failure("unexpected /")
        }
    }

    private mutating func readValue(depth: Int) throws -> ConfigValue {
        guard depth < Self.maxDepth else { throw failure("nested too deeply") }
        guard let byte = peek else { throw failure("unexpected end") }
        switch byte {
        case UInt8(ascii: "{"): return try readObject(depth: depth)
        case UInt8(ascii: "["): return try readArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try readString())
        case UInt8(ascii: "t"): return try readLiteral("true", .bool(true))
        case UInt8(ascii: "f"): return try readLiteral("false", .bool(false))
        case UInt8(ascii: "n"): return try readLiteral("null", .null)
        default: return try readNumber()
        }
    }

    private mutating func readLiteral(_ text: String, _ value: ConfigValue) throws -> ConfigValue {
        let literal = Array(text.utf8)
        guard bytes[index...].starts(with: literal) else { throw failure("invalid literal") }
        index += literal.count
        return value
    }

    private mutating func readNumber() throws -> ConfigValue {
        let start = index
        while let byte = peek, "+-.eE0123456789".utf8.contains(byte) { index += 1 }
        guard start < index, let text = String(bytes: bytes[start..<index], encoding: .utf8) else {
            throw failure("unexpected character")
        }
        if let integer = Int64(text) { return .int(integer) }
        guard let number = Double(text) else { throw failure("invalid number") }
        return .double(number)
    }

    private mutating func readObject(depth: Int) throws -> ConfigValue {
        index += 1
        var members: [String: ConfigValue] = [:]
        while true {
            try skipTrivia()
            guard let byte = peek else { throw failure("unterminated object") }
            if byte == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            guard byte == UInt8(ascii: "\"") else { throw failure("expected a key") }
            let key = try readString()
            try skipTrivia()
            guard peek == UInt8(ascii: ":") else { throw failure("expected :") }
            index += 1
            try skipTrivia()
            let value = try readValue(depth: depth + 1)
            guard members[key] == nil else { throw ConfigParseError.duplicateKey(key) }
            members[key] = value
            try skipSeparator(closing: UInt8(ascii: "}"))
        }
    }

    private mutating func readArray(depth: Int) throws -> ConfigValue {
        index += 1
        var elements: [ConfigValue] = []
        while true {
            try skipTrivia()
            guard let byte = peek else { throw failure("unterminated array") }
            if byte == UInt8(ascii: "]") {
                index += 1
                return .array(elements)
            }
            elements.append(try readValue(depth: depth + 1))
            try skipSeparator(closing: UInt8(ascii: "]"))
        }
    }

    private mutating func skipSeparator(closing: UInt8) throws {
        try skipTrivia()
        if peek == UInt8(ascii: ",") {
            index += 1
            if !tolerant {
                try skipTrivia()
                if peek == closing { throw failure("trailing comma") }
            }
        } else if peek != closing, !tolerant {
            throw failure("expected a comma")
        }
    }

    private mutating func readString() throws -> String {
        index += 1
        var output: [UInt8] = []
        while let byte = peek {
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                // Lossy on purpose: invalid UTF-8 must not make a file unreadable to Warden alone.
                return String(decoding: output, as: UTF8.self) // swiftlint:disable:this optional_data_string_conversion
            case UInt8(ascii: "\\"):
                try readEscape(into: &output)
            default:
                output.append(byte)
            }
        }
        throw failure("unterminated string")
    }

    private mutating func readEscape(into output: inout [UInt8]) throws {
        guard let escape = peek else { throw failure("unterminated escape") }
        index += 1
        switch escape {
        case UInt8(ascii: "n"): output.append(0x0A)
        case UInt8(ascii: "t"): output.append(0x09)
        case UInt8(ascii: "r"): output.append(0x0D)
        case UInt8(ascii: "b"): output.append(0x08)
        case UInt8(ascii: "f"): output.append(0x0C)
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): output.append(escape)
        case UInt8(ascii: "u"): try readUnicodeEscape(into: &output)
        default: throw failure("invalid escape")
        }
    }

    private mutating func readUnicodeEscape(into output: inout [UInt8]) throws {
        var code = UInt32(try readHexQuad())
        if (0xD800..<0xDC00).contains(code), bytes[index...].starts(with: Array("\\u".utf8)) {
            let saved = index
            index += 2
            let low = UInt32(try readHexQuad())
            if (0xDC00..<0xE000).contains(low) {
                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
            } else {
                index = saved
            }
        }
        // A lone surrogate is accepted by JavaScript: keep reading, like the agents do.
        let scalar = Unicode.Scalar(code) ?? "\u{FFFD}"
        output.append(contentsOf: Array(String(scalar).utf8))
    }

    private mutating func readHexQuad() throws -> UInt16 {
        guard index + 4 <= bytes.count,
              let text = String(bytes: bytes[index..<index + 4], encoding: .utf8),
              let value = UInt16(text, radix: 16) else { throw failure("invalid unicode escape") }
        index += 4
        return value
    }
}
