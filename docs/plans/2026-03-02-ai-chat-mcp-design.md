# AI Chat + MCP Server Design

## Overview

Add two capabilities to LedgeIt:
1. **AI Chat** — sidebar tab where users query financial data with natural language
2. **MCP Server** — stdio-based server exposing read-only financial tools for third-party AI agents (e.g., Claude Desktop)

Both share a single `FinancialQueryService` layer. Approach A: Shared Query Layer.

## Architecture

```
ChatView (sidebar tab)          MCP Server (stdio)
       │                              │
  ChatEngine                    MCPToolHandler
  (LLM + tool calling)         (maps MCP → queries)
       │                              │
       └──────────┬───────────────────┘
                  │
       FinancialQueryService
       (shared query layer)
                  │
            GRDB / SQLite
```

## Components

### FinancialQueryService

Single source of truth for all data queries. Returns typed Swift structs.

```swift
actor FinancialQueryService {
    func getTransactions(filter: TransactionFilter) -> [Transaction]
    func getTransactionSummary(period: DatePeriod) -> SpendingSummary
    func getTopMerchants(period: DatePeriod, limit: Int) -> [MerchantSummary]
    func getCategoryBreakdown(period: DatePeriod) -> [CategorySummary]
    func getCreditCardBills(filter: BillFilter) -> [CreditCardBill]
    func getUpcomingPayments() -> [CreditCardBill]
    func getGoals(status: GoalStatus?) -> [FinancialGoal]
    func getGoalProgress(goalId: Int64) -> GoalProgress
    func getLatestReport() -> FinancialReport?
    func getReports(period: DatePeriod) -> [FinancialReport]
    func searchTransactions(query: String) -> [Transaction]
    func getAccountOverview() -> AccountOverview
}
```

Filter types: `TransactionFilter`, `DatePeriod`, `BillFilter` — lightweight Sendable structs with optional fields.

Summary types: `SpendingSummary`, `MerchantSummary`, `CategorySummary`, `AccountOverview`, `GoalProgress` — Sendable + Codable structs.

### ChatEngine

Manages conversation and LLM tool-calling loop.

```swift
actor ChatEngine {
    private let queryService: FinancialQueryService
    private let openRouter: OpenRouterService
    private var conversationHistory: [ChatMessage] = []

    func send(message: String) -> AsyncStream<ChatStreamEvent>
}
```

Flow:
1. User sends message
2. Build request: system prompt + history + user message + tool definitions
3. Call OpenRouter with `stream: true` and tool definitions
4. If tool_call → execute via FinancialQueryService → feed result back → continue streaming
5. Stream text response to ChatView

System prompt includes: current date, user's currency, available categories, brief financial snapshot.

Conversation history is in-memory only (no persistence for v1).

### OpenRouterService Extensions

Add to existing `OpenRouterService`:
- `streamComplete()` — returns `AsyncStream<String>` using URLSession bytes streaming
- Tool-calling support — accept `tools` parameter, parse `tool_calls` in response

### MCP Server

Separate executable target in Xcode project. Communicates via stdio.

Tools exposed (all read-only):

| MCP Tool | Maps to |
|----------|---------|
| `get_transactions` | `getTransactions(filter:)` |
| `get_spending_summary` | `getTransactionSummary(period:)` |
| `get_category_breakdown` | `getCategoryBreakdown(period:)` |
| `get_top_merchants` | `getTopMerchants(period:limit:)` |
| `get_upcoming_payments` | `getUpcomingPayments()` |
| `get_goals` | `getGoals(status:)` |
| `search_transactions` | `searchTransactions(query:)` |
| `get_account_overview` | `getAccountOverview()` |

Client config example (Claude Desktop):
```json
{
  "mcpServers": {
    "ledgeit": {
      "command": "/path/to/LedgeItMCP",
      "args": ["--db", "~/Library/Application Support/LedgeIt/db.sqlite"]
    }
  }
}
```

### ChatView UI

- New `SidebarItem.chat` in ContentView, in "Overview" section after Dashboard
- Icon: `bubble.left.and.bubble.right.fill`
- Message list: user right-aligned, assistant left-aligned
- Text input at bottom with send button
- Streaming text renders incrementally with typing indicator
- Errors shown inline as system messages

## New Files

```
LedgeIt/
  Services/
    FinancialQueryService.swift
    ChatEngine.swift
  Models/
    ChatMessage.swift
  Views/
    Chat/
      ChatView.swift
      MessageBubble.swift
  MCP/
    LedgeItMCPServer.swift      (separate target)
    MCPToolHandler.swift
```

## Modified Files

- `OpenRouterService.swift` — add streaming + tool-calling
- `ContentView.swift` — add `.chat` sidebar item
- `Localization.swift` — add chat strings

## Database Changes

None for v1. Chat history is in-memory only.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Query scope | All financial data | Maximize usefulness |
| MCP deployment | In-app (stdio) | Simple, no extra process management |
| Chat UI | Sidebar tab | Consistent with existing navigation |
| LLM backend | Existing OpenRouter | Reuse infrastructure, no new API keys |
| MCP tools | Read-only | Safe for third-party access |
| Streaming | Yes | Better UX for chat |
| Chat persistence | In-memory v1 | YAGNI, add later if needed |
