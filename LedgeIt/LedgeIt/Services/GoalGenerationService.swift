import Foundation
import SwiftUI
import GRDB

/// Singleton service that generates financial goals in the background,
/// independent of view lifecycle. Persists across page navigation.
@MainActor
final class GoalGenerationService: ObservableObject {
    static let shared = GoalGenerationService()

    @Published var isGenerating = false
    @Published var currentStep = 0

    private init() {}

    func generateGoals(personaId: String, customSavingsTarget: Double, customRiskLevel: String, language: String) {
        guard !isGenerating else { return }
        isGenerating = true
        currentStep = 0

        Task {
            do {
                // Step 0: Analyzing spending
                let persona = AdvisorPersona.resolveWithVersions(
                    id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel
                )
                let analyzer = SpendingAnalyzer(database: AppDatabase.shared)
                let calendar = Calendar.current
                let now = Date()
                let year = calendar.component(.year, from: now)
                let month = calendar.component(.month, from: now)
                let monthlyReport = try analyzer.monthlyBreakdown(year: year, month: month)

                let advice: FinancialAdvisor.SpendingAdvice
                let saved = try await AppDatabase.shared.db.read { db in
                    try FinancialReport
                        .order(FinancialReport.Columns.createdAt.desc)
                        .fetchOne(db)
                }

                let providerConfig = AIProviderConfigStore.load()

                if let saved, let adviceData = saved.adviceJSON.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(FinancialAdvisor.SpendingAdvice.self, from: adviceData) {
                    advice = decoded
                } else {
                    let advisor = FinancialAdvisor(providerConfig: providerConfig)
                    advice = try await advisor.analyzeSpendingHabits(
                        report: monthlyReport, trends: [], language: language, persona: persona
                    )
                }

                // Step 1: Creating goals
                self.currentStep = 1
                _ = try await AppDatabase.shared.db.write { db in
                    try FinancialGoal
                        .filter(FinancialGoal.Columns.status == "suggested")
                        .deleteAll(db)
                }

                let planner = GoalPlanner(providerConfig: providerConfig, database: AppDatabase.shared)

                // Step 2: Calculating targets
                self.currentStep = 2
                let newGoals = try await planner.suggestGoals(
                    report: monthlyReport, advice: advice, language: language, persona: persona
                )
                try await planner.saveGoals(newGoals)
            } catch {
                print("GoalGenerationService: failed to generate goals: \(error)")
            }
            self.isGenerating = false
            self.currentStep = 0
        }
    }
}
