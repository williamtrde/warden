import Foundation

/// Where Warden reads and writes.
enum AppEnvironment {
    /// Debug builds can run against a fake home directory, for the demo and for UI work.
    /// Release builds always use the real one: an environment variable must not be able
    /// to point Warden somewhere else.
    static var home: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["WARDEN_HOME"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/Warden", isDirectory: true)
    }
}
