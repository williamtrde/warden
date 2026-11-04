@testable import WardenCore
import XCTest

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
        return try Data(contentsOf: url)
    }
}

/// Classifies the change between two JSON documents, the way the engine does for an `everyChange` file.
func classifyJSON(_ old: String, _ new: String) throws -> [RiskFinding] {
    let lhs = try ConfigParser.parse(Data(old.utf8), format: .json)
    let rhs = try ConfigParser.parse(Data(new.utf8), format: .json)
    return RiskClassifier.classify(changes: StructuralDiff.compute(old: lhs, new: rhs), old: lhs, new: rhs)
}

func classifyTOML(_ old: String, _ new: String) throws -> [RiskFinding] {
    let lhs = try ConfigParser.parse(Data(old.utf8), format: .toml)
    let rhs = try ConfigParser.parse(Data(new.utf8), format: .toml)
    return RiskClassifier.classify(changes: StructuralDiff.compute(old: lhs, new: rhs), old: lhs, new: rhs)
}
