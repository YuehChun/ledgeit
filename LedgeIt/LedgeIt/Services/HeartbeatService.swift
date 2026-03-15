import Foundation
import GRDB
import os.log

private let heartbeatLogger = Logger(subsystem: "com.ledgeit.app", category: "HeartbeatService")

actor HeartbeatService {

    static let shared = HeartbeatService()

    private let database: AppDatabase
    private let queryService: FinancialQueryService
    private let agentFileManager: AgentFileManager

    init(
        database: AppDatabase = .shared,
        queryService: FinancialQueryService = FinancialQueryService(),
        agentFileManager: AgentFileManager = AgentFileManager()
    ) {
        self.database = database
        self.queryService = queryService
        self.agentFileManager = agentFileManager
    }

    // MARK: - Public API

    func runIfNeeded() async {
        guard await LicenseManager.shared.isPro else { return }
        do {
            try await cleanupOldRecords()

            let today = todayString()
            let existing = try await database.db.read { db in
                try HeartbeatInsight
                    .filter(HeartbeatInsight.Columns.date == today)
                    .filter(HeartbeatInsight.Columns.status == "completed")
                    .fetchOne(db)
            }

            if existing != nil {
                heartbeatLogger.info("Today's insight already exists, skipping")
                return
            }

            // Delete any previous pending/failed record for today
            try await database.db.write { db in
                try HeartbeatInsight
                    .filter(HeartbeatInsight.Columns.date == today)
                    .deleteAll(db)
            }

            // Insert pending record
            let insight = HeartbeatInsight.pending(date: today)
            try await database.db.write { db in
                try insight.save(db)
            }

            heartbeatLogger.info("Generating daily insight...")
            let content = try await generateInsight()

            // Update to completed
            try await database.db.write { db in
                try db.execute(
                    sql: "UPDATE heartbeat_insights SET content = ?, status = 'completed' WHERE date = ?",
                    arguments: [content, today]
                )
            }
            heartbeatLogger.info("Daily insight generated successfully")

            // Auto-archive old daily logs if needed
            do {
                let archived = try await AgentMemoryConsolidator.shared.consolidateIfNeeded(fileManager: agentFileManager)
                if archived {
                    heartbeatLogger.info("Daily logs archived successfully")
                }
            } catch {
                heartbeatLogger.warning("Daily log consolidation failed: \(error.localizedDescription)")
            }

        } catch {
            heartbeatLogger.error("Heartbeat failed: \(error.localizedDescription)")
            let today = todayString()
            try? await database.db.write { db in
                try db.execute(
                    sql: "UPDATE heartbeat_insights SET status = 'failed' WHERE date = ?",
                    arguments: [today]
                )
            }
        }
    }

    // MARK: - Private

    private func generateInsight() async throws -> String {
        // Build system prompt from agent memory
        let overview = try await queryService.getAccountOverview()
        let financialSnapshot = formatAccountOverview(overview)
        let systemPrompt = AgentPromptBuilder.build(
            fileManager: agentFileManager,
            financialSnapshot: financialSnapshot
        )

        // Gather financial data for user message
        let currentMonth = try await queryService.getTransactionSummary(period: .thisMonth)
        let lastMonth = try await queryService.getTransactionSummary(period: .lastMonth)
        let upcoming = try await queryService.getUpcomingPayments()
        let goals = try await queryService.getGoals(status: "accepted")

        let userMessage = buildUserMessage(
            overview: overview,
            currentMonth: currentMonth,
            lastMonth: lastMonth,
            upcoming: upcoming,
            goals: goals
        )

        // Make single LLM call
        let config = AIProviderConfigStore.load()
        let session = try SessionFactory.makeSession(
            assignment: config.advisor,
            config: config,
            instructions: systemPrompt
        )

        let messages: [LLMMessage] = [.user(userMessage)]
        let content = try await session.complete(messages: messages, temperature: 0.7, maxTokens: nil)

        guard !content.isEmpty else {
            throw HeartbeatError.emptyResponse
        }

        return content
    }

    private func buildUserMessage(
        overview: AccountOverview,
        currentMonth: SpendingSummary,
        lastMonth: SpendingSummary,
        upcoming: [CreditCardBill],
        goals: [FinancialGoal]
    ) -> String {
        var parts: [String] = []

        parts.append("""
        Here is today's financial data. Based on this data and your memory of the user,
        provide today's key insights and reminders. Focus on what's most important —
        upcoming deadlines, unusual spending, goal progress, or patterns worth noting.
        Be concise and actionable. Respond in the user's preferred language.
        """)

        parts.append("## Account Overview")
        parts.append("- Transactions this month: \(overview.transactionCount)")
        parts.append("- Income: \(overview.totalIncome)")
        parts.append("- Expenses: \(overview.totalExpenses)")
        parts.append("- Net: \(overview.totalIncome - overview.totalExpenses)")

        parts.append("\n## This Month vs Last Month")
        parts.append("- This month income: \(currentMonth.totalIncome), expenses: \(currentMonth.totalExpenses)")
        parts.append("- Last month income: \(lastMonth.totalIncome), expenses: \(lastMonth.totalExpenses)")

        if !upcoming.isEmpty {
            parts.append("\n## Upcoming Payments")
            for bill in upcoming {
                parts.append("- \(bill.bankName): \(bill.amountDue) \(bill.currency) due \(bill.dueDate)")
            }
        } else {
            parts.append("\n## Upcoming Payments\nNo upcoming payments.")
        }

        if !goals.isEmpty {
            parts.append("\n## Active Goals")
            for goal in goals {
                let target = goal.targetAmount.map { String(format: "%.0f", $0) } ?? "N/A"
                parts.append("- \(goal.title): \(goal.progress)% progress, target \(target) (\(goal.status))")
            }
        } else {
            parts.append("\n## Active Goals\nNo active goals.")
        }

        return parts.joined(separator: "\n")
    }

    private func formatAccountOverview(_ overview: AccountOverview) -> String {
        """
        Transactions: \(overview.transactionCount)
        Income: \(overview.totalIncome)
        Expenses: \(overview.totalExpenses)
        Upcoming payments: \(overview.upcomingPayments)
        Active goals: \(overview.activeGoals)
        """
    }

    private func cleanupOldRecords() async throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let cutoffString = ISO8601DateFormatter().string(from: cutoff)
        try await database.db.write { db in
            try db.execute(
                sql: "DELETE FROM heartbeat_insights WHERE created_at < ?",
                arguments: [cutoffString]
            )
        }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    enum HeartbeatError: LocalizedError {
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .emptyResponse: return "LLM returned an empty response"
            }
        }
    }
}
