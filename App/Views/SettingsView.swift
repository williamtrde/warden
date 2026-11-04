import AppKit
import SwiftUI
import WardenCore

struct SettingsView: View {
    let model: AppModel
    @State private var selectedPath: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(get: { model.isLaunchAtLoginEnabled }, set: model.setLaunchAtLogin))
                Toggle("Pause monitoring", isOn: Binding(get: { model.snapshot.isPaused }, set: model.setPaused))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if model.launchAtLoginStatus == .requiresApproval {
                        Text("Approve Warden in System Settings, under Login Items.")
                    }
                    if model.areNotificationsDenied {
                        Text("Notifications are off for Warden. Turn them on in System Settings to get alerts.")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Use on-device AI for explanations", isOn: Binding(
                    get: { model.snapshot.isOnDeviceAIEnabled && model.isOnDeviceAIAvailable },
                    set: model.setOnDeviceAIEnabled
                ))
                .disabled(!model.isOnDeviceAIAvailable)
            } footer: {
                Text(model.isOnDeviceAIAvailable
                     ? "Runs on this Mac. Turn it off to use built-in rules only."
                     : "Apple Intelligence is not available on this Mac. Warden uses its built-in rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Watched files") {
                List(model.snapshot.files, selection: $selectedPath) { status in
                    Text(verbatim: status.target.displayName).lineLimit(1).truncationMode(.head).tag(status.id)
                }
                .frame(minHeight: 170)
                HStack {
                    Button("Add File…", action: addFile)
                    Button("Remove") {
                        if let selectedPath { model.removeFile(path: selectedPath) }
                        selectedPath = nil
                    }
                    .disabled(selectedPath == nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 480)
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.directoryURL = AppEnvironment.home
        if panel.runModal() == .OK, let url = panel.url { model.addFile(url: url) }
    }
}
