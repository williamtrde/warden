import SwiftUI
import WardenCore

/// The popover under the shield.
struct MenuBarView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            status
            Divider()
            footer
        }
        .frame(width: 340)
    }

    @ViewBuilder private var status: some View {
        if let error = model.startupError {
            Text(verbatim: error)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        } else {
            if model.snapshot.stateResetAt != nil {
                resetNotice
                Divider()
            }
            if model.snapshot.pending.isEmpty, model.snapshot.isPaused {
                Text("Changes will be checked when you resume.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else if model.snapshot.pending.isEmpty {
                Text("Warden is watching \(watchedCount) files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.snapshot.pending) { change in
                            PendingRow(change: change) { model.openWindow(selecting: .file(change.path)) }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var resetNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Warden rebuilt its references from its history. Review any change it reports.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("I Understand") { model.acknowledgeStateReset() }
        }
        .padding(14)
    }

    private var watchedCount: Int {
        model.snapshot.files.filter(\.exists).count
    }

    private var header: some View {
        HStack(spacing: 10) {
            ShieldBadge(appearance: model.appearance, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Warden").font(.headline)
                Text(model.statusTitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Open Warden") { model.openWindow() }
            MenuRow(title: model.snapshot.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
                model.setPaused(!model.snapshot.isPaused)
            }
            .disabled(model.startupError != nil)
            MenuRow(title: "Settings…") { model.openSettings() }
            MenuRow(title: "Quit Warden") { NSApp.terminate(nil) }
        }
        .padding(6)
    }
}

private struct PendingRow: View {
    let change: PendingChange
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                SeverityDot(severity: change.severity).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: (change.path as NSString).lastPathComponent).font(.callout.weight(.medium))
                    Text(verbatim: change.explanation.firstSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MenuRow: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(isHovered ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
