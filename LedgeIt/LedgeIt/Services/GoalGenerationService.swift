import Foundation
import SwiftUI
import GRDB

/// Singleton service that generates financial goals in the background,
/// independent of view lifecycle. Persists across page navigation.
@MainActor
final class GoalGenerationService: ObservableObject {
    static let shared = GoalGenerationService()

    @Published var isGenerating = false

    private init() {}

    func generateGoals(personaId: String, customSavingsTarget: Double, customRiskLevel: String, language: String) {
        guard !isGenerating else { return }
        isGenerating = true

        let pid = personaId
        let target = customSavingsTarget
        let risk = customRiskLevel
        let lang = language

        Task {
            do {
                try await Self.performGeneration(personaId: pid, customTarget: target, customRisk: risk, language: lang)
            } catch {
                print("GoalGenerationService: failed to generate goals: \(error)")
            }
            self.isGenerating = false
        }
    }

    private nonisolated static func performGeneration(personaId: String, customTarget: Double, customRisk: String, language: String) async throws {
        let persona = AdvisorPersona.resolveWithVersions(
            id: personaId, customSavingsTarget: customTarget, customRiskLevel: customRisk
        )

        let analyzer = SpendingAnalyzer(database: AppDatabase.shared)
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let monthlyReport = try analyzer.monthlyBreakdown(year: year, month: month)

        // Try to load saved advice from latest report; generate fresh if none exists
        let advice: FinancialAdvisor.SpendingAdvice
        let saved = try await AppDatabase.shared.db.read { db in
            try FinancialReport
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchOne(db)
        }

        if let saved, let adviceData = saved.adviceJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(FinancialAdvisor.SpendingAdvice.self, from: adviceData) {
            advice = decoded
        } else {
            // No saved report — generate fresh advice on-the-fly
            let openRouter = try OpenRouterService()
            let advisor = FinancialAdvisor(openRouter: openRouter)
            advice = try await advisor.analyzeSpendingHabits(
                report: monthlyReport, trends: [], language: language, persona: persona
            )
        }

        // Delete old suggested goals
        _ = try await AppDatabase.shared.db.write { db in
            try FinancialGoal
                .filter(FinancialGoal.Columns.status == "suggested")
                .deleteAll(db)
        }

        // Generate and save new goals
        let openRouter = try OpenRouterService()
        let planner = GoalPlanner(openRouter: openRouter, database: AppDatabase.shared)
        let newGoals = try await planner.suggestGoals(
            report: monthlyReport, advice: advice, language: language, persona: persona
        )
        try await planner.saveGoals(newGoals)
    }
}
