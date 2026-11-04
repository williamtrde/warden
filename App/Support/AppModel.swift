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
    private(set) var launchAtLoginStatus = SMAppService.mainApp.status
    private(set) var areNotificationsDenied = false
    /// Set when Warden could not start. Nothing is being watched, and the interface must say so.
    private(set) var startupError: String?
    private(set) var isOnDeviceAIAvailable = OnDeviceModel.makeClient() != nil
    var selection: SidebarItem?
    var errorMessage: String?

    private var engine: WardenEngine?
    private let notifications = NotificationManager()
    private let windows = WindowManager()

    var isLaunchAtLoginEnabled: Bool { launchAtLoginStatus == .enabled || launchAtLoginStatus == .requiresApproval }

    /// A pause never hides a change that is still waiting.
    var appearance: ShieldAppearance {
        if startupError != nil { return .failed }
        switch snapshot.shield {
        case .secure: return snapshot.isPaused ? .paused : .secure
        case .pending: return .pending
        case .critical: return .critical
        }
    }

    var statusTitle: LocalizedStringKey {
        switch appearance {
        case .failed: return "Warden is not monitoring your files"
        case .paused: return "Monitoring paused"
        case .secure: return "All files match their reference"
        case .pending:
            return snapshot.pending.isEmpty ? "Warden's records were damaged and rebuilt" : "A change is waiting for your decision"
        case .critical: return "A critical change is waiting"
        }
    }

    func start() {
        notifications.configure { [weak self] action, path, fingerprint in
            self?.handleNotification(action, path: path, fingerprint: fingerprint)
        }
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
            observe(engine)
            Task { [weak self] in
                await engine.start()
                if await engine.currentSnapshot().stateResetAt != nil {
                    self?.notifications.postNotice(
                        title: String(localized: "Warden's records were damaged and rebuilt"),
                        body: String(localized: "Check your watched files. Files you added yourself must be added again.")
                    )
                }
            }
        } catch {
            startupError = Self.message(for: error)
            notifications.postNotice(title: String(localized: "Warden is not monitoring your files"), body: startupError ?? "")
            windows.showMain(model: self)
        }
    }

    private func observe(_ engine: WardenEngine) {
        Task { [weak self] in
            for await snapshot in engine.snapshots { self?.apply(snapshot) }
        }
        Task { [weak self] in
            for await change in engine.alerts {
                self?.notifications.post(change)
                await self?.apply(engine.currentSnapshot())
                #if DEBUG
                // Keeps the demo on screen: see scripts/demo.sh.
                if ProcessInfo.processInfo.environment["WARDEN_OPEN_WINDOW"] != nil {
                    self?.openWindow(selecting: .file(change.path))
                }
                #endif
            }
        }
    }

    /// A banner must not outlive the change it offers to decide.
    private func apply(_ new: EngineSnapshot) {
        let resolved = Set(snapshot.pending.map(\.path)).subtracting(new.pending.map(\.path))
        notifications.remove(paths: Array(resolved))
        snapshot = new
    }

    private func handleNotification(_ action: NotificationManager.Action, path: String, fingerprint: String?) {
        switch action {
        case .accept: accept(path: path, fingerprint: fingerprint)
        case .revert: revert(path: path, fingerprint: fingerprint)
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
        Task { await refreshSystemStatus() }
        windows.showSettings(model: self)
    }

    /// Both can change in System Settings while Warden is running.
    private func refreshSystemStatus() async {
        launchAtLoginStatus = SMAppService.mainApp.status
        areNotificationsDenied = await notifications.isDenied()
    }

    // MARK: - Decisions

    /// Decisions name the version the user saw. If it is gone, Warden shows what is there now
    /// instead of deciding about something the user never read.
    func accept(path: String, fingerprint: String?) {
        decide(path: path) { try await $0.accept(path: path, fingerprint: fingerprint) }
    }

    func revert(path: String, fingerprint: String?) {
        decide(path: path) { try await $0.revert(path: path, fingerprint: fingerprint) }
    }

    private func decide(path: String, _ action: @escaping @Sendable (WardenEngine) async throws -> Void) {
        perform { engine in
            do {
                try await action(engine)
            } catch EngineError.changeSuperseded, EngineError.noPendingChange {
                await MainActor.run { self.openWindow(selecting: .file(path)) }
            }
        }
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
                present(error)
            }
            await apply(engine.currentSnapshot())
        }
    }

    /// Errors live in the main window: it is opened, because a decision made from a
    /// notification or from Settings has nowhere else to fail visibly.
    private func present(_ error: Error) {
        errorMessage = Self.message(for: error)
        windows.showMain(model: self)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case EngineError.unknownFile:
            return String(localized: "This file is no longer watched.")
        case EngineError.noPendingChange, EngineError.changeSuperseded:
            return String(localized: "This change is no longer waiting for a decision.")
        case is StoreError:
            return String(localized: "Warden's stored copy of this version is missing or damaged. The file was left untouched.")
        default:
            return error.localizedDescription
        }
    }

    func diff(for change: PendingChange) async -> LineDiff? {
        await engine?.diff(for: change)
    }

    func diff(path: String, fromSHA: String?, toSHA: String?) async -> LineDiff? {
        await engine?.diff(path: path, fromSHA: fromSHA, toSHA: toSHA)
    }

    // MARK: - Settings

    func acknowledgeStateReset() {
        perform { await $0.acknowledgeStateReset() }
    }

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
            present(error)
        }
        launchAtLoginStatus = SMAppService.mainApp.status
    }
}
