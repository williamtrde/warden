import Foundation

/// Writes that are all-or-nothing, so a crash can never leave half a config file.
public enum AtomicFile {
    /// Writes through a temporary sibling and a rename. Symlinks are followed, so a dotfile
    /// managed from another folder keeps its link. Existing permissions are preserved.
    public static func write(_ data: Data, to url: URL, permissions: Int? = nil) throws {
        let manager = FileManager.default
        let destination = url.resolvingSymlinksInPath()
        let existing = (try? manager.attributesOfItem(atPath: destination.path))?[.posixPermissions] as? Int
        let mode = permissions ?? existing ?? 0o644

        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).warden-\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: mode]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if rename(temporary.path, destination.path) != 0 {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }
}
