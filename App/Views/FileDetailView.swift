import SwiftUI
import WardenCore

struct FileDetailView: View {
    let model: AppModel
    let status: FileStatus

    var body: some View {
        if let change = status.pending {
            ChangeDetailView(model: model, status: status, change: change)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ShieldBadge(state: .secure, isPaused: false, size: 44)
                    Text(verbatim: status.target.displayName).font(.title3.weight(.semibold))
                    if !status.exists {
                        Text("This file does not exist yet. Warden will alert you if it appears.")
                            .foregroundStyle(.secondary)
                    } else if let date = status.baselineDate {
                        Text("Matches the reference from \(date.formatted(date: .abbreviated, time: .shortened)).")
                            .foregroundStyle(.secondary)
                    }
                    if status.target.policy.isFiltered {
                        Text("Only security-related keys of this file trigger alerts. Routine writes stay silent.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 90)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct ChangeDetailView: View {
    let model: AppModel
    let status: FileStatus
    let change: PendingChange
    @State private var diff: LineDiff?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ExplanationCard(explanation: change.explanation)
                actions
                if let diff {
                    DiffView(diff: diff)
                }
            }
            .padding(20)
        }
        .task(id: change.fingerprint) {
            diff = await model.diff(for: change)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: status.target.displayName).font(.title3.weight(.semibold))
            SeverityBadge(severity: change.severity)
            Spacer()
            Text(change.detectedAt, format: .dateTime.day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            let revertFirst = change.explanation.recommendedAction == .revert
            decisionButton("Revert", isPrimary: revertFirst) { model.revert(path: change.path) }
            decisionButton("Accept", isPrimary: !revertFirst) { model.accept(path: change.path) }
            Spacer()
            Text(revertHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var revertHint: LocalizedStringKey {
        status.target.policy.isFiltered
            ? "Revert restores the security keys and saves a backup."
            : "Revert restores the reference and saves a backup."
    }

    @ViewBuilder
    private func decisionButton(_ title: LocalizedStringKey, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        if isPrimary {
            Button(title, action: action).buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Button(title, action: action).buttonStyle(.bordered).controlSize(.large)
        }
    }
}

private struct ExplanationCard: View {
    let explanation: Explanation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("What changed", explanation.whatChanged)
            section("What it means for you", explanation.impact)
            section("What Warden recommends", explanation.recommendation)
            Text(LocalizedStringKey(explanation.source.label))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func section(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
