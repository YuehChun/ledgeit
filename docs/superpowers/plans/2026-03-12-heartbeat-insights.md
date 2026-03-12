# Heartbeat Insights Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a daily proactive AI heartbeat that generates financial insights on app launch and displays them in a dedicated Insights sidebar page with unread badge.

**Architecture:** New `HeartbeatService` actor triggers once daily on app launch, queries `FinancialQueryService` for financial data, builds a system prompt via `AgentPromptBuilder`, makes a single LLM `complete()` call using the `advisor` model assignment, and saves the result to a new `heartbeat_insights` DB table. A new `InsightsView` displays the last 7 days of insights with unread badge on the sidebar.

**Tech Stack:** Swift 6.2, SwiftUI, GRDB 7.0, SessionFactory (multi-provider LLM), AgentPromptBuilder

---

## File Structure

| File | Responsibility |
|------|---------------|
| **Create:** `LedgeIt/LedgeIt/Models/HeartbeatInsight.swift` | GRDB data model for heartbeat_insights table |
| **Create:** `LedgeIt/LedgeIt/Services/HeartbeatService.swift` | Actor: daily heartbeat trigger + LLM insight generation |
| **Create:** `LedgeIt/LedgeIt/Views/Insights/InsightsView.swift` | UI page showing last 7 days of insights |
| **Modify:** `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift` | Add v16 migration creating heartbeat_insights table |
| **Modify:** `LedgeIt/LedgeIt/Utilities/Localization.swift` | Add insights, insightsNotUpdated, generatingInsights L10n keys |
| **Modify:** `LedgeIt/LedgeIt/Views/ContentView.swift` | Add SidebarItem.insights, badge, heartbeat trigger in .onAppear |

---

## Chunk 1: Data Model + Migration

### Task 1: HeartbeatInsight Model

**Files:**
- Create: `LedgeIt/LedgeIt/Models/HeartbeatInsight.swift`

- [ ] **Step 1: Create HeartbeatInsight model**

```swift
import Foundation
import GRDB

struct HeartbeatInsight: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let date: String
    var content: String
    var status: String
    var isRead: Bool
    let createdAt: String

    static let databaseTableName = "heartbeat_insights"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let content = Column(CodingKeys.content)
        static let status = Column(CodingKeys.status)
        static let isRead = Column(CodingKeys.isRead)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case content
        case status
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    static func pending(date: String) -> HeartbeatInsight {
        HeartbeatInsight(
            id: UUID(),
            date: date,
            content: "",
            status: "pending",
            isRead: false,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
```

- [ ] **Step 2: Verify file compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds (model has no dependencies beyond GRDB)

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Models/HeartbeatInsight.swift
git commit -m "feat(heartbeat): add HeartbeatInsight GRDB model"
```

---

### Task 2: Database Migration v16

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift`

- [ ] **Step 1: Add v16 migration**

After the existing v15 migration block, add:

```swift
// v16: Heartbeat insights table for daily AI-generated financial insights
migrator.registerMigration("v16") { db in
    try db.create(table: "heartbeat_insights") { t in
        t.primaryKey("id", .text)
        t.column("date", .text).notNull().unique()
        t.column("content", .text).notNull().defaults(to: "")
        t.column("status", .text).notNull().defaults(to: "pending")
        t.column("is_read", .integer).notNull().defaults(to: 0)
        t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
    }
}
```

- [ ] **Step 2: Verify build succeeds**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Database/DatabaseMigrations.swift
git commit -m "feat(heartbeat): add v16 migration for heartbeat_insights table"
```

---

## Chunk 2: HeartbeatService

### Task 3: HeartbeatService Actor

**Files:**
- Create: `LedgeIt/LedgeIt/Services/HeartbeatService.swift`

**Reference files (read before implementing):**
- `LedgeIt/LedgeIt/Services/ChatEngine.swift` — actor pattern, AgentPromptBuilder usage
- `LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift` — `makeSession(assignment:config:instructions:)` API
- `LedgeIt/LedgeIt/Services/AIProviderConfigStore.swift` — `AIProviderConfigStore.load()` static method
- `LedgeIt/LedgeIt/Services/FinancialQueryService.swift` — query methods
- `LedgeIt/LedgeIt/Services/Agent/AgentPromptBuilder.swift` — `build(fileManager:financialSnapshot:)` static method

- [ ] **Step 1: Create HeartbeatService**

```swift
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
            var insight = HeartbeatInsight.pending(date: today)
            try await database.db.write { db in
                try insight.insert(db)
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
        let content = try await session.complete(messages: messages)

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
                parts.append("- \(goal.title): \(goal.progress)% progress, target \(goal.targetAmount.map { String(format: "%.0f", $0) } ?? "N/A") (\(goal.status))")
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
```

- [ ] **Step 2: Verify build succeeds**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds. If there are type mismatches with `AccountOverview`, `SpendingSummary`, `CreditCardBill`, or `FinancialGoal` properties, check the actual property names in those models and adjust the `buildUserMessage` and `formatAccountOverview` methods accordingly.

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/HeartbeatService.swift
git commit -m "feat(heartbeat): add HeartbeatService actor with daily LLM insight generation"
```

---

## Chunk 3: UI Integration

### Task 4: Localization Keys

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift`

- [ ] **Step 1: Add L10n keys**

Add these properties to the `L10n` struct, near the existing sidebar-related keys:

```swift
var insights: String { s("Insights", "洞察") }
var insightsNotUpdated: String { s("Not yet updated today", "今日尚未更新") }
var generatingInsights: String { s("Generating insights...", "正在生成洞察...") }
var noInsightsYet: String { s("No insights yet. They will appear after your first app launch with financial data.", "尚無洞察。在您有財務資料後首次啟動應用程式時將會出現。") }
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Utilities/Localization.swift
git commit -m "feat(heartbeat): add L10n keys for insights UI"
```

---

### Task 5: InsightsView

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Insights/InsightsView.swift`

**Reference files:**
- `LedgeIt/LedgeIt/Views/Chat/ChatView.swift` — SwiftUI view pattern with database observation
- `LedgeIt/LedgeIt/Models/HeartbeatInsight.swift` — model to query

- [ ] **Step 1: Create InsightsView**

```swift
import SwiftUI
import GRDB

struct InsightsView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var insights: [HeartbeatInsight] = []
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if insights.isEmpty {
                    emptyState
                } else {
                    ForEach(insights) { insight in
                        insightCard(insight)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(l10n.insights)
        .task {
            await loadInsights()
            await markTodayAsRead()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(l10n.noInsightsYet)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func insightCard(_ insight: HeartbeatInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(formatDate(insight.date))
                    .font(.headline)
                Spacer()
                if !insight.isRead {
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                }
            }

            switch insight.status {
            case "completed":
                Text(insight.content)
                    .font(.body)
                    .textSelection(.enabled)
            case "pending":
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(l10n.generatingInsights)
                        .foregroundStyle(.secondary)
                }
            case "failed":
                Text(l10n.insightsNotUpdated)
                    .foregroundStyle(.secondary)
                    .italic()
            default:
                EmptyView()
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func loadInsights() async {
        do {
            insights = try await database.db.read { db in
                try HeartbeatInsight
                    .order(HeartbeatInsight.Columns.date.desc)
                    .limit(7)
                    .fetchAll(db)
            }
        } catch {
            insights = []
        }
    }

    private func markTodayAsRead() async {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        try? await database.db.write { db in
            try db.execute(
                sql: "UPDATE heartbeat_insights SET is_read = 1 WHERE date = ? AND is_read = 0",
                arguments: [today]
            )
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let inputFmt = DateFormatter()
        inputFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inputFmt.date(from: dateString) else { return dateString }
        let outputFmt = DateFormatter()
        outputFmt.dateStyle = .medium
        return outputFmt.string(from: date)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Insights/InsightsView.swift
git commit -m "feat(heartbeat): add InsightsView with daily insight cards"
```

---

### Task 6: ContentView Integration

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

**Read this file first** to find exact line numbers for:
1. `SidebarItem` enum — add `case insights`
2. `icon` property `switch` — add `case .insights: return "brain.head.profile"`
3. Sidebar `List` — add insights row after chat
4. Detail `switch` — add `case .insights: InsightsView()`
5. `.onAppear` — add heartbeat trigger

- [ ] **Step 1: Add `case insights` to SidebarItem enum**

In the `SidebarItem` enum, add:
```swift
case insights = "Insights"
```

In the `icon` computed property, add:
```swift
case .insights: return "brain.head.profile"
```

- [ ] **Step 2: Add sidebar row**

In the sidebar `List`, after the Chat row, add:

```swift
sidebarRow(l10n.insights, icon: SidebarItem.insights.icon)
    .tag(SidebarItem.insights)
    .badge(unreadInsightCount)
```

- [ ] **Step 3: Add unread count state**

Add a `@State` property to ContentView:

```swift
@State private var unreadInsightCount = 0
```

Add a method to load it:

```swift
private func loadUnreadInsightCount() async {
    do {
        unreadInsightCount = try await AppDatabase.shared.db.read { db in
            try HeartbeatInsight
                .filter(HeartbeatInsight.Columns.isRead == false)
                .fetchCount(db)
        }
    } catch {
        unreadInsightCount = 0
    }
}
```

- [ ] **Step 4: Add InsightsView to detail switch**

In the detail `switch`, add:
```swift
case .insights:
    InsightsView()
```

- [ ] **Step 5: Add heartbeat trigger in .onAppear**

In the existing `.onAppear` block, add after the sync calls:

```swift
Task {
    await HeartbeatService.shared.runIfNeeded()
    await loadUnreadInsightCount()
}
```

- [ ] **Step 6: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 7: Fix any compilation issues**

Check that:
- `SidebarItem` rawValue doesn't conflict
- `.badge()` modifier works on the sidebar row (requires macOS 14+)
- `InsightsView` is accessible from ContentView

- [ ] **Step 8: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat(heartbeat): integrate Insights sidebar item with badge and heartbeat trigger"
```

---

## Chunk 4: Build & Verify

### Task 7: Full Build and Manual Verification

- [ ] **Step 1: Full clean build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds with no errors

- [ ] **Step 2: Build .app bundle**

Run: `cd LedgeIt && bash build.sh 2>&1 | tail -10`
Expected: Build succeeds, .app bundle created

- [ ] **Step 3: Install to /Applications**

Run: `cp -R LedgeIt/build/LedgeIt.app /Applications/LedgeIt.app`

- [ ] **Step 4: Commit all remaining changes**

```bash
git add -A
git commit -m "feat(heartbeat): complete heartbeat insights feature"
```
