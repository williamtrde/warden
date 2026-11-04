import Foundation

public enum ConfigParseError: Error, Equatable {
    case notUTF8
    case invalidJSON(String)
    case duplicateKey(String)
    case invalidTOML(line: Int, reason: String)
    case unstructuredFormat
}

/// Entry point turning raw file bytes into a `ConfigValue`.
public enum ConfigParser {
    public static func parse(_ data: Data, format: FileFormat) throws -> ConfigValue {
        switch format {
        case .json:
            return try JSONReader.parse(data, tolerant: false)
        case .jsonc:
            return try JSONReader.parse(data, tolerant: true)
        case .toml:
            guard let text = String(data: data, encoding: .utf8) else { throw ConfigParseError.notUTF8 }
            return try TOMLParser.parse(text)
        case .instructions, .plainText:
            throw ConfigParseError.unstructuredFormat
        }
    }
}
