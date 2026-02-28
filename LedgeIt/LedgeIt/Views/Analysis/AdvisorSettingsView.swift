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

                Divider()

                // MARK: - Feedback & Optimize
                VStack(alignment: .leading, spacing: 12) {
                    Label(l10n.feedbackSection, systemImage: "wand.and.stars")
                        .font(.headline)

                    TextEditor(text: $feedbackText)
                        .font(.callout)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if feedbackText.isEmpty {
                                Text(l10n.feedbackPlaceholder)
                                    .font(.callout).foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }

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

                    if let preview = optimizedPreview {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(l10n.optimizePreview, systemImage: "doc.text.magnifyingglass")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Text(preview.changesSummary)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 16) {
                                Label("\(Int(preview.savingsTarget * 100))%", systemImage: "percent")
                                    .font(.caption)
                                Label(preview.riskLevel.capitalized, systemImage: "gauge.medium")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.blue.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // MARK: - Apply Button
                if isApplying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(l10n.applying)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        applyChanges()
                    } label: {
                        Label(l10n.applyButton, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!hasPendingChanges)
                }

                // MARK: - Version History
                if !versions.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 8) {
                            ForEach(versions) { version in
                                versionRow(version)
                            }
                        }
                    } label: {
                        Label(l10n.versionHistory, systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                    }
                    .padding(16)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
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
        let language = appLanguage
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
                // 1. Determine what to apply
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
                    // Preset switch: deactivate any active version
                    try await deactivateAllVersions()
                }

                // 2. Regenerate goals
                try await regenerateGoals(language: language, personaId: currentId, customTarget: customTarget, customRisk: customRisk)
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

    private func deactivateAllVersions() async throws {
        _ = try await AppDatabase.shared.db.write { db in
            try PromptVersion
                .filter(Column("is_active") == 1)
                .updateAll(db, PromptVersion.Columns.isActive.set(to: false))
        }
    }

    private func regenerateGoals(language: String, personaId: String, customTarget: Double, customRisk: String) async throws {
        let persona = AdvisorPersona.resolveWithVersions(
            id: personaId, customSavingsTarget: customTarget, customRiskLevel: customRisk
        )

        // Load latest report
        let saved = try await AppDatabase.shared.db.read { db in
            try FinancialReport
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchOne(db)
        }
        guard let saved,
              let adviceData = saved.adviceJSON.data(using: .utf8) else { return }

        let advice = try JSONDecoder().decode(FinancialAdvisor.SpendingAdvice.self, from: adviceData)
        let components = saved.periodStart.split(separator: "-")
        guard components.count >= 2,
              let year = Int(components[0]),
              let month = Int(components[1]) else { return }

        let analyzer = SpendingAnalyzer(database: AppDatabase.shared)
        let monthlyReport = try analyzer.monthlyBreakdown(year: year, month: month)

        // Delete old suggested goals
        _ = try await AppDatabase.shared.db.write { db in
            try FinancialGoal
                .filter(FinancialGoal.Columns.status == "suggested")
                .deleteAll(db)
        }

        // Generate new goals
        let openRouter = try OpenRouterService()
        let planner = GoalPlanner(openRouter: openRouter, database: AppDatabase.shared)
        let newGoals = try await planner.suggestGoals(
            report: monthlyReport, advice: advice, language: language, persona: persona
        )
        try await planner.saveGoals(newGoals)
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
