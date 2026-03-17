# Spending Diary Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a daily, narrative-style spending diary feature that auto-generates persona-voiced diary entries and displays them in a compact calendar + diary panel layout.

**Architecture:** New `SpendingDiaryEntry` model + `SpendingDiaryService` actor (following HeartbeatService pattern). CalendarView restructured to 1/3 compact calendar + 2/3 diary panel. LLM generates diary entries using AdvisorPersona's spendingPhilosophy for tone.

**Tech Stack:** Swift 6.2, SwiftUI, GRDB 7.0, SessionFactory (multi-provider LLM), Swift Testing framework

**Spec:** `docs/superpowers/specs/2026-03-16-spending-diary-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `LedgeIt/LedgeIt/Models/SpendingDiaryEntry.swift` | Create | Data model for diary entries |
| `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift` | Modify | Add v17 migration for `spending_diary_entries` table |
| `LedgeIt/LedgeIt/Services/SpendingDiaryService.swift` | Create | Actor service for diary generation |
| `LedgeIt/LedgeIt/Views/CalendarView.swift` | Modify | Restructure to compact calendar + diary panel |
| `LedgeIt/LedgeIt/Views/Calendar/DiaryPanelView.swift` | Create | Diary detail panel component |
| `LedgeIt/LedgeIt/Views/ContentView.swift` | Modify | Add SpendingDiaryService launch on app start |
| `LedgeIt/Tests/SpendingDiaryEntryTests.swift` | Create | Model tests |
| `LedgeIt/Tests/SpendingDiaryServiceTests.swift` | Create | Service logic tests |

---

## Chunk 1: Data Model & Migration

### Task 1: SpendingDiaryEntry Model

**Files:**
- Create: `LedgeIt/LedgeIt/Models/SpendingDiaryEntry.swift`
- Test: `LedgeIt/Tests/SpendingDiaryEntryTests.swift`

- [ ] **Step 1: Write the model test**

```swift
// LedgeIt/Tests/SpendingDiaryEntryTests.swift
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

        try db.write { db in
            try entry.save(db)
        }

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LedgeIt && swift test --filter SpendingDiaryEntryTests 2>&1 | head -30`
Expected: FAIL — `SpendingDiaryEntry` not found

- [ ] **Step 3: Create the SpendingDiaryEntry model**

Follow the HeartbeatInsight pattern in `LedgeIt/LedgeIt/Models/HeartbeatInsight.swift`.

```swift
// LedgeIt/LedgeIt/Models/SpendingDiaryEntry.swift
import Foundation
import GRDB

struct SpendingDiaryEntry: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let date: String
    var content: String
    var personaId: String
    var transactionCount: Int
    var totalSpending: Double
    var currency: String
    var status: String
    let createdAt: String

    static let databaseTableName = "spending_diary_entries"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let content = Column(CodingKeys.content)
        static let personaId = Column(CodingKeys.personaId)
        static let transactionCount = Column(CodingKeys.transactionCount)
        static let totalSpending = Column(CodingKeys.totalSpending)
        static let currency = Column(CodingKeys.currency)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case content
        case personaId = "persona_id"
        case transactionCount = "transaction_count"
        case totalSpending = "total_spending"
        case currency
        case status
        case createdAt = "created_at"
    }

    static func pending(date: String) -> SpendingDiaryEntry {
        SpendingDiaryEntry(
            id: UUID(),
            date: date,
            content: "",
            personaId: "",
            transactionCount: 0,
            totalSpending: 0,
            currency: "TWD",
            status: "pending",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
```

- [ ] **Step 4: Add database migration v17**

Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift` — add after the v16 heartbeat migration block (after line ~343):

```swift
// MARK: - v17: Spending diary entries table
migrator.registerMigration("v17") { db in
    try db.create(table: "spending_diary_entries") { t in
        t.primaryKey("id", .text)
        t.column("date", .text).notNull().unique()
        t.column("content", .text).notNull().defaults(to: "")
        t.column("persona_id", .text).notNull().defaults(to: "")
        t.column("transaction_count", .integer).notNull().defaults(to: 0)
        t.column("total_spending", .double).notNull().defaults(to: 0)
        t.column("currency", .text).notNull().defaults(to: "TWD")
        t.column("status", .text).notNull().defaults(to: "pending")
        t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd LedgeIt && swift test --filter SpendingDiaryEntryTests 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/Models/SpendingDiaryEntry.swift \
       LedgeIt/LedgeIt/Database/DatabaseMigrations.swift \
       LedgeIt/Tests/SpendingDiaryEntryTests.swift
git commit -m "feat(diary): add SpendingDiaryEntry model and v17 migration"
```

---

## Chunk 2: SpendingDiaryService

### Task 2: SpendingDiaryService — Core Generation Logic

**Files:**
- Create: `LedgeIt/LedgeIt/Services/SpendingDiaryService.swift`
- Test: `LedgeIt/Tests/SpendingDiaryServiceTests.swift`

- [ ] **Step 1: Write the service test**

Follow the MockLicenseDeps pattern from `LedgeIt/Tests/LicenseManagerTests.swift` for dependency injection.

```swift
// LedgeIt/Tests/SpendingDiaryServiceTests.swift
import Testing
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
        // Insert a completed entry for yesterday
        var entry = SpendingDiaryEntry.pending(date: yesterdayString())
        entry.status = "completed"
        entry.content = "Existing diary"
        try db.write { db in try entry.save(db) }

        let needsGeneration = try db.read { db in
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd LedgeIt && swift test --filter SpendingDiaryServiceTests 2>&1 | head -30`
Expected: FAIL — `SpendingDiaryService` not found

- [ ] **Step 3: Create SpendingDiaryService**

Follow the HeartbeatService pattern in `LedgeIt/LedgeIt/Services/HeartbeatService.swift`.

```swift
// LedgeIt/LedgeIt/Services/SpendingDiaryService.swift
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
            // Check if completed entry exists
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

            // Delete any pending/failed record for this date
            try await database.db.write { db in
                try SpendingDiaryEntry
                    .filter(SpendingDiaryEntry.Columns.date == date)
                    .deleteAll(db)
            }

            // Insert pending record
            let entry = SpendingDiaryEntry.pending(date: date)
            try await database.db.write { db in
                try entry.save(db)
            }

            // Gather transaction data
            let filter = TransactionFilter(startDate: date, endDate: date)
            let transactions = try await queryService.getTransactions(filter: filter)
            let debitTransactions = transactions.filter { $0.type == "debit" }

            let transactionData = debitTransactions.map {
                (merchant: $0.merchant, amount: $0.amount, category: $0.category)
            }
            let totalSpending = debitTransactions.reduce(0.0) { $0 + $1.amount }
            let primaryCurrency = debitTransactions.first?.currency ?? "TWD"

            // Get month-to-date context
            let monthStart = String(date.prefix(7)) + "-01"
            let monthFilter = TransactionFilter(startDate: monthStart, endDate: date)
            let monthTransactions = try await queryService.getTransactions(filter: monthFilter)
            let monthTotal = monthTransactions.filter { $0.type == "debit" }.reduce(0.0) { $0 + $1.amount }
            let daysInMonth = max(1, dayOfMonth(date))
            let dailyAverage = monthTotal / Double(daysInMonth)

            // Load persona
            let personaId = UserDefaults.standard.string(forKey: "advisorPersonaId") ?? "moderate"
            let customSavings = UserDefaults.standard.double(forKey: "customSavingsTarget")
            let customRisk = UserDefaults.standard.string(forKey: "customRiskLevel") ?? "medium"
            let persona = AdvisorPersona.resolve(
                id: personaId,
                customSavingsTarget: customSavings > 0 ? customSavings : 0.20,
                customRiskLevel: customRisk
            )

            // Determine language
            let language = Locale.current.language.languageCode?.identifier == "zh"
                ? "Traditional Chinese"
                : "English"

            // Build prompts
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

            // Call LLM
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(
                assignment: config.advisor,
                config: config,
                instructions: systemPrompt
            )
            let messages: [LLMMessage] = [.user(userPrompt)]
            let content = try await session.complete(messages: messages, temperature: 0.7, maxTokens: 600)

            // Update to completed
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
        - Write 200-400 characters in \(language)
        - Narrative style, like a real diary entry
        - Mention specific merchants and amounts naturally in the story
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

        for i in 1...lookbackDays {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd LedgeIt && swift test --filter SpendingDiaryServiceTests 2>&1 | tail -20`
Expected: All 4 tests PASS

- [ ] **Step 5: Commit**

```bash
git add LedgeIt/LedgeIt/Services/SpendingDiaryService.swift \
       LedgeIt/Tests/SpendingDiaryServiceTests.swift
git commit -m "feat(diary): add SpendingDiaryService with LLM generation logic"
```

---

## Chunk 3: CalendarView Restructure + DiaryPanelView

### Task 3: DiaryPanelView Component

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Calendar/DiaryPanelView.swift`

- [ ] **Step 1: Create DiaryPanelView**

This is a new SwiftUI view component that displays the diary entry, transactions, and date header for the selected date. Reference the mockup from the design spec (1/3 calendar + 2/3 diary panel).

```swift
// LedgeIt/LedgeIt/Views/Calendar/DiaryPanelView.swift
import SwiftUI
import GRDB

struct DiaryPanelView: View {
    let selectedDate: Date
    let transactions: [Transaction]
    let bills: [CreditCardBill]
    let diaryEntry: SpendingDiaryEntry?

    private var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt
    }

    private var dayTransactions: [Transaction] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateString = fmt.string(from: selectedDate)
        return transactions.filter { $0.transactionDate == dateString }
    }

    private var dayBills: [CreditCardBill] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let dateString = fmt.string(from: selectedDate)
        return bills.filter { $0.dueDate == dateString }
    }

    private var daySpending: Double {
        dayTransactions.filter { $0.type == "debit" }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Date header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dateFormatter.string(from: selectedDate))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(dayTransactions.count) transactions · $\(String(format: "%.0f", daySpending)) spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let entry = diaryEntry {
                    Text(entry.personaId.capitalized)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Bills section (if any)
            if !dayBills.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Bills Due", systemImage: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(dayBills, id: \.id) { bill in
                        HStack {
                            Text(bill.bankName)
                                .font(.callout)
                            Spacer()
                            Text("\(bill.currency) \(String(format: "%.0f", bill.amountDue))")
                                .font(.callout)
                                .foregroundStyle(bill.isPaid ? .green : .orange)
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Compact transactions
            if !dayTransactions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Transactions", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    FlowLayout(spacing: 8) {
                        ForEach(dayTransactions, id: \.id) { tx in
                            HStack(spacing: 4) {
                                Text(tx.merchant)
                                    .font(.caption)
                                Text("$\(String(format: "%.0f", tx.amount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Diary content (main focus)
            VStack(alignment: .leading, spacing: 10) {
                Label("Spending Diary", systemImage: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .textCase(.uppercase)

                if let entry = diaryEntry, entry.status == "completed" {
                    Text(entry.content)
                        .font(.body)
                        .lineSpacing(6)
                } else if let entry = diaryEntry, entry.status == "pending" {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating diary...")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if let entry = diaryEntry, entry.status == "failed" {
                    Text("Diary generation failed. It will retry on next launch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No diary entry for this date.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.15), lineWidth: 1)
            )

            Spacer()
        }
        .padding()
    }
}

// Simple flow layout for compact transaction chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Calendar/DiaryPanelView.swift
git commit -m "feat(diary): add DiaryPanelView component"
```

### Task 4: Restructure CalendarView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/CalendarView.swift`

The current CalendarView is a full-width calendar grid with a selected-day detail section below. We need to restructure it to: compact calendar on the left (~1/3) + DiaryPanelView on the right (~2/3).

- [ ] **Step 1: Add diary state and observation to CalendarView**

Add to the existing `@State` properties at the top of CalendarView (after the existing `bills`/`billCancellable` state around line 10):

```swift
@State private var diaryEntries: [SpendingDiaryEntry] = []
@State private var diaryCancellable: AnyDatabaseCancellable?
```

Add a new observation method (similar to the existing transaction/bill observation pattern around lines 402-433). Add this to the `.onAppear` or observation setup:

```swift
private func observeDiaryEntries() {
    diaryCancellable = ValueObservation
        .tracking { db in
            try SpendingDiaryEntry
                .order(SpendingDiaryEntry.Columns.date.desc)
                .fetchAll(db)
        }
        .start(in: AppDatabase.shared.db, onError: { _ in }, onChange: { entries in
            diaryEntries = entries
        })
}
```

- [ ] **Step 2: Restructure the body layout**

Replace the current vertical layout (calendar grid on top → detail below) with an `HStack`:

```swift
// Main layout: compact calendar (1/3) + diary panel (2/3)
HStack(alignment: .top, spacing: 0) {
    // Left: Compact calendar + month stats
    VStack(spacing: 0) {
        // Existing month header (navigation arrows + month name)
        // Existing calendar grid (keep but make compact)
        // Add: Monthly overview stats below calendar
        monthOverviewStats
    }
    .frame(width: 260)

    Divider()

    // Right: Diary panel
    DiaryPanelView(
        selectedDate: selectedDate,
        transactions: transactions,
        bills: bills,
        diaryEntry: diaryEntryForSelectedDate
    )
}
```

Add a computed property for the selected date's diary entry:

```swift
private var diaryEntryForSelectedDate: SpendingDiaryEntry? {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let dateString = fmt.string(from: selectedDate)
    return diaryEntries.first { $0.date == dateString }
}
```

Add the monthly overview stats view:

```swift
private var monthPrefix: String {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM"
    return fmt.string(from: displayedMonth)
}

private func dateFromString(_ string: String) -> Date? {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt.date(from: string)
}

@ViewBuilder
private var monthOverviewStats: some View {
    let monthTransactions = transactions.filter { tx in
        guard let txDate = dateFromString(tx.transactionDate) else { return false }
        return Calendar.current.isDate(txDate, equalTo: displayedMonth, toGranularity: .month)
    }
    let totalSpending = monthTransactions.filter { $0.type == "debit" }.reduce(0.0) { $0 + $1.amount }
    let diaryCount = diaryEntries.filter { $0.date.hasPrefix(monthPrefix) && $0.status == "completed" }.count
    let daysInMonth = Calendar.current.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    let dailyAvg = totalSpending / Double(max(1, daysInMonth))

    VStack(alignment: .leading, spacing: 6) {
        Text("Monthly Overview")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
        LabeledContent("Total Spending", value: "$\(String(format: "%.0f", totalSpending))")
            .font(.caption)
        LabeledContent("Diary Entries", value: "\(diaryCount)")
            .font(.caption)
        LabeledContent("Daily Avg", value: "$\(String(format: "%.0f", dailyAvg))")
            .font(.caption)
    }
    .padding(12)
}
```

- [ ] **Step 3: Add diary dot indicators on calendar day cells**

In the existing day cell view (around lines 184-243), add a blue dot indicator for dates that have a diary entry. Add below the existing category dots:

```swift
// Blue dot for diary entry
if hasDiaryEntry(for: day) {
    Circle()
        .fill(.blue)
        .frame(width: 4, height: 4)
}
```

Helper:

```swift
private func hasDiaryEntry(for date: Date) -> Bool {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let dateString = fmt.string(from: date)
    return diaryEntries.contains { $0.date == dateString && $0.status == "completed" }
}
```

- [ ] **Step 4: Wire up diary observation in onAppear**

In the existing `.onAppear` block where transaction and bill observations are set up, add:

```swift
observeDiaryEntries()
```

- [ ] **Step 5: Build and verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds with no errors

- [ ] **Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/Views/CalendarView.swift
git commit -m "feat(diary): restructure CalendarView to compact calendar + diary panel layout"
```

---

## Chunk 4: App Integration & Wiring

### Task 5: Launch SpendingDiaryService on App Start

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

- [ ] **Step 1: Add SpendingDiaryService call**

In ContentView's `.task` modifier (around line 153-158), add `SpendingDiaryService.shared.runIfNeeded()` alongside the existing `HeartbeatService.shared.runIfNeeded()`:

```swift
.task {
    await HeartbeatService.shared.runIfNeeded()
    await SpendingDiaryService.shared.runIfNeeded()
    await loadUnreadInsightCount()
    triggerAutoSync()
    startSyncTimer()
}
```

- [ ] **Step 2: Build and verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 3: Run all tests**

Run: `cd LedgeIt && swift test 2>&1 | tail -30`
Expected: All tests pass (existing + new SpendingDiary tests)

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat(diary): wire SpendingDiaryService into app launch"
```

### Task 6: Final Integration Test

- [ ] **Step 1: Run full test suite**

Run: `cd LedgeIt && swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Build the app**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Final commit (if any remaining changes)**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "feat(diary): spending diary feature complete"
```
