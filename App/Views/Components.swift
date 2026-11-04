import AppKit
import SwiftUI
import WardenCore

extension Severity {
    var color: Color { self == .critical ? .red : .orange }
    var title: LocalizedStringKey { self == .critical ? "Critical" : "Info" }
}

/// The shape differs by severity, so that color is never the only signal.
struct SeverityDot: View {
    let severity: Severity

    var body: some View {
        Image(systemName: severity == .critical ? "xmark.octagon.fill" : "exclamationmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(severity.color)
            .accessibilityLabel(Text(severity.title))
    }
}

struct SeverityBadge: View {
    let severity: Severity

    var body: some View {
        Text(severity.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(severity.color)
            .background(severity.color.opacity(0.14), in: Capsule())
    }
}

/// What the shield shows. Each state has its own glyph, so color is never the only signal.
enum ShieldAppearance {
    case paused, secure, pending, critical, failed

    var symbol: String {
        switch self {
        case .paused: return "shield.slash.fill"
        case .secure: return "checkmark.shield.fill"
        case .pending: return "exclamationmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: NSColor {
        switch self {
        case .paused: return .systemGray
        case .secure: return .systemGreen
        case .pending: return .systemOrange
        case .critical, .failed: return .systemRed
        }
    }
}

struct ShieldBadge: View {
    let appearance: ShieldAppearance
    let size: CGFloat

    var body: some View {
        Image(systemName: appearance.symbol)
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(nsColor: appearance.color))
            .accessibilityHidden(true)
    }
}
