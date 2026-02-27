import Foundation
import GRDB

@Observable
@MainActor
final class ReportGenerator {
    let database: AppDatabase
    private let analyzer: SpendingAnalyzer
    private let advisor: FinancialAdvisor
    private let goalPlanner: GoalPlanner

    var isGenerating = false
    var progress: String = ""

    init(database: AppDatabase, openRouter: OpenRouterService) {
        self.database = database
        self.analyzer = SpendingAnalyzer(database: database)
        self.advisor = FinancialAdvisor(openRouter: openRouter)
        self.goalPlanner = GoalPlanner(openRouter: openRouter, database: database)
    }

    // MARK: - Full Report Types

    struct FullReport: Sendable {
        let monthlyReport: SpendingAnalyzer.MonthlyReport
        let trends: [SpendingAnalyzer.MonthTrend]
        let advice: FinancialAdvisor.SpendingAdvice
        let goals: GoalPlanner.GoalSuggestions
    }

    // MARK: - Generate Report

    func generateMonthlyReport(year: Int, month: Int) async throws -> FullReport {
        guard !isGenerating else {
            throw ReportError.alreadyGenerating
        }
        isGenerating = true
        defer { isGenerating = false }

        // Step 1: Statistical analysis
        progress = "Analyzing spending data..."
        let report = try analyzer.monthlyBreakdown(year: year, month: month)
        let trends = try analyzer.spendingTrend(months: 6)

        // Step 2: AI financial advice
        progress = "Generating financial advice..."
        let advice = try await advisor.analyzeSpendingHabits(report: report, trends: trends)

        // Step 3: AI goal suggestions
        progress = "Planning financial goals..."
        let goals = try await goalPlanner.suggestGoals(report: report, advice: advice)

        // Step 4: Save goals to DB
        try await goalPlanner.saveGoals(goals)

        // Step 5: Persist report
        progress = "Saving report..."
        try await persistReport(
            year: year, month: month,
            report: report, advice: advice, goals: goals
        )

        progress = ""
        return FullReport(
            monthlyReport: report,
            trends: trends,
            advice: advice,
            goals: goals
        )
    }

    private func persistReport(
        year: Int, month: Int,
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice,
        goals: GoalPlanner.GoalSuggestions
    ) async throws {
        let encoder = JSONEncoder()

        let summaryDict: [String: Any] = [
            "total_spending": report.totalSpending,
            "total_income": report.totalIncome,
            "savings_rate": report.savingsRate,
            "transaction_count": report.transactionCount,
            "categories": report.categoryBreakdown.map { ["name": $0.category, "amount": $0.amount, "pct": $0.percentage] }
        ]
        let summaryJSON = String(data: try JSONSerialization.data(withJSONObject: summaryDict), encoding: .utf8) ?? "{}"
        let adviceJSON = String(data: try encoder.encode(advice), encoding: .utf8) ?? "{}"
        let goalsJSON = String(data: try encoder.encode(goals), encoding: .utf8) ?? "{}"

        let periodStart = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let periodEnd = String(format: "%04d-%02d-01", endYear, endMonth)

        let record = FinancialReport(
            id: UUID().uuidString,
            reportType: "monthly",
            periodStart: periodStart,
            periodEnd: periodEnd,
            summaryJSON: summaryJSON,
            adviceJSON: adviceJSON,
            goalsJSON: goalsJSON,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        try await database.db.write { [record] db in
            try record.insert(db)
        }
    }

    // MARK: - Fetch Saved Reports

    func getLatestReport() async throws -> FinancialReport? {
        try await database.db.read { db in
            try FinancialReport
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    func getGoals(status: String? = nil) async throws -> [FinancialGoal] {
        try await database.db.read { db in
            var query = FinancialGoal.all()
            if let status {
                query = query.filter(FinancialGoal.Columns.status == status)
            }
            return try query
                .order(FinancialGoal.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func updateGoalStatus(goalId: String, status: String) async throws {
        try await database.db.write { db in
            if var goal = try FinancialGoal.fetchOne(db, key: goalId) {
                goal.status = status
                try goal.update(db)
            }
        }
    }
}

enum ReportError: LocalizedError {
    case alreadyGenerating

    var errorDescription: String? {
        switch self {
        case .alreadyGenerating: return "A report is already being generated"
        }
    }
}
