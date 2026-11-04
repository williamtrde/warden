import SwiftUI
import WardenCore

/// Everything that happened, newest first, with the ability to go back to any version.
struct HistoryView: View {
    let model: AppModel
    @State private var selectedID: HistoryEntry.ID?

    private var selected: HistoryEntry? {
        model.snapshot.history.first { $0.id == selectedID }
    }

    var body: some View {
        HSplitView {
            List(model.snapshot.history, selection: $selectedID) { entry in
                HistoryRow(entry: entry).tag(entry.id)
            }
            .frame(minWidth: 300, idealWidth: 340)
            Group {
                if let selected {
                    HistoryDetail(model: model, entry: selected).id(selected.id)
                } else {
                    ContentUnavailableView("Select an event", systemImage: "clock", description: Text("Pick a line to see that version."))
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension HistoryEntry.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .baselineCreated: return "Reference created"
        case .changeDetected: return "Change detected"
        case .accepted: return "Accepted"
        case .reverted: return "Reverted"
        case .restored: return "Version restored"
        case .resolvedExternally: return "Back to reference"
        }
    }

    var symbol: String {
        switch self {
        case .baselineCreated: return "camera"
        case .changeDetected: return "exclamationmark.triangle"
        case .accepted: return "checkmark.circle"
        case .reverted: return "arrow.uturn.backward.circle"
        case .restored: return "clock.arrow.circlepath"
        case .resolvedExternally: return "equal.circle"
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(entry.severity?.color ?? .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.kind.title).font(.callout.weight(.medium))
                    if let severity = entry.severity {
                        Text(severity.title).font(.caption2).foregroundStyle(severity.color)
                    }
                }
                Text(verbatim: entry.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(entry.date, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryDetail: View {
    let model: AppModel
    let entry: HistoryEntry
    @State private var diff: LineDiff?
    @State private var isConfirming = false

    /// The version a user would want back: what this event produced, or what it saved.
    private var restorableSHA: String? { entry.versionSHA ?? entry.backupSHA }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.kind.title).font(.title3.weight(.semibold))
                Text(verbatim: entry.path.hasPrefix("/") ? entry.path : "~/\(entry.path)").font(.callout).foregroundStyle(.secondary)
                if let summary = entry.summary {
                    Text(verbatim: summary).textSelection(.enabled)
                }
                if let sha = restorableSHA {
                    Button("Restore This Version") { isConfirming = true }
                        .confirmationDialog("Restore this version?", isPresented: $isConfirming) {
                            Button("Restore") { model.restore(path: entry.path, sha: sha) }
                        } message: {
                            Text("It becomes the new reference. The current file is backed up first.")
                        }
                }
                if let diff, !diff.isEmpty {
                    Text("Difference with the current reference").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DiffView(diff: diff)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            let status = model.snapshot.files.first { $0.id == entry.path }
            let reference = status?.pending?.beforeSHA ?? currentReference
            diff = await model.diff(path: entry.path, fromSHA: reference, toSHA: restorableSHA)
        }
    }

    /// The latest version in the history of this file.
    private var currentReference: String? {
        model.snapshot.history.first { $0.path == entry.path && [.accepted, .baselineCreated, .restored].contains($0.kind) }?.versionSHA
    }
}
