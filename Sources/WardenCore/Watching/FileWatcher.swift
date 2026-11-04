import CoreServices
import Foundation

/// Reports that some watched paths may have changed.
public protocol FileWatching: AnyObject, Sendable {
    func start(paths: [String], onChange: @escaping @Sendable ([String]) -> Void)
    func stop()
}

/// FSEvents, at file granularity.
///
/// Each file's parent directory is what gets watched: agents save with an atomic rename, which
/// replaces the watched inode, and a file that does not exist yet can still appear there.
/// Folders that do not exist are covered by the engine's periodic scan.
public final class FSEventsWatcher: FileWatching, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.warden.fsevents")
    private var stream: FSEventStreamRef?
    private var handler: (@Sendable ([String]) -> Void)?
    private var watched = Set<String>()
    private let latency: CFTimeInterval

    public init(latency: CFTimeInterval = 0.25) {
        self.latency = latency
    }

    deinit { stop() }

    public func start(paths: [String], onChange: @escaping @Sendable ([String]) -> Void) {
        stop()
        queue.sync {
            handler = onChange
            watched = Set(paths.map(Self.normalized))
            let roots = Self.roots(for: paths)
            guard !roots.isEmpty else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer
            guard let created = FSEventStreamCreate(
                nil,
                Self.callback,
                &context,
                roots as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(flags)
            ) else { return }
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
            stream = created
        }
    }

    public func stop() {
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    /// Existing file paths themselves plus their parents, minus anything already covered.
    /// The home directory is never watched recursively: `~/.claude.json` is watched by path.
    static func roots(for paths: [String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var roots = Set<String>()
        for path in paths {
            let parent = (path as NSString).deletingLastPathComponent
            if parent == home {
                roots.insert(path)
            } else if FileManager.default.fileExists(atPath: parent) {
                roots.insert(parent)
            }
        }
        return roots.sorted()
    }

    private static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
        let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        let changed = (0..<count).compactMap { array[$0] as? String }.map(normalized)
        let relevant = changed.filter { watcher.watched.contains($0) }
        if !relevant.isEmpty { watcher.handler?(Array(Set(relevant))) }
    }
}
