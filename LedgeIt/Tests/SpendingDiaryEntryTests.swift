import Testing
import GRDB
@testable import LedgeIt

struct SpendingDiaryEntryTests {

    private func makeTestDatabase() throws -> DatabaseQueue {
        let db = try DatabaseQueue(path: ":memory:")
        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(&migrator)
        try migrator.migrate(db)
        return db
    }

    @Test func pendingEntryHasCorrectDefaults() {
        let entry = SpendingDiaryEntry.pending(date: "2026-03-15")
        #expect(entry.date == "2026-03-15")
        #expect(entry.content == "")
        #expect(entry.status == "pending")
        #expect(entry.personaId == "")
        #expect(entry.transactionCount == 0)
        #expect(entry.totalSpending == 0)
        #expect(entry.currency == "TWD")
    }

    @Test func canInsertAndFetchEntry() throws {
        let db = try makeTestDatabase()
        var entry = SpendingDiaryEntry.pending(date: "2026-03-15")
        try db.write { db in try entry.save(db) }
        let fetched = try db.read { db in
            try SpendingDiaryEntry
                .filter(SpendingDiaryEntry.Columns.date == "2026-03-15")
                .fetchOne(db)
        }
        #expect(fetched != nil)
        #expect(fetched?.status == "pending")
    }

    @Test func dateIsUnique() throws {
        let db = try makeTestDatabase()
        let entry1 = SpendingDiaryEntry.pending(date: "2026-03-15")
        let entry2 = SpendingDiaryEntry.pending(date: "2026-03-15")
        try db.write { db in try entry1.save(db) }
        #expect(throws: (any Error).self) {
            try db.write { db in try entry2.save(db) }
        }
    }
}
