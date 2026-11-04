import CryptoKit
import Foundation

public enum StoreError: Error, Equatable {
    case missingVersion(String)
    case corruptVersion(String)
}

/// Warden's persistent state.
public struct WardenState: Codable, Equatable, Sendable {
    public var files: [WatchedFileRecord] = []
    public var baselines: [String: FileVersionRef] = [:]
    public var pending: [String: PendingChange] = [:]
    public var isPaused = false
    public var isOnDeviceAIEnabled = true

    public init() {}
}

/// Everything Warden keeps on disk, under one directory:
///
///     state.json       watched files, baselines, pending changes, settings
///     history.jsonl    append-only log of changes and decisions
///     versions/<sha>   content-addressed snapshots
///
/// Snapshots contain whatever the original files contain, so the directory is private to the user.
public final class WardenStore: @unchecked Sendable {
    public let root: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var stateURL: URL { root.appendingPathComponent("state.json") }
    private var historyURL: URL { root.appendingPathComponent("history.jsonl") }
    private var versionsURL: URL { root.appendingPathComponent("versions", isDirectory: true) }

    public init(root: URL) throws {
        self.root = root
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for directory in [root, versionsURL] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Versions

    /// Stores a snapshot and returns its hash. Storing the same bytes twice is free.
    @discardableResult
    public func saveVersion(_ data: Data) throws -> String {
        let sha = Self.hash(data)
        let url = versionsURL.appendingPathComponent(sha)
        if !fileManager.fileExists(atPath: url.path) {
            try AtomicFile.write(data, to: url, permissions: 0o600)
        }
        return sha
    }

    /// Loads a snapshot and verifies that it still matches its hash.
    public func loadVersion(_ sha: String) throws -> Data {
        let url = versionsURL.appendingPathComponent(sha)
        guard let data = try? Data(contentsOf: url) else { throw StoreError.missingVersion(sha) }
        guard Self.hash(data) == sha else { throw StoreError.corruptVersion(sha) }
        return data
    }

    // MARK: - State

    public func loadState() throws -> WardenState {
        guard fileManager.fileExists(atPath: stateURL.path) else { return WardenState() }
        return try decoder.decode(WardenState.self, from: Data(contentsOf: stateURL))
    }

    public func saveState(_ state: WardenState) throws {
        try AtomicFile.write(try encoder.encode(state), to: stateURL, permissions: 0o600)
    }

    // MARK: - History

    public func append(_ entry: HistoryEntry) throws {
        var line = try encoder.encode(entry)
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: historyURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try AtomicFile.write(line, to: historyURL, permissions: 0o600)
        }
    }

    /// Newest first. A damaged line is skipped rather than losing the rest of the log.
    public func loadHistory() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return data.split(separator: 0x0A)
            .compactMap { try? decoder.decode(HistoryEntry.self, from: Data($0)) }
            .reversed()
    }
}
