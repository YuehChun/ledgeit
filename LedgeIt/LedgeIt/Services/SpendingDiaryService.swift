import Foundation
import GRDB
import os

private let diaryLogger = Logger(subsystem: "com.ledgeit", category: "SpendingDiary")

actor SpendingDiaryService {
    static let shared = SpendingDiaryService()

    private let database: AppDatabase
    private let queryService: FinancialQueryService

    init(
        database: AppDatabase = .shared,
        queryService: FinancialQueryService = FinancialQueryService()
    ) {
        self.database = database
        self.queryService = queryService
    }

    // MARK: - Public API

    func runIfNeeded() async {
        do {
            try await cleanupOldRecords()
            try await generateMissingEntries()
        } catch {
            diaryLogger.error("Spending diary generation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Generation

    private func generateMissingEntries() async throws {
        let dates = lookbackDates(days: 7)
        for date in dates {
            await generateEntry(for: date)
        }
    }

    private func generateEntry(for date: String) async {
        do {
            let existing = try await database.db.read { db in
                try SpendingDiaryEntry
                    .filter(SpendingDiaryEntry.Columns.date == date)
                    .filter(SpendingDiaryEntry.Columns.status == "completed")
                    .fetchOne(db)
            }
            if existing != nil {
                diaryLogger.info("Diary for \(date) already exists, skipping")
                return
            }

            try await database.db.write { db in
                try SpendingDiaryEntry
                    .filter(SpendingDiaryEntry.Columns.date == date)
                    .deleteAll(db)
            }

            let entry = SpendingDiaryEntry.pending(date: date)
            try await database.db.write { db in
                try entry.save(db)
            }

            let filter = TransactionFilter(startDate: date, endDate: date)
            let transactions = try await queryService.getTransactions(filter: filter)
            let debitTransactions = transactions.filter { $0.type == "debit" }

            let transactionData = debitTransactions.map {
                (merchant: $0.merchant ?? "Unknown", amount: $0.amount, category: $0.category ?? "Other")
            }
            let totalSpending = debitTransactions.reduce(0.0) { $0 + $1.amount }
            let primaryCurrency = debitTransactions.first?.currency ?? "TWD"

            let monthStart = String(date.prefix(7)) + "-01"
            let monthFilter = TransactionFilter(startDate: monthStart, endDate: date)
            let monthTransactions = try await queryService.getTransactions(filter: monthFilter)
            let monthTotal = monthTransactions.filter { $0.type == "debit" }.reduce(0.0) { $0 + $1.amount }
            let daysInMonth = max(1, dayOfMonth(date))
            let dailyAverage = monthTotal / Double(daysInMonth)

            let personaId = UserDefaults.standard.string(forKey: "advisorPersonaId") ?? "moderate"
            let customSavings = UserDefaults.standard.double(forKey: "customSavingsTarget")
            let customRisk = UserDefaults.standard.string(forKey: "customRiskLevel") ?? "medium"
            let persona = AdvisorPersona.resolve(
                id: personaId,
                customSavingsTarget: customSavings > 0 ? customSavings : 0.20,
                customRiskLevel: customRisk
            )

            let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            let language = appLanguage == "zh-Hant"
                ? "Traditional Chinese (繁體中文)"
                : "English"

            let systemPrompt = Self.buildSystemPrompt(
                spendingPhilosophy: persona.spendingPhilosophy,
                language: language
            )
            let userPrompt = Self.buildUserPrompt(
                transactions: transactionData,
                totalSpending: totalSpending,
                transactionCount: debitTransactions.count,
                monthToDateTotal: monthTotal,
                monthDailyAverage: dailyAverage,
                currency: primaryCurrency
            )

            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(
                assignment: config.advisor,
                config: config,
                instructions: systemPrompt
            )
            let messages: [LLMMessage] = [.user(userPrompt)]
            let content = try await session.complete(messages: messages, temperature: 0.7, maxTokens: 600)

            try await database.db.write { db in
                try db.execute(
                    sql: """
                        UPDATE spending_diary_entries
                        SET content = ?, persona_id = ?, transaction_count = ?,
                            total_spending = ?, currency = ?, status = 'completed'
                        WHERE date = ?
                        """,
                    arguments: [content, personaId, debitTransactions.count,
                               totalSpending, primaryCurrency, date]
                )
            }
            diaryLogger.info("Diary for \(date) generated successfully")
        } catch {
            diaryLogger.error("Diary generation failed for \(date): \(error.localizedDescription)")
            try? await database.db.write { db in
                try db.execute(
                    sql: "UPDATE spending_diary_entries SET status = 'failed' WHERE date = ?",
                    arguments: [date]
                )
            }
        }
    }

    // MARK: - Prompt Builders (static for testability)

    static func buildSystemPrompt(spendingPhilosophy: String, language: String) -> String {
        """
        You are a personal spending diary writer. Write diary entries in first-person \
        perspective as if you are the user reflecting on their day.

        Personality & tone: \(spendingPhilosophy)

        Rules:
        - CRITICAL: You MUST write ALL text in \(language). Do NOT use any other language.
        - Write 200-400 characters
        - Narrative style, like a real diary entry
        - Mention specific merchants and amounts naturally in the story
        - Do NOT guess or assume what a merchant sells or does. Only describe the transaction factually (name + amount + category)
        - End with a brief reflection or feeling
        - If no transactions, write about having a spending-free day
        - Never give direct financial advice
        """
    }

    static func buildUserPrompt(
        transactions: [(merchant: String, amount: Double, category: String)],
        totalSpending: Double,
        transactionCount: Int,
        monthToDateTotal: Double,
        monthDailyAverage: Double,
        currency: String
    ) -> String {
        if transactions.isEmpty {
            return """
                Today's date had no transactions recorded.
                Month-to-date total: \(currency) \(String(format: "%.0f", monthToDateTotal))
                Daily average this month: \(currency) \(String(format: "%.0f", monthDailyAverage))
                """
        }

        let list = transactions.map { "- \($0.merchant) (\($0.category)): \(currency) \(String(format: "%.0f", $0.amount))" }
            .joined(separator: "\n")

        return """
            Transactions (\(transactionCount)):
            \(list)

            Total spending: \(currency) \(String(format: "%.0f", totalSpending))
            Month-to-date total: \(currency) \(String(format: "%.0f", monthToDateTotal))
            Daily average this month: \(currency) \(String(format: "%.0f", monthDailyAverage))
            """
    }

    // MARK: - Helpers

    private func lookbackDates(days: Int) -> [String] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        var dates: [String] = []

        for i in 1...days {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                dates.append(fmt.string(from: date))
            }
        }
        return dates
    }

    private func dayOfMonth(_ dateString: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateString) else { return 1 }
        return Calendar.current.component(.day, from: date)
    }

    private func cleanupOldRecords() async throws {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) else { return }
        let cutoffString = fmt.string(from: cutoff)

        try await database.db.write { db in
            try SpendingDiaryEntry
                .filter(SpendingDiaryEntry.Columns.date < cutoffString)
                .deleteAll(db)
        }
    }
}
