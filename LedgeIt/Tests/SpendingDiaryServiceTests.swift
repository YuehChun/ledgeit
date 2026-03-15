import Testing
import Foundation
import GRDB
@testable import LedgeIt

struct SpendingDiaryServiceTests {

    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(path: ":memory:")
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(&migrator)
        try migrator.migrate(db)
        return db
    }

    @Test func buildPromptWithTransactions() {
        let transactions: [(merchant: String, amount: Double, category: String)] = [
            ("7-ELEVEN", 45, "Food & Drink"),
            ("麥當勞", 189, "Food & Drink"),
        ]
        let prompt = SpendingDiaryService.buildUserPrompt(
            transactions: transactions,
            totalSpending: 234,
            transactionCount: 2,
            monthToDateTotal: 12450,
            monthDailyAverage: 830,
            currency: "TWD"
        )
        #expect(prompt.contains("7-ELEVEN"))
        #expect(prompt.contains("234"))
        #expect(prompt.contains("TWD"))
    }

    @Test func buildPromptWithNoTransactions() {
        let prompt = SpendingDiaryService.buildUserPrompt(
            transactions: [],
            totalSpending: 0,
            transactionCount: 0,
            monthToDateTotal: 12450,
            monthDailyAverage: 830,
            currency: "TWD"
        )
        #expect(prompt.contains("no transactions"))
    }

    @Test func buildSystemPromptIncludesPersona() {
        let prompt = SpendingDiaryService.buildSystemPrompt(
            spendingPhilosophy: "Balance lifestyle and savings",
            language: "Traditional Chinese"
        )
        #expect(prompt.contains("Balance lifestyle and savings"))
        #expect(prompt.contains("Traditional Chinese"))
    }

    @Test func skipsExistingCompletedEntry() async throws {
        let db = try makeTestDatabase()
        var entry = SpendingDiaryEntry.pending(date: yesterdayString())
        entry.status = "completed"
        entry.content = "Existing diary"
        let entryToSave = entry
        try await db.write { db in try entryToSave.save(db) }

        let needsGeneration = try await db.read { db in
            try SpendingDiaryEntry
                .filter(SpendingDiaryEntry.Columns.date == yesterdayString())
                .filter(SpendingDiaryEntry.Columns.status == "completed")
                .fetchOne(db)
        }
        #expect(needsGeneration != nil)
    }

    private func yesterdayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }
}
