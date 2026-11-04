import AppKit
import SwiftUI
import WardenCore

@main
struct WardenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: delegate.model)
        } label: {
            ShieldIcon(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the long-lived objects: SwiftUI scenes are rebuilt, these must not be.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// The icon in the menu bar. Each state has its own glyph, so color is never the only signal.
private struct ShieldIcon: View {
    let model: AppModel

    var body: some View {
        Image(nsImage: Self.image(for: model.snapshot.shield, isPaused: model.snapshot.isPaused))
            .accessibilityLabel(Text(model.statusTitle))
    }

    private static func image(for shield: ShieldState, isPaused: Bool) -> NSImage {
        let symbol: String
        let color: NSColor
        switch (isPaused, shield) {
        case (true, _): (symbol, color) = ("shield.slash.fill", .systemGray)
        case (false, .secure): (symbol, color) = ("checkmark.shield.fill", .systemGreen)
        case (false, .pending): (symbol, color) = ("exclamationmark.shield.fill", .systemOrange)
        case (false, .critical): (symbol, color) = ("xmark.shield.fill", .systemRed)
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(.init(paletteColors: [.white, color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Warden")?
            .withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
