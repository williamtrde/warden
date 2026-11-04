import Foundation

/// Decides which changes of a file deserve an alert.
public enum WatchPolicy: Equatable, Sendable {
    /// Every byte counts. Revert restores the whole file.
    case everyChange
    /// Only these keys count: the file is rewritten for routine reasons by its owner.
    /// Revert restores these keys and leaves the rest of the file alone.
    case filtered([PathPattern])

    public var isFiltered: Bool {
        if case .filtered = self { return true }
        return false
    }

    /// Whether a key path is watched by this policy.
    public func watches(_ path: [String]) -> Bool {
        switch self {
        case .everyChange: return true
        case .filtered(let patterns): return patterns.contains { $0.matches(path) }
        }
    }

    /// Keeps the changes that matter. For filtered files, a key appearing with an empty
    /// default (`allowedTools: []`, `hasTrustDialogAccepted: false`) is not a change:
    /// agents create those for every new project.
    public func relevantChanges(in changes: [ConfigChange]) -> [ConfigChange] {
        guard isFiltered else { return changes }
        return changes.filter { change in
            guard watches(change.path) else { return false }
            let oldBlank = change.oldValue?.isBlank ?? true
            let newBlank = change.newValue?.isBlank ?? true
            return !(oldBlank && newBlank)
        }
    }

    /// The part of a document this policy watches. Used to show a diff free of noise.
    public func projection(of value: ConfigValue) -> ConfigValue {
        guard isFiltered else { return value }
        return project(value, path: []) ?? .object([:])
    }

    private func project(_ value: ConfigValue, path: [String]) -> ConfigValue? {
        if !path.isEmpty, watches(path) { return value }
        guard case .object(let members) = value else { return nil }
        var kept: [String: ConfigValue] = [:]
        for (key, member) in members {
            if let projected = project(member, path: path + [key]) { kept[key] = projected }
        }
        return kept.isEmpty ? nil : .object(kept)
    }
}
