@testable import WardenCore
import XCTest

/// The README promises what triggers an alert, so it has to match the catalog.
final class ReadmeTests: XCTestCase {
    private func section(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        let start = try XCTUnwrap(readme.range(of: "<!-- \(name):start -->"))
        let end = try XCTUnwrap(readme.range(of: "<!-- \(name):end -->"))
        return String(readme[start.upperBound..<end.lowerBound])
    }

    func testTableMatchesTheCatalog() throws {
        let rows = try section("watch-table").split(separator: "\n").filter { $0.hasPrefix("| `") }
        XCTAssertEqual(rows.count, WatchCatalog.defaultTargets.count)
        for target in WatchCatalog.defaultTargets {
            let row = try XCTUnwrap(rows.first { $0.hasPrefix("| `\(target.displayName)` |") }, target.displayName)
            XCTAssertTrue(row.contains("| \(target.agent.displayName) |"), target.path)
            XCTAssertEqual(row.contains("Security keys only"), target.policy.isFiltered, target.path)
            XCTAssertEqual(row.contains("Those keys only"), target.policy.isFiltered, target.path)
        }
    }

    func testEveryWatchedKeyIsListed() throws {
        let text = try section("watch-keys")
        for pattern in WatchCatalog.claudeStateKeys + WatchCatalog.cursorSettingsKeys {
            let key = pattern.replacingOccurrences(of: "/**", with: "")
            XCTAssertTrue(text.contains("`\(key)`"), key)
        }
        let listed = text.components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let known = Set((WatchCatalog.claudeStateKeys + WatchCatalog.cursorSettingsKeys).map { $0.replacingOccurrences(of: "/**", with: "") })
        let headings: Set<String> = ["~/.claude.json", "projects.<path>", "settings.json"]
        XCTAssertEqual(Set(listed).subtracting(known).subtracting(headings), [])
    }
}
