import SwiftUI
import WardenCore

struct MainWindowView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            switch model.selection {
            case .file(let path):
                if let status = model.snapshot.files.first(where: { $0.id == path }) {
                    FileDetailView(model: model, status: status)
                        .id(path)
                } else {
                    placeholder
                }
            case .history:
                HistoryView(model: model)
            case nil:
                placeholder
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .alert("Warden could not finish this action", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Select a file", systemImage: "shield", description: Text("Choose a watched file on the left."))
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

private struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        List(selection: $model.selection) {
            let pending = model.snapshot.files.filter { $0.pending != nil }
            if !pending.isEmpty {
                Section("Needs your decision") {
                    ForEach(pending) { FileRow(status: $0).tag(SidebarItem.file($0.id)) }
                }
            }
            Section("Watched files") {
                ForEach(model.snapshot.files.filter { $0.pending == nil }) { FileRow(status: $0).tag(SidebarItem.file($0.id)) }
            }
            Section {
                Label("History", systemImage: "clock.arrow.circlepath").tag(SidebarItem.history)
            }
        }
        .listStyle(.sidebar)
    }
}

private struct FileRow: View {
    let status: FileStatus

    var body: some View {
        HStack(spacing: 8) {
            indicator.frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: status.target.displayName)
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(status.exists || status.pending != nil ? 1 : 0.55)
    }

    private var subtitle: LocalizedStringKey {
        let agent = status.record.agent == .other ? String(localized: "Other") : status.record.agent.displayName
        return status.exists ? "\(agent)" : "\(agent) · not on this Mac yet"
    }

    @ViewBuilder private var indicator: some View {
        if let change = status.pending {
            SeverityDot(severity: change.severity)
        } else if status.exists {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(Text("Matches its reference"))
        } else {
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Not found"))
        }
    }
}
