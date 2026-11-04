import Foundation

/// A file the user chose to watch, as persisted.
public struct WatchedFileRecord: Codable, Equatable, Sendable, Identifiable {
    public let path: String
    public let agent: Agent
    public let format: FileFormat
    /// True for files from `WatchCatalog`, whose policy comes from the catalog.
    public let isBuiltIn: Bool

    public var id: String { path }

    public init(path: String, agent: Agent, format: FileFormat, isBuiltIn: Bool) {
        self.path = path
        self.agent = agent
        self.format = format
        self.isBuiltIn = isBuiltIn
    }

    public init(target: WatchTarget, isBuiltIn: Bool) {
        self.init(path: target.path, agent: target.agent, format: target.format, isBuiltIn: isBuiltIn)
    }

    /// Rebuilds the full target, taking the policy from the catalog so that a stored
    /// file can never weaken what the catalog decides.
    public var target: WatchTarget {
        WatchCatalog.defaultTargets.first { $0.path == path }
            ?? WatchTarget(path: path, agent: agent, format: format, policy: .everyChange)
    }
}

/// A stored version of a file. A nil hash means "the file did not exist".
public struct FileVersionRef: Codable, Equatable, Sendable {
    public let sha256: String?
    public let date: Date

    public init(sha256: String?, date: Date) {
        self.sha256 = sha256
        self.date = date
    }
}

/// A change waiting for the user's decision.
public struct PendingChange: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let path: String
    public let detectedAt: Date
    public let beforeSHA: String?
    public let afterSHA: String?
    public let severity: Severity
    public let findings: [RiskFinding]
    public let explanation: Explanation

    public init(
        id: UUID = UUID(),
        path: String,
        detectedAt: Date,
        beforeSHA: String?,
        afterSHA: String?,
        severity: Severity,
        findings: [RiskFinding],
        explanation: Explanation
    ) {
        self.id = id
        self.path = path
        self.detectedAt = detectedAt
        self.beforeSHA = beforeSHA
        self.afterSHA = afterSHA
        self.severity = severity
        self.findings = findings
        self.explanation = explanation
    }
}

/// One line of the chronological history.
public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// First snapshot of a file.
        case baselineCreated
        case changeDetected
        case accepted
        case reverted
        case restored
        /// The file went back to its reference by itself.
        case resolvedExternally
    }

    public let id: UUID
    public let date: Date
    public let path: String
    public let kind: Kind
    public let severity: Severity?
    /// The version this entry produced or looked at.
    public let versionSHA: String?
    /// The copy saved before Warden overwrote the file.
    public let backupSHA: String?
    public let summary: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        path: String,
        kind: Kind,
        severity: Severity? = nil,
        versionSHA: String? = nil,
        backupSHA: String? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.date = date
        self.path = path
        self.kind = kind
        self.severity = severity
        self.versionSHA = versionSHA
        self.backupSHA = backupSHA
        self.summary = summary
    }
}
