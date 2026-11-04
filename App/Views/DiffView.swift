import SwiftUI
import WardenCore

/// A readable, colored diff. Highlighted lines also get a glyph, so color is not the only signal.
struct DiffView: View {
    let diff: LineDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                if index > 0 {
                    Text(verbatim: "⋯")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                        .padding(.leading, 78)
                }
                ForEach(hunk.lines) { DiffLineRow(line: $0) }
            }
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            marker
            Text(verbatim: number).frame(width: 40, alignment: .trailing).foregroundStyle(.tertiary)
            Text(verbatim: sign).frame(width: 20).foregroundStyle(signColor)
            Text(verbatim: line.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(.callout, design: .monospaced))
        .fontWeight(line.emphasis == .critical ? .semibold : .regular)
        .padding(.vertical, 1)
        .background(background)
        .accessibilityElement(children: .combine)
    }

    private var marker: some View {
        HStack(spacing: 0) {
            Rectangle().fill(markerColor).frame(width: 4)
            Text(verbatim: markerGlyph)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .frame(width: 14)
        }
    }

    private var markerGlyph: String {
        switch line.emphasis {
        case .critical: return "!!"
        case .notable: return "!"
        case .none: return ""
        }
    }

    private var number: String {
        (line.newNumber ?? line.oldNumber).map(String.init) ?? ""
    }

    private var sign: String {
        switch line.kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private var signColor: Color {
        switch line.kind {
        case .added: return .green
        case .removed: return .red
        case .context: return .secondary
        }
    }

    private var markerColor: Color {
        switch line.emphasis {
        case .critical: return .red
        case .notable: return .yellow
        case .none: return .clear
        }
    }

    private var background: Color {
        let strength = line.emphasis == .none ? 0.10 : 0.22
        switch line.kind {
        case .added: return line.emphasis == .notable ? .yellow.opacity(0.16) : .green.opacity(strength)
        case .removed: return .red.opacity(strength)
        case .context: return .clear
        }
    }
}
