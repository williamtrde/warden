import Foundation

/// A small TOML reader covering what agent configs use: tables, arrays of tables, dotted and quoted
/// keys, strings, numbers, booleans, arrays and inline tables. Dates are kept as plain strings.
/// Written in-house so that Warden keeps zero third-party runtime dependencies.
enum TOMLParser {
    static func parse(_ source: String) throws -> ConfigValue {
        var reader = Reader(source)
        var root = Table()
        var currentPath: [Segment] = []

        while true {
            reader.skipBlankAndComments()
            guard let scalar = reader.peek else { break }

            if scalar == "[" {
                let isArray = reader.peek(offset: 1) == "["
                reader.advance(by: isArray ? 2 : 1)
                let keys = try reader.readKeyPath()
                try reader.expect("]")
                if isArray { try reader.expect("]") }
                try reader.expectEndOfLine()
                currentPath = try root.openTable(at: keys, isArray: isArray, line: reader.line)
            } else {
                let keys = try reader.readKeyPath()
                try reader.expect("=")
                let value = try reader.readValue()
                try reader.expectEndOfLine()
                try root.set(value, at: keys, under: currentPath, line: reader.line)
            }
        }
        return root.configValue
    }

    /// One step from the root: a named member, optionally entering the last element of an array of tables.
    struct Segment {
        let key: String
        let entersLastElement: Bool
    }
}

/// Mutable tree used while parsing.
private struct Table {
    indirect enum Node {
        case value(ConfigValue)
        case table(Table)
        case tableArray([Table])
    }

    var members: [String: Node] = [:]

    var configValue: ConfigValue {
        .object(members.mapValues { node in
            switch node {
            case .value(let value): return value
            case .table(let table): return table.configValue
            case .tableArray(let tables): return .array(tables.map(\.configValue))
            }
        })
    }

    /// Creates the table named by a `[header]` or `[[header]]` and returns its resolved path.
    mutating func openTable(at keys: [String], isArray: Bool, line: Int) throws -> [TOMLParser.Segment] {
        guard let last = keys.last else {
            throw ConfigParseError.invalidTOML(line: line, reason: "empty table header")
        }
        var path: [TOMLParser.Segment] = []
        for key in keys.dropLast() {
            let isTableArray: Bool
            if case .tableArray = members(at: path)?[key] { isTableArray = true } else { isTableArray = false }
            path.append(.init(key: key, entersLastElement: isTableArray))
        }
        try update(path, line: line) { table in
            if isArray {
                if case .tableArray(var tables) = table.members[last] {
                    tables.append(Table())
                    table.members[last] = .tableArray(tables)
                } else {
                    table.members[last] = .tableArray([Table()])
                }
            } else if table.members[last] == nil {
                table.members[last] = .table(Table())
            }
        }
        path.append(.init(key: last, entersLastElement: isArray))
        return path
    }

    mutating func set(_ value: ConfigValue, at keys: [String], under base: [TOMLParser.Segment], line: Int) throws {
        guard let last = keys.last else {
            throw ConfigParseError.invalidTOML(line: line, reason: "empty key")
        }
        let path = base + keys.dropLast().map { TOMLParser.Segment(key: $0, entersLastElement: false) }
        try update(path, line: line) { $0.members[last] = .value(value) }
    }

    private func members(at path: [TOMLParser.Segment]) -> [String: Node]? {
        var table = self
        for segment in path {
            switch table.members[segment.key] {
            case .table(let next): table = next
            case .tableArray(let tables):
                guard let next = tables.last else { return nil }
                table = next
            default: return nil
            }
        }
        return table.members
    }

    private mutating func update(
        _ path: [TOMLParser.Segment],
        line: Int,
        _ body: (inout Table) throws -> Void
    ) throws {
        guard let segment = path.first else {
            try body(&self)
            return
        }
        let rest = Array(path.dropFirst())
        switch members[segment.key] {
        case nil:
            var child = Table()
            try child.update(rest, line: line, body)
            members[segment.key] = .table(child)
        case .table(var child):
            try child.update(rest, line: line, body)
            members[segment.key] = .table(child)
        case .tableArray(var tables):
            guard var child = tables.popLast() else {
                throw ConfigParseError.invalidTOML(line: line, reason: "empty array of tables")
            }
            try child.update(rest, line: line, body)
            tables.append(child)
            members[segment.key] = .tableArray(tables)
        case .value:
            throw ConfigParseError.invalidTOML(line: line, reason: "key \(segment.key) is not a table")
        }
    }
}

/// Character-level cursor.
private struct Reader {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private(set) var line = 1

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    var peek: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    func peek(offset: Int) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    mutating func advance(by count: Int = 1) {
        for _ in 0..<count where index < scalars.count {
            if scalars[index] == "\n" { line += 1 }
            index += 1
        }
    }

    private func failure(_ reason: String) -> ConfigParseError {
        .invalidTOML(line: line, reason: reason)
    }

    mutating func skipInlineSpace() {
        while peek == " " || peek == "\t" { advance() }
    }

    mutating func skipComment() {
        guard peek == "#" else { return }
        while let scalar = peek, scalar != "\n" {
            _ = scalar
            advance()
        }
    }

    mutating func skipBlankAndComments() {
        while let scalar = peek {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                advance()
            } else if scalar == "#" {
                skipComment()
            } else {
                return
            }
        }
    }

    mutating func expect(_ scalar: Unicode.Scalar) throws {
        skipInlineSpace()
        guard peek == scalar else { throw failure("expected \(scalar)") }
        advance()
    }

    mutating func expectEndOfLine() throws {
        skipInlineSpace()
        skipComment()
        if peek == "\r" { advance() }
        guard peek == nil || peek == "\n" else { throw failure("unexpected trailing content") }
    }

    mutating func readKeyPath() throws -> [String] {
        var keys: [String] = []
        repeat {
            if !keys.isEmpty { advance() }
            skipInlineSpace()
            keys.append(try readKey())
            skipInlineSpace()
        } while peek == "."
        return keys
    }

    private mutating func readKey() throws -> String {
        if peek == "\"" || peek == "'" { return try readSingleLineString() }
        var key = String.UnicodeScalarView()
        while let scalar = peek, Self.isBareKeyScalar(scalar) {
            key.append(scalar)
            advance()
        }
        guard !key.isEmpty else { throw failure("expected a key") }
        return String(key)
    }

    private static func isBareKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "-" || (scalar.isASCII && scalar.properties.isAlphabetic)
            || ("0"..."9").contains(scalar)
    }

    mutating func readValue() throws -> ConfigValue {
        skipInlineSpace()
        guard let scalar = peek else { throw failure("expected a value") }
        switch scalar {
        case "\"", "'":
            let quote = scalar
            if peek(offset: 1) == quote, peek(offset: 2) == quote {
                return .string(try readMultilineString(quote: quote))
            }
            return .string(try readSingleLineString())
        case "[": return try readArray()
        case "{": return try readInlineTable()
        default: return try readBareValue()
        }
    }

    private mutating func readSingleLineString() throws -> String {
        guard let quote = peek else { throw failure("expected a string") }
        advance()
        var text = String.UnicodeScalarView()
        while let scalar = peek {
            if scalar == "\n" { break }
            advance()
            if scalar == quote { return String(text) }
            if scalar == "\\", quote == "\"" {
                try appendEscape(to: &text)
            } else {
                text.append(scalar)
            }
        }
        throw failure("unterminated string")
    }

    private mutating func readMultilineString(quote: Unicode.Scalar) throws -> String {
        advance(by: 3)
        if peek == "\r" { advance() }
        if peek == "\n" { advance() }
        var text = String.UnicodeScalarView()
        while let scalar = peek {
            if scalar == quote, peek(offset: 1) == quote, peek(offset: 2) == quote {
                advance(by: 3)
                return String(text)
            }
            advance()
            if scalar == "\\", quote == "\"" {
                if peek == "\n" || peek == "\r" {
                    while let next = peek, next.properties.isWhitespace {
                        _ = next
                        advance()
                    }
                } else {
                    try appendEscape(to: &text)
                }
            } else {
                text.append(scalar)
            }
        }
        throw failure("unterminated multiline string")
    }

    private mutating func appendEscape(to text: inout String.UnicodeScalarView) throws {
        guard let escape = peek else { throw failure("unterminated escape") }
        advance()
        switch escape {
        case "n": text.append("\n")
        case "t": text.append("\t")
        case "r": text.append("\r")
        case "b": text.append("\u{08}")
        case "f": text.append("\u{0C}")
        case "\"": text.append("\"")
        case "\\": text.append("\\")
        case "u": text.append(try readUnicodeEscape(digits: 4))
        case "U": text.append(try readUnicodeEscape(digits: 8))
        default: throw failure("invalid escape")
        }
    }

    private mutating func readUnicodeEscape(digits: Int) throws -> Unicode.Scalar {
        var hex = ""
        for _ in 0..<digits {
            guard let scalar = peek else { throw failure("unterminated unicode escape") }
            hex.unicodeScalars.append(scalar)
            advance()
        }
        guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
            throw failure("invalid unicode escape")
        }
        return scalar
    }

    private mutating func readArray() throws -> ConfigValue {
        advance()
        var elements: [ConfigValue] = []
        while true {
            skipBlankAndComments()
            if peek == "]" {
                advance()
                return .array(elements)
            }
            elements.append(try readValue())
            skipBlankAndComments()
            if peek == "," {
                advance()
            } else if peek != "]" {
                throw failure("expected , or ] in array")
            }
        }
    }

    private mutating func readInlineTable() throws -> ConfigValue {
        advance()
        var table = Table()
        while true {
            skipBlankAndComments()
            if peek == "}" {
                advance()
                return table.configValue
            }
            let keys = try readKeyPath()
            try expect("=")
            try table.set(try readValue(), at: keys, under: [], line: line)
            skipBlankAndComments()
            if peek == "," {
                advance()
            } else if peek != "}" {
                throw failure("expected , or } in inline table")
            }
        }
    }

    private mutating func readBareValue() throws -> ConfigValue {
        var raw = String.UnicodeScalarView()
        while let scalar = peek, !",]}#\n\r".unicodeScalars.contains(scalar) {
            raw.append(scalar)
            advance()
        }
        let text = String(raw).trimmingCharacters(in: .whitespaces)
        switch text {
        case "": throw failure("expected a value")
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        let digits = text.replacingOccurrences(of: "_", with: "")
        if let integer = Int64(digits) { return .int(integer) }
        if let number = Double(digits) { return .double(number) }
        if text.first?.isNumber == true { return .string(text) } // Dates and times.
        throw failure("invalid value \(text)")
    }
}
