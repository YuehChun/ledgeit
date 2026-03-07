import SwiftUI
import GRDB

struct PromptVersionsView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var versions: [PromptVersion] = []
    @State private var pendingOptimization: PromptOptimizer.OptimizedPrompt?
    @State private var currentPersona: AdvisorPersona?
    @State private var feedbackText = ""
    @State private var isOptimizing = false
    @State private var optimizeError: String?
    @State private var isApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.promptVersions)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(l10n.promptVersionsSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Feedback + Optimize
                OptimizeFeedbackSection(
                    l10n: l10n,
                    feedbackText: $feedbackText,
                    isOptimizing: isOptimizing,
                    optimizeError: optimizeError,
                    onOptimize: { runOptimize() }
                )

                // Pending review
                if let pending = pendingOptimization, let current = currentPersona {
                    PendingReviewSection(
                        l10n: l10n,
                        current: current,
                        proposed: pending,
                        isApplying: isApplying,
                        onApprove: { approvePending() },
                        onReject: { pendingOptimization = nil }
                    )
                }

                Divider()

                // Version history
                VersionHistorySection(l10n: l10n, versions: versions)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear { loadData() }
    }

    // MARK: - Actions

    private func loadData() {
        do {
            versions = try AppDatabase.shared.db.read { db in
                try PromptVersion
                    .order(PromptVersion.Columns.id.desc)
                    .fetchAll(db)
            }
            let activeVersion = versions.first(where: { $0.isActive })
            currentPersona = activeVersion?.toPersona() ?? .moderate
        } catch {
            print("Failed to load versions: \(error)")
        }
    }

    private func runOptimize() {
        guard !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let persona = currentPersona ?? .moderate
        let language = appLanguage

        isOptimizing = true
        optimizeError = nil

        Task {
            do {
                let providerConfig = AIProviderConfigStore.load()
                let optimizer = PromptOptimizer(providerConfig: providerConfig)
                let result = try await optimizer.optimizePrompt(
                    currentPersona: persona,
                    feedback: feedbackText,
                    language: language
                )
                pendingOptimization = result
            } catch {
                optimizeError = error.localizedDescription
            }
            isOptimizing = false
        }
    }

    private func approvePending() {
        guard let pending = pendingOptimization else { return }
        isApplying = true

        Task {
            do {
                let hintsJSON = (try? String(data: JSONEncoder().encode(pending.categoryBudgetHints), encoding: .utf8)) ?? "{}"
                var newVersion = PromptVersion(
                    basePersonaId: currentPersona?.id ?? "custom",
                    spendingPhilosophy: pending.spendingPhilosophy,
                    savingsTarget: pending.savingsTarget,
                    riskLevel: pending.riskLevel,
                    categoryBudgetHints: hintsJSON,
                    userFeedback: feedbackText,
                    isActive: true,
                    createdAt: ISO8601DateFormatter().string(from: Date())
                )

                try AppDatabase.shared.db.write { db in
                    // Deactivate all existing
                    try PromptVersion
                        .filter(PromptVersion.Columns.isActive == true)
                        .updateAll(db, PromptVersion.Columns.isActive.set(to: false))
                    // Insert new active
                    try newVersion.insert(db)
                }

                pendingOptimization = nil
                feedbackText = ""
                loadData()
            } catch {
                optimizeError = "Failed to save: \(error.localizedDescription)"
            }
            isApplying = false
        }
    }
}

// MARK: - Optimize Feedback Section

private struct OptimizeFeedbackSection: View {
    let l10n: L10n
    @Binding var feedbackText: String
    let isOptimizing: Bool
    let optimizeError: String?
    let onOptimize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l10n.feedbackSection, systemImage: "sparkles")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.purple)

            TextEditor(text: $feedbackText)
                .font(.callout)
                .frame(height: 60)
                .padding(6)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Group {
                        if feedbackText.isEmpty {
                            Text(l10n.feedbackPlaceholder)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 10)
                                .padding(.top, 14)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )

            HStack {
                Button {
                    onOptimize()
                } label: {
                    if isOptimizing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(l10n.optimizing)
                        }
                    } else {
                        Label(l10n.optimizeButton, systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isOptimizing || feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error = optimizeError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Pending Review Section

private struct PendingReviewSection: View {
    let l10n: L10n
    let current: AdvisorPersona
    let proposed: PromptOptimizer.OptimizedPrompt
    let isApplying: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Label(l10n.pendingReview, systemImage: "eye.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)
                Spacer()
            }

            // Changes summary
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.changesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                Text(proposed.changesSummary)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Parameter comparison
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.parameters)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                HStack(spacing: 0) {
                    Text("")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(l10n.currentLabel)
                        .frame(width: 100, alignment: .trailing)
                    Text("→")
                        .frame(width: 30, alignment: .center)
                    Text(l10n.proposedLabel)
                        .frame(width: 100, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fontWeight(.medium)

                paramRow(
                    l10n.savingsTargetLabel,
                    old: "\(Int(current.savingsTarget * 100))%",
                    new: "\(Int(proposed.savingsTarget * 100))%",
                    changed: current.savingsTarget != proposed.savingsTarget
                )
                paramRow(
                    l10n.riskLevel,
                    old: current.riskLevel,
                    new: proposed.riskLevel,
                    changed: current.riskLevel != proposed.riskLevel
                )
            }
            .padding(10)
            .background(.background.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Prompt diff
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.promptDiff)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)

                InlineDiffView(
                    oldText: current.spendingPhilosophy,
                    newText: proposed.spendingPhilosophy
                )
            }

            // Approve / Reject buttons
            HStack {
                Spacer()
                Button(l10n.rejectPrompt) {
                    onReject()
                }
                .buttonStyle(.bordered)

                Button {
                    onApprove()
                } label: {
                    if isApplying {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(l10n.applying)
                        }
                    } else {
                        Label(l10n.approvePrompt, systemImage: "checkmark.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isApplying)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func paramRow(_ label: String, old: String, new: String, changed: Bool) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(old)
                .frame(width: 100, alignment: .trailing)
                .foregroundStyle(changed ? .red : .secondary)
            Text("→")
                .frame(width: 30, alignment: .center)
                .foregroundStyle(.tertiary)
            Text(new)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(changed ? .green : .secondary)
        }
        .font(.callout)
        .fontWeight(changed ? .medium : .regular)
    }
}

// MARK: - Inline Diff View

private struct InlineDiffView: View {
    let oldText: String
    let newText: String

    private var diffLines: [DiffLine] {
        TextDiff.diff(old: oldText, new: newText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diffLines) { line in
                HStack(spacing: 0) {
                    Text(prefix(for: line.type))
                        .frame(width: 20, alignment: .center)
                        .foregroundStyle(color(for: line.type))
                    Text(line.text.isEmpty ? " " : line.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(background(for: line.type))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    private func prefix(for type: DiffLineType) -> String {
        switch type {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "−"
        }
    }

    private func color(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }

    private func background(for type: DiffLineType) -> Color {
        switch type {
        case .unchanged: return .clear
        case .added: return .green.opacity(0.1)
        case .removed: return .red.opacity(0.1)
        }
    }
}

// MARK: - Version History Section

private struct VersionHistorySection: View {
    let l10n: L10n
    let versions: [PromptVersion]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l10n.versionHistory, systemImage: "clock.arrow.circlepath")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)

            if versions.isEmpty {
                ContentUnavailableView(
                    l10n.noVersionsYet,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(l10n.noVersionsDescription)
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(versions) { version in
                        VersionRow(l10n: l10n, version: version)
                    }
                }
            }
        }
    }
}

private struct VersionRow: View {
    let l10n: L10n
    let version: PromptVersion

    var body: some View {
        HStack(spacing: 10) {
            // Version number
            Text("v\(version.id ?? 0)")
                .font(.callout)
                .fontWeight(.bold)
                .monospacedDigit()
                .frame(width: 36)

            // Persona badge
            Text(version.basePersonaId)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .foregroundStyle(.purple)
                .background(.purple.opacity(0.1), in: Capsule())

            // Feedback excerpt
            Text(version.userFeedback ?? l10n.initialPreset)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            // Date
            if let date = version.createdAt {
                Text(date.prefix(16))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Active badge
            if version.isActive {
                Text(l10n.activeVersion)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.green)
                    .background(.green.opacity(0.1), in: Capsule())
            }
        }
        .padding(10)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
