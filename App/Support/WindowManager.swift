import AppKit
import SwiftUI

/// Windows are managed through AppKit: a menu bar app has no Dock icon and no main scene,
/// and notifications must be able to bring a window up from anywhere.
@MainActor
final class WindowManager {
    private var main: NSWindow?
    private var settings: NSWindow?

    func showMain(model: AppModel) {
        let window = main ?? makeWindow(
            title: "Warden",
            size: NSSize(width: 980, height: 640),
            content: MainWindowView(model: model)
        )
        window.setFrameAutosaveName("WardenMain")
        main = window
        present(window)
    }

    func showSettings(model: AppModel) {
        let title = String(localized: "Warden Settings")
        let window = settings ?? makeWindow(title: title, size: NSSize(width: 520, height: 520), content: SettingsView(model: model))
        settings = window
        present(window)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
