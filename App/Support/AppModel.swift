import Foundation
import Observation
import ServiceManagement
import SwiftUI
import WardenCore

/// What the main window is showing.
enum SidebarItem: Hashable {
    case file(String)
    case history
}

/// Bridges the engine actor to SwiftUI.
@MainActor
@Observable
final class AppModel {
    private(set) var snapshot = EngineSnapshot()
    private(set) var isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    private(set) var isOnDeviceAIAvailable = OnDeviceModel.makeClient() != nil
    var selection: SidebarItem?
    var errorMessage: String?

    private var engine: WardenEngine?
    private let notifications = NotificationManager()
    private let windows = WindowManager()

    var statusTitle: LocalizedStringKey {
        if snapshot.isPaused { return "Monitoring paused" }
        switch snapshot.shield {
        case .secure: return "All files match their reference"
        case .pending: return "A change is waiting for your decision"
        case .critical: return "A critical change is waiting"
        }
    }

    func start() {
        do {
            let home = AppEnvironment.home
            let store = try WardenStore(root: AppEnvironment.supportDirectory)
            let engine = try WardenEngine(configuration: .init(
                home: home,
                store: store,
                watcher: FSEventsWatcher(),
                usage: UsageContextBuilder(reader: LocalMetadataReader(home: home), home: home),
                onDeviceGenerator: { OnDeviceModel.makeClient().map(OnDeviceExplanationGenerator.init(client:)) }
            ))
            self.engine = engine
            notifications.configure { [weak self] action, path in self?.handleNotification(action, path: path) }
            observe(engine)
            Task { await engine.start() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func observe(_ engine: WardenEngine) {
        Task { [weak self] in
            for await snapshot in engine.snapshots { self?.snapshot = snapshot }
        }
        Task { [weak self] in
            for await change in engine.alerts {
                self?.notifications.post(change)
                self?.snapshot = await engine.currentSnapshot()
                #if DEBUG
                // Keeps the demo on screen: see scripts/demo.sh.
                if ProcessInfo.processInfo.environment["WARDEN_OPEN_WINDOW"] != nil {
                    self?.openWindow(selecting: .file(change.path))
                }
                #endif
            }
        }
    }

    private func handleNotification(_ action: NotificationManager.Action, path: String) {
        switch action {
        case .accept: accept(path: path)
        case .revert: revert(path: path)
        case .open: openWindow(selecting: .file(path))
        }
    }

    // MARK: - Windows

    func openWindow(selecting item: SidebarItem? = nil) {
        if let item {
            selection = item
        } else if selection == nil {
            selection = snapshot.pending.first.map { .file($0.path) } ?? snapshot.files.first.map { .file($0.id) }
        }
        windows.showMain(model: self)
    }

    func openSettings() {
        windows.showSettings(model: self)
    }

    // MARK: - Decisions

    func accept(path: String) {
        perform { try await $0.accept(path: path) }
    }

    func revert(path: String) {
        perform { try await $0.revert(path: path) }
    }

    func restore(path: String, sha: String) {
        perform { try await $0.restore(path: path, sha: sha) }
    }

    private func perform(_ action: @escaping @Sendable (WardenEngine) async throws -> Void) {
        guard let engine else { return }
        Task {
            do {
                try await action(engine)
            } catch {
                errorMessage = error.localizedDescription
            }
            snapshot = await engine.currentSnapshot()
        }
    }

    func diff(for change: PendingChange) async -> LineDiff? {
        await engine?.diff(for: change)
    }

    func diff(path: String, fromSHA: String?, toSHA: String?) async -> LineDiff? {
        await engine?.diff(path: path, fromSHA: fromSHA, toSHA: toSHA)
    }

    // MARK: - Settings

    func setPaused(_ paused: Bool) {
        perform { await $0.setPaused(paused) }
    }

    func setOnDeviceAIEnabled(_ enabled: Bool) {
        perform { await $0.setOnDeviceAIEnabled(enabled) }
    }

    func addFile(url: URL) {
        perform { await $0.addFile(url: url) }
    }

    func removeFile(path: String) {
        perform { await $0.removeFile(path: path) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}
