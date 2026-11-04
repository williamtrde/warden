@testable import WardenCore
import XCTest

final class ParsingTests: XCTestCase {
    func testJSONKeepsTypes() throws {
        let value = try ConfigParser.parse(Data(#"{"a":1,"b":1.5,"c":true,"d":null,"e":"x","f":[1],"g":{}}"#.utf8), format: .json)
        XCTAssertEqual(value.value(at: ["a"]), .int(1))
        XCTAssertEqual(value.value(at: ["b"]), .double(1.5))
        XCTAssertEqual(value.value(at: ["c"]), .bool(true))
        XCTAssertEqual(value.value(at: ["d"]), .null)
        XCTAssertEqual(value.value(at: ["f", "0"]), .int(1))
    }

    func testEmptyJSONFileIsAnEmptyObject() throws {
        XCTAssertEqual(try ConfigParser.parse(Data(" \n".utf8), format: .json), .object([:]))
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try ConfigParser.parse(Data("{oops".utf8), format: .json))
    }

    func testJSONCStripsCommentsAndTrailingCommas() throws {
        let source = """
        {
          // a comment with "quotes"
          "url": "http://example.com/a//b", /* block */
          "list": [1, 2,],
        }
        """
        let value = try ConfigParser.parse(Data(source.utf8), format: .jsonc)
        XCTAssertEqual(value.value(at: ["url"]), .string("http://example.com/a//b"))
        XCTAssertEqual(value.value(at: ["list"]), .array([.int(1), .int(2)]))
    }

    func testDuplicateKeysAreRefused() {
        let text = #"{"hooks":{},"hooks":{"Stop":[{"command":"evil"}]}}"#
        XCTAssertThrowsError(try ConfigParser.parse(Data(text.utf8), format: .json)) {
            XCTAssertEqual($0 as? ConfigParseError, .duplicateKey("hooks"))
        }
    }

    func testJSONCCommentEndsAtCarriageReturn() throws {
        let value = try ConfigParser.parse(Data("{ // note\r\"http.proxy\":\"http://evil\"\n}".utf8), format: .jsonc)
        XCTAssertEqual(value.value(at: ["http.proxy"]), .string("http://evil"))
    }

    func testJSONCToleratesMissingCommaLikeCursor() throws {
        let value = try ConfigParser.parse(Data(#"{"a":1 "http.proxy":"x"}"#.utf8), format: .jsonc)
        XCTAssertEqual(value.value(at: ["http.proxy"]), .string("x"))
        XCTAssertThrowsError(try ConfigParser.parse(Data(#"{"a":1 "b":2}"#.utf8), format: .json))
        XCTAssertThrowsError(try ConfigParser.parse(Data(#"{"a":1,}"#.utf8), format: .json))
    }

    func testJSONReadsWhatNodeReads() throws {
        XCTAssertEqual(try ConfigParser.parse(Data(#"{"x":1e999}"#.utf8), format: .json).value(at: ["x"]), .double(.infinity))
        XCTAssertEqual(try ConfigParser.parse(Data(#"{"x":"\ud800"}"#.utf8), format: .json).value(at: ["x"]), .string("\u{FFFD}"))
        XCTAssertEqual(try ConfigParser.parse(Data(#"{"x":"\ud83d\ude00"}"#.utf8), format: .json).value(at: ["x"]), .string("😀"))
        XCTAssertEqual(try ConfigParser.parse(Data("\u{FEFF}{\"x\":1}".utf8), format: .json).value(at: ["x"]), .int(1))
    }

    func testDeepNestingIsRefusedNotACrash() {
        let json = String(repeating: "[", count: 60_000)
        XCTAssertThrowsError(try ConfigParser.parse(Data(json.utf8), format: .json))
        let toml = "x = " + String(repeating: "[", count: 60_000)
        XCTAssertThrowsError(try ConfigParser.parse(Data(toml.utf8), format: .toml))
        let dotted = (0..<60_000).map { _ in "a" }.joined(separator: ".") + " = 1"
        XCTAssertThrowsError(try ConfigParser.parse(Data(dotted.utf8), format: .toml))
    }

    func testNonFiniteNumbersDoNotCrashSerialization() throws {
        let value = try ConfigParser.parse(Data("x = [nan]\ny = inf\n".utf8), format: .toml)
        XCTAssertNoThrow(try value.serialized())
        XCTAssertEqual(value, value)
    }

    func testTOMLMultilineCornerCases() throws {
        let source = #"""
        a = """x"""""
        b = '''y'''''
        c = """p \%%
          q"""
        """#.replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "%%", with: "   ")
        let value = try ConfigParser.parse(Data(source.utf8), format: .toml)
        XCTAssertEqual(value.value(at: ["a"]), .string("x\"\""))
        XCTAssertEqual(value.value(at: ["b"]), .string("y''"))
        XCTAssertEqual(value.value(at: ["c"]), .string("p q"))
    }

    func testTOMLReadsThePostmanConfig() throws {
        let source = """
        model = "gpt-5" # trailing comment
        approval_policy = "on-request"

        [marketplaces.postman]
        source_type = "git"
        source = "https://github.com/postmanlabs/postman-plugin.git"

        [plugins."postman@postman"]
        enabled = true

        [hooks.state."postman@postman:hooks/codex-hooks.json:session_start:0:0"]
        trusted_hash = "sha256:b67ddd"
        """
        let value = try ConfigParser.parse(Data(source.utf8), format: .toml)
        XCTAssertEqual(value.value(at: ["model"]), .string("gpt-5"))
        XCTAssertEqual(value.value(at: ["plugins", "postman@postman", "enabled"]), .bool(true))
        XCTAssertEqual(
            value.value(at: ["hooks", "state", "postman@postman:hooks/codex-hooks.json:session_start:0:0", "trusted_hash"]),
            .string("sha256:b67ddd")
        )
    }

    func testTOMLValuesAndStructures() throws {
        let source = #"""
        a.b = 1_000
        pi = 3.14
        day = 2026-11-04
        args = ["-y", 'literal\n', ]
        env = { TOKEN = "x", NESTED.KEY = true }
        text = """
        two
        lines"""
        escaped = "tab\there é"

        [[servers]]
        name = "one"

        [[servers]]
        name = "two"

        [servers.extra]
        ok = true
        """#
        let value = try ConfigParser.parse(Data(source.utf8), format: .toml)
        XCTAssertEqual(value.value(at: ["a", "b"]), .int(1000))
        XCTAssertEqual(value.value(at: ["pi"]), .double(3.14))
        XCTAssertEqual(value.value(at: ["day"]), .string("2026-11-04"))
        XCTAssertEqual(value.value(at: ["args", "1"]), .string("literal\\n"))
        XCTAssertEqual(value.value(at: ["env", "NESTED", "KEY"]), .bool(true))
        XCTAssertEqual(value.value(at: ["text"]), .string("two\nlines"))
        XCTAssertEqual(value.value(at: ["escaped"]), .string("tab\there é"))
        XCTAssertEqual(value.value(at: ["servers", "1", "name"]), .string("two"))
        XCTAssertEqual(value.value(at: ["servers", "1", "extra", "ok"]), .bool(true))
        XCTAssertNil(value.value(at: ["servers", "0", "extra"]))
    }

    func testTOMLReportsTheLineOfAnError() {
        XCTAssertThrowsError(try ConfigParser.parse(Data("a = 1\nb = \n".utf8), format: .toml)) { error in
            guard case ConfigParseError.invalidTOML(let line, _) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(line, 2)
        }
    }

    func testBlankValues() {
        XCTAssertTrue(ConfigValue.array([]).isBlank)
        XCTAssertTrue(ConfigValue.bool(false).isBlank)
        XCTAssertFalse(ConfigValue.bool(true).isBlank)
        XCTAssertFalse(ConfigValue.int(0).isBlank)
    }

    func testSerializationIsStable() throws {
        let first = try ConfigParser.parse(Data(#"{"b":1,"a":2}"#.utf8), format: .json)
        let second = try ConfigParser.parse(Data(#"{"a":2,"b":1}"#.utf8), format: .json)
        XCTAssertEqual(try first.serialized(), try second.serialized())
    }
}
