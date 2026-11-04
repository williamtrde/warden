import Foundation

public enum RestoreError: Error, Equatable {
    /// A filtered file cannot be repaired key by key when it no longer parses.
    case currentFileUnreadable
}

/// Computes what a file should contain after a revert.
public enum FileRestorer {
    /// - Parameters:
    ///   - reference: the version to go back to, nil if the file did not exist.
    ///   - current: the file as it is now, nil if it is gone.
    /// - Returns: the bytes to write, or nil if the file should not exist.
    public static func restoredContent(target: WatchTarget, reference: Data?, current: Data?) throws -> Data? {
        guard case .filtered = target.policy, let reference, let current else { return reference }
        return try surgicalRestore(target: target, reference: reference, current: current)
    }

    /// Puts the watched keys back to their reference values and leaves everything else as it is
    /// now: the owner of the file may have legitimately rewritten the rest in the meantime.
    private static func surgicalRestore(target: WatchTarget, reference: Data, current: Data) throws -> Data {
        guard let currentValue = try? ConfigParser.parse(current, format: target.format) else {
            if target.format == .jsonc || target.format == .json { return reference }
            throw RestoreError.currentFileUnreadable
        }
        let referenceValue = try ConfigParser.parse(reference, format: target.format)
        var result = currentValue
        for path in watchedRoots(in: currentValue, target: target) + watchedRoots(in: referenceValue, target: target) {
            result = setting(referenceValue.value(at: path), at: path, in: result)
        }
        return try result.serialized()
    }

    /// The topmost watched paths of a document.
    private static func watchedRoots(in value: ConfigValue, target: WatchTarget, path: [String] = []) -> [[String]] {
        if !path.isEmpty, target.policy.watches(path) { return [path] }
        guard case .object(let members) = value else { return [] }
        return members.flatMap { watchedRoots(in: $0.value, target: target, path: path + [$0.key]) }
    }

    /// Returns `document` with `path` set to `value`, or removed when `value` is nil.
    static func setting(_ value: ConfigValue?, at path: [String], in document: ConfigValue) -> ConfigValue {
        guard let key = path.first else { return value ?? document }
        var members: [String: ConfigValue]
        if case .object(let existing) = document { members = existing } else { members = [:] }
        if path.count == 1 {
            members[key] = value
        } else if let child = members[key] {
            members[key] = setting(value, at: Array(path.dropFirst()), in: child)
        } else if value != nil {
            members[key] = setting(value, at: Array(path.dropFirst()), in: .object([:]))
        }
        return .object(members)
    }
}
