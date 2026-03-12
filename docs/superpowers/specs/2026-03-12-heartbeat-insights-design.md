# Heartbeat Insights — Design Spec

## Goal

Add a proactive AI heartbeat to LedgeIt that runs once daily on app launch, generates financial insights and reminders, and displays them in a dedicated Insights page in the sidebar.

## Context

LedgeIt already has an AI agent memory system (PERSONA.md, USER.md, daily logs, long-term memory) and a comprehensive `FinancialQueryService`. The heartbeat leverages these to let the AI autonomously decide what's worth highlighting each day — upcoming bills, spending anomalies, goal progress, patterns, etc.

## Decisions

| Question | Decision |
|----------|----------|
| Trigger timing | App launch (in `.onAppear`), once per day max |
| Analysis content | AI autonomously decides (given full financial snapshot + memory) |
| Display location | New "Insights" sidebar item with dedicated page + unread badge |
| Failure handling | Show localized "Not yet updated today" in Insights page |
| Architecture | Independent HeartbeatService with single LLM call (not ChatEngine) |
| Model assignment | Uses `advisor` model assignment |

## Data Model

New `heartbeat_insights` table (DB migration v16):

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT | UUID primary key |
| date | TEXT | YYYY-MM-DD, unique constraint (one per day) |
| content | TEXT | AI-generated Markdown insights |
| status | TEXT | "pending", "completed", "failed" |
| is_read | INTEGER | Default 0 (false), controls sidebar badge |
| created_at | TEXT | ISO 8601 timestamp |

Swift model: `HeartbeatInsight` conforming to `Sendable, FetchableRecord, PersistableRecord, Codable, Identifiable`.

Requires `CodingKeys` enum for snake_case mapping (`isRead` -> `is_read`, `createdAt` -> `created_at`).

### Data Retention

On each `runIfNeeded()` call, delete records older than 30 days to prevent unbounded growth.

## HeartbeatService

New file: `Services/HeartbeatService.swift`

```swift
actor HeartbeatService {
    static let shared = HeartbeatService(
        db: .shared,
        configStore: .shared,
        queryService: FinancialQueryService(database: .shared),
        agentFileManager: AgentFileManager()
    )

    private let db: AppDatabase
    private let configStore: AIProviderConfigStore
    private let queryService: FinancialQueryService
    private let agentFileManager: AgentFileManager

    /// Check if today's insight exists; if not, generate one.
    func runIfNeeded() async

    /// Generate insight via single LLM call.
    func generateInsight() async throws -> String
}
```

### Flow: `runIfNeeded()`

1. Delete records older than 30 days
2. Query DB for today's `heartbeat_insights` record with status `completed` → if exists, return early
3. Insert a new record with `status: "pending"`
4. Call `generateInsight()`
5. On success → update record to `status: "completed"`, write AI response to `content`
6. On failure → update record to `status: "failed"`

### Flow: `generateInsight()`

1. `AgentPromptBuilder.build(fileManager:financialSnapshot:)` → system prompt with persona, user profile, memory
2. Query `FinancialQueryService`:
   - `getAccountOverview()` — high-level snapshot
   - `getTransactionSummary(period:)` — this month vs last month
   - `getUpcomingPayments()` — unpaid bills
   - `getGoals(status:)` — active goals
3. Compose user message: financial data + instruction for AI to decide what to highlight
4. `SessionFactory.makeSession(assignment: config.advisor, config: config, instructions: systemPrompt)` to create LLM session
5. Single `session.complete()` call (non-streaming)
6. Return AI response text

### System Prompt Assembly

Reuses `AgentPromptBuilder.build()` which already includes:
- PERSONA.md (advisor identity, tone, boundary rules)
- USER.md (user preferences, language)
- Active context + daily logs
- Long-term memory
- Financial snapshot

### User Message Template

```
Here is today's financial data. Based on this data and your memory of the user,
provide today's key insights and reminders. Focus on what's most important —
upcoming deadlines, unusual spending, goal progress, or patterns worth noting.
Be concise and actionable. Respond in the user's preferred language.

## Account Overview
{accountOverview}

## This Month vs Last Month
{currentMonth}
{lastMonth}

## Upcoming Payments
{upcomingPayments}

## Active Goals
{activeGoals}
```

## Insights UI

### New: `Views/Insights/InsightsView.swift`

- Displays the last 7 days of heartbeat insights from DB
- Each day's insight: date header + Markdown content
- States:
  - `completed` → render content
  - `pending` → `ProgressView` + "Generating insights..."
  - `failed` → gray text (localized via `L10n`: "Not yet updated today")
  - No record → nothing shown for that day
- On appear: mark today's insight as `isRead = true`

### Modified: `ContentView.swift`

**SidebarItem enum addition:**
- Add `case insights` to `SidebarItem` enum
- Add `icon` property return: `"brain.head.profile"` (SF Symbol)
- Add `InsightsView()` case in the detail `switch`
- Add `l10n.insights` localization key
- Place in sidebar below Chat

**Badge:**
- Use GRDB `ValueObservation` to reactively observe unread count (`is_read == false`)
- Render via `.badge(unreadCount)` modifier on sidebar row

**Trigger:**
- In existing `.onAppear` modifier, after sync setup:
  ```swift
  Task {
      await HeartbeatService.shared.runIfNeeded()
  }
  ```

## File Changes

### New Files
| File | Purpose |
|------|---------|
| `Models/HeartbeatInsight.swift` | Data model (GRDB, Sendable, CodingKeys) |
| `Services/HeartbeatService.swift` | Core heartbeat logic (actor) |
| `Views/Insights/InsightsView.swift` | Insights page UI |

### Modified Files
| File | Change |
|------|--------|
| `Database/DatabaseMigrations.swift` | Add v16 migration for `heartbeat_insights` table |
| `Views/ContentView.swift` | Add `SidebarItem.insights` case, badge via ValueObservation, trigger `runIfNeeded()` in `.onAppear` |
| `Utilities/Localization.swift` | Add `insights`, `insightsNotUpdated`, `generatingInsights` keys |

### Untouched
- ChatEngine, ChatView, AgentFileManager, AgentPromptBuilder — fully reused, not modified

## Error Handling

- LLM call failure (network, quota, no provider configured) → catch error, update status to `failed`
- No financial data (new user, no transactions) → AI receives empty snapshot, will generate a generic welcome insight or skip gracefully
- DB write failure → log error, do not crash

## Future Extensions (not in scope)

- macOS notifications for urgent insights (overdue bills)
- Heartbeat writing to agent memory via tool calling
- Configurable heartbeat frequency in Settings
- Heartbeat trigger after sync completes (event-driven)
