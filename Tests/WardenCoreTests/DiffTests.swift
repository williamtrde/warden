@testable import WardenCore
import XCTest

final class LineDiffTests: XCTestCase {
    func testIdenticalTextsHaveNoHunks() {
        XCTAssertTrue(LineDiff.compute(old: "a\nb\n", new: "a\nb\n").isEmpty)
    }

    func testAddedAndRemovedLinesCarryNumbers() {
        let diff = LineDiff.compute(old: "a\nb\nc\n", new: "a\nB\nc\nd\n")
        XCTAssertEqual(diff.removedLines.map(\.text), ["b"])
        XCTAssertEqual(diff.removedLines.first?.oldNumber, 2)
        XCTAssertEqual(diff.addedLines.map(\.text), ["B", "d"])
        XCTAssertEqual(diff.addedLines.last?.newNumber, 4)
    }

    func testDistantChangesFormSeparateHunks() {
        let old = (1...30).map(String.init).joined(separator: "\n")
        let new = old.replacingOccurrences(of: "\n2\n", with: "\ntwo\n").replacingOccurrences(of: "\n29\n", with: "\nnine\n")
        let diff = LineDiff.compute(old: old, new: new, context: 2)
        XCTAssertEqual(diff.hunks.count, 2)
        XCTAssertEqual(diff.hunks[0].lines.filter { $0.kind == .context }.count, 3) // Line 1 + two after.
    }

    func testFromEmptyAndToEmpty() {
        XCTAssertEqual(LineDiff.compute(old: "", new: "x\n").addedLines.count, 1)
        XCTAssertEqual(LineDiff.compute(old: "x\n", new: "").removedLines.count, 1)
    }

    func testCRLFIsNotAChange() {
        XCTAssertTrue(LineDiff.compute(old: "a\r\nb\r\n", new: "a\nb\n").isEmpty)
    }

    func testUnifiedText() {
        XCTAssertEqual(LineDiff.compute(old: "a\n", new: "b\n").unifiedText, "- a\n+ b")
    }
}

final class StructuralDiffTests: XCTestCase {
    private func json(_ text: String) throws -> ConfigValue {
        try ConfigParser.parse(Data(text.utf8), format: .json)
    }

    func testModifiedLeaf() throws {
        let changes = StructuralDiff.compute(old: try json(#"{"a":{"b":1}}"#), new: try json(#"{"a":{"b":2}}"#))
        XCTAssertEqual(changes, [.init(kind: .modified, path: ["a", "b"], oldValue: .int(1), newValue: .int(2))])
    }

    func testNewSubtreeExpandsToLeaves() throws {
        let changes = StructuralDiff.compute(
            old: try json("{}"),
            new: try json(#"{"mcpServers":{"evil":{"url":"http://x","args":["a"]}}}"#)
        )
        XCTAssertEqual(changes.map(\.dottedPath), ["mcpServers.evil.args.[]", "mcpServers.evil.url"])
        XCTAssertTrue(changes.allSatisfy { $0.kind == .added })
    }

    func testRemovedSubtree() throws {
        let changes = StructuralDiff.compute(old: try json(#"{"a":{"b":1}}"#), new: try json("{}"))
        XCTAssertEqual(changes.first?.kind, .removed)
        XCTAssertEqual(changes.first?.oldValue, .int(1))
    }

    func testScalarArraysCompareAsSets() throws {
        let changes = StructuralDiff.compute(
            old: try json(#"{"allow":["Read","Edit"]}"#),
            new: try json(#"{"allow":["Read","Bash(*)"]}"#)
        )
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.contains { $0.kind == .added && $0.newValue == .string("Bash(*)") })
        XCTAssertTrue(changes.contains { $0.kind == .removed && $0.oldValue == .string("Edit") })
    }

    func testReorderedScalarArrayStillCounts() throws {
        let changes = StructuralDiff.compute(old: try json(#"{"args":["a","b"]}"#), new: try json(#"{"args":["b","a"]}"#))
        XCTAssertEqual(changes.map(\.kind), [.modified])
    }

    func testObjectArraysCompareByIndex() throws {
        let changes = StructuralDiff.compute(
            old: try json(#"{"h":[{"c":"a"}]}"#),
            new: try json(#"{"h":[{"c":"a"},{"c":"b"}]}"#)
        )
        XCTAssertEqual(changes.map(\.dottedPath), ["h.1.c"])
    }

    func testScalarChangeOfTypeIsAModification() throws {
        let changes = StructuralDiff.compute(old: try json(#"{"a":1}"#), new: try json(#"{"a":"1"}"#))
        XCTAssertEqual(changes.map(\.kind), [.modified])
    }

    func testTypeChangeExpandsToLeaves() throws {
        let changes = StructuralDiff.compute(old: try json(#"{"mcpServers":null}"#), new: try json(#"{"mcpServers":{"e":{"command":"sh"}}}"#))
        XCTAssertTrue(changes.contains { $0.kind == .added && $0.path == ["mcpServers", "e", "command"] })
    }

    func testLookalikeStringIsAChange() throws {
        let changes = StructuralDiff.compute(old: .string("/opt/Kit/run"), new: .string("/opt/\u{212A}it/run"))
        XCTAssertEqual(changes.count, 1)
        XCTAssertFalse(LineDiff.compute(old: "caf\u{E9}", new: "cafe\u{301}").isEmpty)
    }

    func testMissingDocumentMeansEverythingIsNew() throws {
        let changes = StructuralDiff.compute(old: nil, new: try json(#"{"a":1}"#))
        XCTAssertEqual(changes.map(\.kind), [.added])
    }
}
