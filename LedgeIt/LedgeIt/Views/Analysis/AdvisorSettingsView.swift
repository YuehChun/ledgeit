import SwiftUI
import GRDB

struct AdvisorSettingsView: View {
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
    @AppStorage("categoryBudgetOverrides") private var budgetOverridesJSON = ""
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var budgetValues: [String: Double] = [:]
    @State private var feedbackText = ""
    @State private var isOptimizing = false
    @State private var isApplying = false
    @State private var optimizedPreview: PromptOptimizer.OptimizedPrompt?
    @State private var versions: [PromptVersion] = []
    @State private var revertTarget: PromptVersion?
    @State private var initialPersonaId = ""
    @ObservedObject private var goalService = GoalGenerationService.shared

    private var currentPersona: AdvisorPersona {
        AdvisorPersona.resolve(id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }

    private var hasActiveVersion: Bool {
        versions.contains(where: { $0.isActive })
    }

    private var hasPendingChanges: Bool {
        optimizedPreview != nil || revertTarget != nil || personaId != initialPersonaId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.aiAdvisor)
                        .font(.title2).fontWeight(.bold)
                    Text(l10n.aiAdvisorSubtitle)
                        .font(.callout).foregroundStyle(.secondary)
                }

                // MARK: - Persona Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    personaCard(id: "conservative", icon: "shield.fill", color: .blue,
                                name: l10n.conservative, desc: l10n.conservativeDesc,
                                target: "30%")
                    personaCard(id: "moderate", icon: "scale.3d", color: .green,
                                name: l10n.moderate, desc: l10n.moderateDesc,
                                target: "20%")
                    personaCard(id: "aggressive", icon: "flame.fill", color: .orange,
                                name: l10n.aggressive, desc: l10n.aggressiveDesc,
                                target: "10%")
                    personaCard(id: "custom", icon: "slider.horizontal.3", color: .purple,
                                name: l10n.custom, desc: l10n.customDesc,
                                target: "\(Int(customSavingsTarget * 100))%")
                }

                // MARK: - Custom Controls
                if personaId == "custom" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.savingsTargetLabel)
                            .font(.subheadline).fontWeight(.semibold)
                        HStack {
                            Slider(value: $customSavingsTarget, in: 0.05...0.50, step: 0.05)
                            Text("\(Int(customSavingsTarget * 100))%")
                                .font(.title3).fontWeight(.bold).monospacedDigit()
                                .frame(width: 50)
                        }
                        Text(l10n.riskLevel)
                            .font(.subheadline).fontWeight(.semibold)
                        Picker(l10n.riskLevel, selection: $customRiskLevel) {
                            Text(l10n.riskLow).tag("low")
                            Text(l10n.riskMedium).tag("medium")
                            Text(l10n.riskHigh).tag("high")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                    .padding(16)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // MARK: - Category Budget Limits
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(l10n.categoryBudgets, systemImage: "chart.bar.fill")
                            .font(.headline)
                        Spacer()
                        Button(l10n.resetToDefault) {
                            budgetValues = currentPersona.categoryBudgetHints
                            saveBudgets()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    let sortedKeys = budgetValues.sorted { $0.value > $1.value }.map(\.key)
                    ForEach(sortedKeys, id: \.self) { category in
                        HStack(spacing: 8) {
                            Text(l10n.categoryName(category))
                                .font(.callout)
                                .frame(width: 100, alignment: .leading)
                            Slider(value: budgetBinding(for: category), in: 0.01...0.50, step: 0.01)
                            Text("\(Int((budgetValues[category] ?? 0) * 100))%")
                                .font(.callout).fontWeight(.medium).monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // MARK: - Feedback & Optimize
                VStack(alignment: .leading, spacing: 12) {
                    Label(l10n.feedbackSection, systemImage: "wand.and.stars")
                        .font(.headline)

                    TextField(l10n.feedbackPlaceholder, text: $feedbackText, axis: .vertical)
                        .font(.callout)
                        .lineLimit(3...6)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .frame(minHeight: 80, alignment: .top)
                        .background(.background.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary, lineWidth: 1)
                        )

                    if isOptimizing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.optimizing)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            optimizePrompt()
                        } label: {
                            Label(l10n.optimizeButton, systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // MARK: - Pending Diff Review
                if let preview = optimizedPreview {
                    PromptDiffReviewCard(
                        l10n: l10n,
                        currentPersona: currentPersona,
                        proposed: preview,
                        isApplying: isApplying,
                        onApprove: { applyChanges() },
                        onReject: {
                            optimizedPreview = nil
                            revertTarget = nil
                        }
                    )
                } else {
                    // MARK: - Apply Button (for persona switch / revert only)
                    if isApplying {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.applying)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else if hasPendingChanges {
                        Button {
                            applyChanges()
                        } label: {
                            Label(l10n.applyButton, systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }

                // MARK: - Version History
                if !versions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(l10n.versionHistory, systemImage: "clock.arrow.circlepath")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(versions) { version in
                                versionRow(version)
                            }
                        }
                    }
                    .padding(16)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Divider()

                // MARK: - Generate Goals (single action)
                VStack(alignment: .leading, spacing: 12) {
                    Label(l10n.generateGoals, systemImage: "target")
                        .font(.headline)
                    Text(l10n.generateGoalsDesc)
                        .font(.callout).foregroundStyle(.secondary)

                    if goalService.isGenerating {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(l10n.generatingGoals)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            goalService.generateGoals(
                                personaId: personaId,
                                customSavingsTarget: customSavingsTarget,
                                customRiskLevel: customRiskLevel,
                                language: appLanguage
                            )
                        } label: {
                            Label(l10n.generateGoals, systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .navigationTitle(l10n.aiAdvisor)
        .onAppear {
            loadBudgets()
            loadVersions()
            initialPersonaId = personaId
        }
    }

    // MARK: - Version Row

    private func versionRow(_ version: PromptVersion) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("v\(version.id ?? 0)")
                        .font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Text(version.basePersonaId.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                    if version.isActive {
                        Text(l10n.activeVersion)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.green, in: Capsule())
                    }
                }
                if let feedback = version.userFeedback, !feedback.isEmpty {
                    Text(feedback)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(l10n.initialPreset)
                        .font(.caption).foregroundStyle(.tertiary)
                }
                if let date = version.createdAt {
                    Text(date.prefix(16).description)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if !version.isActive {
                Button(l10n.revert) {
                    revertTarget = version
                    optimizedPreview = nil
                }
                .buttonStyle(.bordered).controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Optimize Prompt

    private func optimizePrompt() {
        let feedback = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty else { return }
        isOptimizing = true
        let persona = AdvisorPersona.resolveWithVersions(
            id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel
        )
        let language = appLanguage
        Task {
            defer { isOptimizing = false }
            do {
                let openRouter = try OpenRouterService()
                let optimizer = PromptOptimizer(openRouter: openRouter)
                optimizedPreview = try await optimizer.optimizePrompt(
                    currentPersona: persona, feedback: feedback, language: language
                )
                revertTarget = nil
            } catch {
                print("PromptOptimizer failed: \(error)")
            }
        }
    }

    // MARK: - Apply Changes

    private func applyChanges() {
        isApplying = true
        let currentId = personaId
        let customTarget = customSavingsTarget
        let customRisk = customRiskLevel

        Task {
            defer {
                isApplying = false
                initialPersonaId = personaId
                feedbackText = ""
                optimizedPreview = nil
                revertTarget = nil
                loadVersions()
            }
            do {
                if let preview = optimizedPreview {
                    // Feedback-optimized: create new version
                    let persona = AdvisorPersona(
                        id: currentId,
                        savingsTarget: preview.savingsTarget,
                        riskLevel: preview.riskLevel,
                        spendingPhilosophy: preview.spendingPhilosophy,
                        categoryBudgetHints: preview.categoryBudgetHints
                    )
                    try await saveVersion(PromptVersion.fromPersona(persona, feedback: feedbackText))
                } else if let revert = revertTarget {
                    // Revert: activate selected version
                    try await activateVersion(revert)
                } else {
                    // Preset switch: save as new version
                    let persona = AdvisorPersona.resolve(
                        id: currentId, customSavingsTarget: customTarget, customRiskLevel: customRisk
                    )
                    try await saveVersion(PromptVersion.fromPersona(persona, feedback: nil))
                }
            } catch {
                print("Apply failed: \(error)")
            }
        }
    }

    // MARK: - DB Operations

    private func saveVersion(_ version: PromptVersion) async throws {
        try await AppDatabase.shared.db.write { db in
            // Deactivate existing
            try PromptVersion
                .filter(Column("is_active") == 1)
                .updateAll(db, PromptVersion.Columns.isActive.set(to: false))
            // Insert new
            var v = version
            v.isActive = true
            try v.insert(db)
        }
    }

    private func activateVersion(_ version: PromptVersion) async throws {
        guard let versionId = version.id else { return }
        try await AppDatabase.shared.db.write { db in
            try PromptVersion
                .filter(Column("is_active") == 1)
                .updateAll(db, PromptVersion.Columns.isActive.set(to: false))
            try PromptVersion
                .filter(PromptVersion.Columns.id == versionId)
                .updateAll(db, PromptVersion.Columns.isActive.set(to: true))
        }
    }

    // MARK: - Budget Persistence

    private func budgetBinding(for category: String) -> Binding<Double> {
        Binding(
            get: { budgetValues[category] ?? 0.10 },
            set: { newValue in
                budgetValues[category] = newValue
                saveBudgets()
            }
        )
    }

    private func saveBudgets() {
        if let data = try? JSONEncoder().encode(budgetValues),
           let json = String(data: data, encoding: .utf8) {
            budgetOverridesJSON = json
        }
    }

    private func loadBudgets() {
        if !budgetOverridesJSON.isEmpty,
           let data = budgetOverridesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: data) {
            budgetValues = decoded
        } else {
            budgetValues = currentPersona.categoryBudgetHints
        }
    }

    private func loadVersions() {
        versions = (try? AppDatabase.shared.db.read { db in
            try PromptVersion
                .order(PromptVersion.Columns.id.desc)
                .fetchAll(db)
        }) ?? []
    }

    // MARK: - Persona Card

    @ViewBuilder
    private func personaCard(id: String, icon: String, color: Color, name: String, desc: String, target: String) -> some View {
        Button {
            personaId = id
            optimizedPreview = nil
            revertTarget = nil
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                    Text(target)
                        .font(.title3).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(color)
                }
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(personaId == id ? color.opacity(0.08) : Color.clear)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(personaId == id ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Prompt Diff Review Card

private struct PromptDiffReviewCard: View {
    let l10n: L10n
    let currentPersona: AdvisorPersona
    let proposed: PromptOptimizer.OptimizedPrompt
    let isApplying: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(l10n.pendingReview, systemImage: "eye.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            // Changes summary
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.changesSummary)
                    .font(.caption).foregroundStyle(.secondary).fontWeight(.medium)
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
                    .font(.caption).foregroundStyle(.secondary).fontWeight(.medium)

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
                .font(.caption).foregroundStyle(.tertiary).fontWeight(.medium)

                paramRow(
                    l10n.savingsTargetLabel,
                    old: "\(Int(currentPersona.savingsTarget * 100))%",
                    new: "\(Int(proposed.savingsTarget * 100))%",
                    changed: currentPersona.savingsTarget != proposed.savingsTarget
                )
                paramRow(
                    l10n.riskLevel,
                    old: currentPersona.riskLevel,
                    new: proposed.riskLevel,
                    changed: currentPersona.riskLevel != proposed.riskLevel
                )
            }
            .padding(10)
            .background(.background.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Prompt diff
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.promptDiff)
                    .font(.caption).foregroundStyle(.secondary).fontWeight(.medium)

                InlineDiffView(
                    oldText: currentPersona.spendingPhilosophy,
                    newText: proposed.spendingPhilosophy
                )
            }

            // Approve / Reject
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
        .padding(16)
        .background(.orange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
