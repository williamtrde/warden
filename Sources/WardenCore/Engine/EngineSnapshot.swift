import Foundation

/// The shield in the menu bar.
public enum ShieldState: String, Sendable {
    case secure
    case pending
    case critical
}

/// One row of the watched files list.
public struct FileStatus: Equatable, Sendable, Identifiable {
    public let record: WatchedFileRecord
    public let exists: Bool
    public let baselineDate: Date?
    public let pending: PendingChange?

    public var id: String { record.id }
    public var target: WatchTarget { record.target }
}

/// An immutable view of the engine for the interface.
public struct EngineSnapshot: Equatable, Sendable {
    public var files: [FileStatus] = []
    public var history: [HistoryEntry] = []
    public var isPaused = false
    public var isOnDeviceAIEnabled = true

    public init() {}

    public var pending: [PendingChange] {
        files.compactMap(\.pending).sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.detectedAt > $1.detectedAt
        }
    }

    public var shield: ShieldState {
        let changes = pending
        if changes.contains(where: { $0.severity == .critical }) { return .critical }
        return changes.isEmpty ? .secure : .pending
    }
}
