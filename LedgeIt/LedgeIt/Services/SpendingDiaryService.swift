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
        let dates = lookbackDates(days: 7).reversed()
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

            let diaryPersona = UserDefaults.standard.string(forKey: "diaryPersona") ?? ""

            let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            let language = appLanguage == "zh-Hant"
                ? "Traditional Chinese (繁體中文)"
                : "English"

            // Load recent diary entries for story continuity
            let recentDiaries = try await database.db.read { db in
                try SpendingDiaryEntry
                    .filter(SpendingDiaryEntry.Columns.status == "completed")
                    .filter(SpendingDiaryEntry.Columns.date < date)
                    .order(SpendingDiaryEntry.Columns.date.desc)
                    .limit(3)
                    .fetchAll(db)
            }

            let systemPrompt = Self.buildSystemPrompt(
                diaryPersona: diaryPersona,
                language: language
            )
            let userPrompt = Self.buildUserPrompt(
                transactions: transactionData,
                totalSpending: totalSpending,
                transactionCount: debitTransactions.count,
                currency: primaryCurrency,
                recentDiaries: recentDiaries
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
                    arguments: [content, "diary", debitTransactions.count,
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

    static func buildSystemPrompt(diaryPersona: String, language: String) -> String {
        let personaSection = diaryPersona.isEmpty
            ? "You are a personal spending diary writer."
            : "You are a personal spending diary writer with the following personality:\n\(diaryPersona)\n\nYou MUST stay in character at all times. Every diary entry must reflect this personality — use relevant metaphors, vocabulary, and perspective from this character."

        return """
        \(personaSection)

        Write diary entries in first-person perspective as if you are the user reflecting on their day.

        Rules:
        - CRITICAL: You MUST write ALL text in \(language). Do NOT use any other language.
        - Write 200-400 characters.
        - Focus on describing the actual transactions: merchant name, amount, and category.
        - Do NOT include monthly spending summaries, monthly totals, or daily averages unless the user's persona specifically asks for it.
        - Do NOT guess or assume what a merchant sells or does. Only describe the transaction factually.
        - If previous diary entries are provided, reference them naturally to create story continuity (e.g., "just like last Tuesday..." or "unlike yesterday..."). The diary should feel like a continuous personal journal, not isolated daily reports.
        - If no transactions today, write an encouraging, positive diary entry — a motivational message about the peace of a no-spend day, smart money habits, or the value of saving. Stay in character and be creative.
        - Never give direct financial advice.
        """
    }

    static func buildUserPrompt(
        transactions: [(merchant: String, amount: Double, category: String)],
        totalSpending: Double,
        transactionCount: Int,
        currency: String,
        recentDiaries: [SpendingDiaryEntry] = []
    ) -> String {
        var parts: [String] = []

        // Recent diary context for story continuity
        if !recentDiaries.isEmpty {
            let diaryContext = recentDiaries.reversed().map { entry in
                "[\(entry.date)] \(entry.content)"
            }.joined(separator: "\n\n")
            parts.append("Previous diary entries (for continuity — reference these naturally):\n\(diaryContext)")
        }

        // Today's transactions
        if transactions.isEmpty {
            parts.append("Today: No transactions recorded.")
        } else {
            let list = transactions.map { "- \($0.merchant) (\($0.category)): \(currency) \(String(format: "%.0f", $0.amount))" }
                .joined(separator: "\n")
            parts.append("Today's transactions (\(transactionCount)):\n\(list)\n\nTotal: \(currency) \(String(format: "%.0f", totalSpending))")
        }

        return parts.joined(separator: "\n\n---\n\n")
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
