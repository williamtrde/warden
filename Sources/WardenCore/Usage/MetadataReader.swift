import Foundation

/// The only door between usage analysis and the disk.
///
/// The interface makes the privacy rule structural: it can list folders, read dates, and
/// read a short allowlist of configuration files. It has no way to read a session.
public protocol MetadataReader: Sendable {
    func children(of directory: URL) -> [URL]
    func modificationDate(of url: URL) -> Date?
    /// Returns the bytes of an allowlisted metadata file, or nil for anything else.
    func readMetadataFile(_ url: URL) -> Data?
}

/// `MetadataReader` backed by the file system.
public struct LocalMetadataReader: MetadataReader {
    private let home: URL

    public init(home: URL) {
        self.home = home
    }

    public func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    public func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public func readMetadataFile(_ url: URL) -> Data? {
        guard isAllowlisted(url) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// `workspace.json` holds a single folder URI; the two others list known project paths.
    /// Symlinks are resolved first, so a link cannot smuggle a session file past this check.
    func isAllowlisted(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        let root = home.resolvingSymlinksInPath()
        if resolved == root.appendingPathComponent(UsagePaths.claudeState)
            || resolved == root.appendingPathComponent(UsagePaths.codexConfig) {
            return true
        }
        let workspaces = root.appendingPathComponent(UsagePaths.cursorWorkspaces)
        return resolved.lastPathComponent == "workspace.json"
            && resolved.deletingLastPathComponent().deletingLastPathComponent() == workspaces
    }
}

enum UsagePaths {
    static let claudeState = ".claude.json"
    static let claudeProjects = ".claude/projects"
    static let codexConfig = ".codex/config.toml"
    static let codexSessions = ".codex/sessions"
    static let cursorWorkspaces = "Library/Application Support/Cursor/User/workspaceStorage"
}
