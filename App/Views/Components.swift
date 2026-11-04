import SwiftUI
import WardenCore

extension Severity {
    var color: Color { self == .critical ? .red : .orange }
    var title: LocalizedStringKey { self == .critical ? "Critical" : "Info" }
}

struct SeverityDot: View {
    let severity: Severity

    var body: some View {
        Circle()
            .fill(severity.color)
            .frame(width: 8, height: 8)
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

struct ShieldBadge: View {
    let state: ShieldState
    let isPaused: Bool
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, color)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if isPaused { return "shield.slash.fill" }
        switch state {
        case .secure: return "checkmark.shield.fill"
        case .pending: return "exclamationmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        }
    }

    private var color: Color {
        if isPaused { return .gray }
        switch state {
        case .secure: return .green
        case .pending: return .orange
        case .critical: return .red
        }
    }
}
