@testable import WardenCore
import XCTest

final class FileWatcherTests: XCTestCase {
    private func expectEvent(for file: URL, watcher: FSEventsWatcher, during action: () throws -> Void) throws {
        let expectation = expectation(description: "change on \(file.lastPathComponent)")
        expectation.assertForOverFulfill = false
        watcher.start(paths: [file.path]) { paths in
            if paths.contains(where: { $0.hasSuffix(file.lastPathComponent) }) { expectation.fulfill() }
        }
        Thread.sleep(forTimeInterval: 0.3)
        try action()
        wait(for: [expectation], timeout: 5)
        watcher.stop()
    }

    func testDetectsAnInPlaceWrite() throws {
        let home = try TemporaryHome()
        let file = try home.write("{}", to: "agent/settings.json")
        try expectEvent(for: file, watcher: FSEventsWatcher(latency: 0.05)) {
            try Data("{\"a\":1}".utf8).write(to: file)
        }
    }

    func testDetectsAnAtomicRename() throws {
        let home = try TemporaryHome()
        let file = try home.write("{}", to: "agent/settings.json")
        try expectEvent(for: file, watcher: FSEventsWatcher(latency: 0.05)) {
            let temporary = try home.write("{\"a\":1}", to: "agent/settings.json.tmp")
            _ = rename(temporary.path, file.path)
        }
    }

    func testDetectsAFileCreatedAfterStart() throws {
        let home = try TemporaryHome()
        try home.write("x", to: "agent/other")
        let file = home.url.appendingPathComponent("agent/config.toml")
        try expectEvent(for: file, watcher: FSEventsWatcher(latency: 0.05)) {
            try home.write("a = 1", to: "agent/config.toml")
        }
    }

    func testIgnoresSiblingFiles() throws {
        let home = try TemporaryHome()
        let file = try home.write("{}", to: "agent/settings.json")
        let watcher = FSEventsWatcher(latency: 0.05)
        let expectation = expectation(description: "no event")
        expectation.isInverted = true
        watcher.start(paths: [file.path]) { paths in
            // The creation of `settings.json` itself may be replayed; a sibling must never appear.
            if paths.contains(where: { !$0.hasSuffix("settings.json") }) { expectation.fulfill() }
        }
        Thread.sleep(forTimeInterval: 0.3)
        try home.write("noise", to: "agent/session.jsonl")
        wait(for: [expectation], timeout: 1)
        watcher.stop()
    }

    /// `~/.claude.json` sits directly in the home folder, which must not be watched recursively,
    /// so that file is watched by its exact path, which FSEvents keeps tracking across renames.
    func testFileDirectlyInHomeIsWatchedByPath() throws {
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(realHome)/.claude.json"
        XCTAssertEqual(FSEventsWatcher.roots(for: [path]), [path])
    }
}
