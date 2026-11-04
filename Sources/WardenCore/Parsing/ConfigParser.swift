import Foundation

public enum ConfigParseError: Error, Equatable {
    case notUTF8
    case invalidJSON(String)
    case invalidTOML(line: Int, reason: String)
    case unstructuredFormat
}

/// Entry point turning raw file bytes into a `ConfigValue`.
public enum ConfigParser {
    public static func parse(_ data: Data, format: FileFormat) throws -> ConfigValue {
        switch format {
        case .json:
            return try parseJSON(data)
        case .jsonc:
            guard let text = String(data: data, encoding: .utf8) else { throw ConfigParseError.notUTF8 }
            return try parseJSON(Data(JSONCStripper.strip(text).utf8))
        case .toml:
            guard let text = String(data: data, encoding: .utf8) else { throw ConfigParseError.notUTF8 }
            return try TOMLParser.parse(text)
        case .instructions, .plainText:
            throw ConfigParseError.unstructuredFormat
        }
    }

    private static func parseJSON(_ data: Data) throws -> ConfigValue {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return .object([:])
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return ConfigValue(foundationObject: object)
        } catch {
            throw ConfigParseError.invalidJSON(error.localizedDescription)
        }
    }
}
