# AI Chat + MCP Server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an AI chat sidebar tab and a stdio MCP server that both query financial data through a shared FinancialQueryService.

**Architecture:** Shared query layer (`FinancialQueryService`) sits between GRDB and two consumers: `ChatEngine` (in-app LLM with tool calling + streaming) and `MCPToolHandler` (stdio MCP server). Chat UI is a new sidebar tab with streaming message display.

**Tech Stack:** Swift 6.0, SwiftUI, GRDB, OpenRouter API (streaming + function calling), MCP protocol (stdio/JSON-RPC)

**Design doc:** `docs/plans/2026-03-02-ai-chat-mcp-design.md`

---

### Task 1: Query Types — Filter and Summary Structs

**Files:**
- Create: `LedgeIt/LedgeIt/Models/QueryTypes.swift`

**Step 1: Create the query types file**

```swift
import Foundation

// MARK: - Filters

struct TransactionFilter: Sendable {
    var startDate: String?
    var endDate: String?
    var category: String?
    var merchant: String?
    var minAmount: Double?
    var maxAmount: Double?
    var type: String? // debit, credit, transfer
}

struct BillFilter: Sendable {
    var startDate: String?
    var endDate: String?
    var bankName: String?
    var isPaid: Bool?
}

struct DatePeriod: Sendable, Codable {
    var startDate: String
    var endDate: String

    static var thisMonth: DatePeriod {
        let now = Date()
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: start), endDate: fmt.string(from: now))
    }

    static var lastMonth: DatePeriod {
        let now = Date()
        let cal = Calendar.current
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfThisMonth)!
        let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfThisMonth)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: startOfLastMonth), endDate: fmt.string(from: endOfLastMonth))
    }

    static var last30Days: DatePeriod {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: start), endDate: fmt.string(from: now))
    }
}

// MARK: - Summaries

struct SpendingSummary: Sendable, Codable {
    let totalIncome: Double
    let totalExpenses: Double
    let netSavings: Double
    let transactionCount: Int
    let period: DatePeriod
}

struct MerchantSummary: Sendable, Codable {
    let merchant: String
    let totalAmount: Double
    let transactionCount: Int
}

struct CategorySummary: Sendable, Codable {
    let category: String
    let totalAmount: Double
    let transactionCount: Int
    let percentage: Double
}

struct AccountOverview: Sendable, Codable {
    let totalIncome: Double
    let totalExpenses: Double
    let transactionCount: Int
    let topCategories: [CategorySummary]
    let upcomingPayments: Int
    let activeGoals: Int
}

struct GoalProgress: Sendable, Codable {
    let goal: FinancialGoal
    let currentAmount: Double
    let percentComplete: Double
}
```

**Step 2: Build to verify it compiles**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Models/QueryTypes.swift
git commit -m "feat: add query filter and summary types for chat/MCP"
```

---

### Task 2: FinancialQueryService — Shared Query Layer

**Files:**
- Create: `LedgeIt/LedgeIt/Services/FinancialQueryService.swift`

**Step 1: Create the query service**

```swift
import Foundation
import GRDB

actor FinancialQueryService {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Transactions

    func getTransactions(filter: TransactionFilter) async throws -> [Transaction] {
        try await database.db.read { db in
            var query = Transaction
                .filter(Transaction.Columns.deletedAt == nil)

            if let startDate = filter.startDate {
                query = query.filter(Transaction.Columns.transactionDate >= startDate)
            }
            if let endDate = filter.endDate {
                query = query.filter(Transaction.Columns.transactionDate <= endDate)
            }
            if let category = filter.category {
                query = query.filter(Transaction.Columns.category == category)
            }
            if let merchant = filter.merchant {
                query = query.filter(Transaction.Columns.merchant.like("%\(merchant)%"))
            }
            if let minAmount = filter.minAmount {
                query = query.filter(Transaction.Columns.amount >= minAmount)
            }
            if let maxAmount = filter.maxAmount {
                query = query.filter(Transaction.Columns.amount <= maxAmount)
            }
            if let type = filter.type {
                query = query.filter(Transaction.Columns.type == type)
            }

            return try query
                .order(Transaction.Columns.transactionDate.desc)
                .fetchAll(db)
        }
    }

    func getTransactionSummary(period: DatePeriod) async throws -> SpendingSummary {
        try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    COALESCE(SUM(CASE WHEN type = 'credit' THEN amount ELSE 0 END), 0) as total_income,
                    COALESCE(SUM(CASE WHEN type = 'debit' THEN amount ELSE 0 END), 0) as total_expenses,
                    COUNT(*) as tx_count
                FROM transactions
                WHERE deleted_at IS NULL
                    AND transaction_date >= ? AND transaction_date <= ?
                """, arguments: [period.startDate, period.endDate])

            let row = rows.first!
            let income: Double = row["total_income"]
            let expenses: Double = row["total_expenses"]

            return SpendingSummary(
                totalIncome: income,
                totalExpenses: expenses,
                netSavings: income - expenses,
                transactionCount: row["tx_count"],
                period: period
            )
        }
    }

    func getTopMerchants(period: DatePeriod, limit: Int = 10) async throws -> [MerchantSummary] {
        try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT merchant, SUM(amount) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL AND merchant IS NOT NULL
                    AND transaction_date >= ? AND transaction_date <= ?
                GROUP BY merchant
                ORDER BY total DESC
                LIMIT ?
                """, arguments: [period.startDate, period.endDate, limit])

            return rows.map { row in
                MerchantSummary(
                    merchant: row["merchant"],
                    totalAmount: row["total"],
                    transactionCount: row["cnt"]
                )
            }
        }
    }

    func getCategoryBreakdown(period: DatePeriod) async throws -> [CategorySummary] {
        try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(amount) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL AND category IS NOT NULL AND type = 'debit'
                    AND transaction_date >= ? AND transaction_date <= ?
                GROUP BY category
                ORDER BY total DESC
                """, arguments: [period.startDate, period.endDate])

            let grandTotal = rows.reduce(0.0) { $0 + ($1["total"] as Double) }

            return rows.map { row in
                let total: Double = row["total"]
                return CategorySummary(
                    category: row["category"],
                    totalAmount: total,
                    transactionCount: row["cnt"],
                    percentage: grandTotal > 0 ? (total / grandTotal) * 100 : 0
                )
            }
        }
    }

    // MARK: - Credit Card Bills

    func getCreditCardBills(filter: BillFilter) async throws -> [CreditCardBill] {
        try await database.db.read { db in
            var query = CreditCardBill.all()

            if let bankName = filter.bankName {
                query = query.filter(Column("bank_name") == bankName)
            }
            if let startDate = filter.startDate {
                query = query.filter(Column("due_date") >= startDate)
            }
            if let endDate = filter.endDate {
                query = query.filter(Column("due_date") <= endDate)
            }

            return try query.order(Column("due_date").desc).fetchAll(db)
        }
    }

    func getUpcomingPayments() async throws -> [CreditCardBill] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        return try await database.db.read { db in
            try CreditCardBill
                .filter(Column("due_date") >= today)
                .order(Column("due_date").asc)
                .fetchAll(db)
        }
    }

    // MARK: - Goals

    func getGoals(status: String? = nil) async throws -> [FinancialGoal] {
        try await database.db.read { db in
            var query = FinancialGoal.all()
            if let status {
                query = query.filter(Column("status") == status)
            }
            return try query.fetchAll(db)
        }
    }

    // MARK: - Reports

    func getLatestReport() async throws -> FinancialReport? {
        try await database.db.read { db in
            try FinancialReport
                .order(Column("created_at").desc)
                .fetchOne(db)
        }
    }

    func getReports(period: DatePeriod) async throws -> [FinancialReport] {
        try await database.db.read { db in
            try FinancialReport
                .filter(Column("created_at") >= period.startDate)
                .filter(Column("created_at") <= period.endDate)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Search

    func searchTransactions(query: String) async throws -> [Transaction] {
        try await database.db.read { db in
            try Transaction
                .filter(Transaction.Columns.deletedAt == nil)
                .filter(
                    Transaction.Columns.merchant.like("%\(query)%") ||
                    Transaction.Columns.description.like("%\(query)%") ||
                    Transaction.Columns.category.like("%\(query)%")
                )
                .order(Transaction.Columns.transactionDate.desc)
                .limit(50)
                .fetchAll(db)
        }
    }

    // MARK: - Overview

    func getAccountOverview() async throws -> AccountOverview {
        let period = DatePeriod.thisMonth
        let summary = try await getTransactionSummary(period: period)
        let categories = try await getCategoryBreakdown(period: period)
        let upcoming = try await getUpcomingPayments()
        let goals = try await getGoals(status: "accepted")

        return AccountOverview(
            totalIncome: summary.totalIncome,
            totalExpenses: summary.totalExpenses,
            transactionCount: summary.transactionCount,
            topCategories: Array(categories.prefix(5)),
            upcomingPayments: upcoming.count,
            activeGoals: goals.count
        )
    }
}
```

**Step 2: Build to verify**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/FinancialQueryService.swift
git commit -m "feat: add FinancialQueryService shared query layer"
```

---

### Task 3: OpenRouterService — Streaming + Tool Calling

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/OpenRouterService.swift`

**Step 1: Add tool-calling types and streaming to OpenRouterService**

Add these types after the existing `Message` struct (around line 65):

```swift
// MARK: - Tool Calling Types

struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]

    func toDict() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ] as [String: Any]
        ]
    }
}

struct ToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String
}

enum StreamEvent: Sendable {
    case text(String)
    case toolCall(ToolCall)
    case done
    case error(String)
}
```

**Step 2: Add the streaming method**

Add after the existing `complete()` method (after line 258):

```swift
// MARK: - Streaming API

func streamComplete(
    model: String,
    messages: [Message],
    tools: [ToolDefinition] = [],
    temperature: Double = 0.3,
    maxTokens: Int = 4000
) -> AsyncStream<StreamEvent> {
    AsyncStream { continuation in
        Task {
            do {
                guard let url = URL(string: Self.baseURL) else {
                    continuation.yield(.error("Invalid URL"))
                    continuation.finish()
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("https://ledgeit.app", forHTTPHeaderField: "HTTP-Referer")
                request.setValue("LedgeIt", forHTTPHeaderField: "X-Title")
                request.timeoutInterval = 120

                var body: [String: Any] = [
                    "model": model,
                    "messages": messages.map { msg -> [String: Any] in
                        let contentValue: Any
                        switch msg.content {
                        case .text(let str):
                            contentValue = str
                        case .parts(let parts):
                            contentValue = parts.map { part -> [String: Any] in
                                var dict: [String: Any] = ["type": part.type]
                                if let text = part.text { dict["text"] = text }
                                if let imageUrl = part.imageUrl { dict["image_url"] = ["url": imageUrl.url] }
                                return dict
                            }
                        }
                        return ["role": msg.role, "content": contentValue]
                    },
                    "temperature": temperature,
                    "max_tokens": maxTokens,
                    "stream": true
                ]

                if !tools.isEmpty {
                    body["tools"] = tools.map { $0.toDict() }
                }

                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (bytes, response) = try await session.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    continuation.yield(.error("HTTP \(code)"))
                    continuation.finish()
                    return
                }

                var toolCallId = ""
                var toolCallName = ""
                var toolCallArgs = ""

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        if !toolCallName.isEmpty {
                            continuation.yield(.toolCall(ToolCall(
                                id: toolCallId,
                                name: toolCallName,
                                arguments: toolCallArgs
                            )))
                        }
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else {
                        continue
                    }

                    // Text content
                    if let content = delta["content"] as? String {
                        continuation.yield(.text(content))
                    }

                    // Tool calls
                    if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                       let tc = toolCalls.first {
                        if let id = tc["id"] as? String { toolCallId = id }
                        if let fn = tc["function"] as? [String: Any] {
                            if let name = fn["name"] as? String { toolCallName = name }
                            if let args = fn["arguments"] as? String { toolCallArgs += args }
                        }
                    }
                }

                continuation.finish()
            } catch {
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }
    }
}
```

**Step 3: Add assistant message helper for tool results**

Add to the existing Message static methods (around line 63):

```swift
static func assistant(_ text: String) -> Message {
    Message(role: "assistant", content: .text(text))
}

static func toolResult(toolCallId: String, content: String) -> Message {
    Message(role: "tool", content: .text(content))
    // Note: OpenRouter/OpenAI format requires tool_call_id in the message.
    // We'll handle this in ChatEngine by building the raw dict directly.
}
```

**Step 4: Build and verify**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add LedgeIt/LedgeIt/Services/OpenRouterService.swift
git commit -m "feat: add streaming and tool-calling support to OpenRouterService"
```

---

### Task 4: ChatMessage Model + ChatEngine

**Files:**
- Create: `LedgeIt/LedgeIt/Models/ChatMessage.swift`
- Create: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

**Step 1: Create ChatMessage model**

```swift
import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    enum ChatRole: String, Sendable {
        case user
        case assistant
        case system
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, timestamp: Date())
    }

    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, timestamp: Date())
    }

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .system, content: text, timestamp: Date())
    }
}

enum ChatStreamEvent: Sendable {
    case messageStarted(UUID)
    case textDelta(String)
    case toolCallStarted(String)
    case messageComplete
    case error(String)
}
```

**Step 2: Create ChatEngine**

```swift
import Foundation

actor ChatEngine {
    private let queryService: FinancialQueryService
    private var openRouter: OpenRouterService?
    private var history: [OpenRouterService.Message] = []
    private let model: String

    init(
        queryService: FinancialQueryService = FinancialQueryService(),
        model: String = "anthropic/claude-sonnet-4-20250514"
    ) {
        self.queryService = queryService
        self.model = model
    }

    func send(message: String) -> AsyncStream<ChatStreamEvent> {
        AsyncStream { continuation in
            Task {
                do {
                    let router = try self.getOrCreateRouter()

                    // Add user message to history
                    history.append(.user(message))

                    // Build system prompt
                    let systemPrompt = try await buildSystemPrompt()
                    var messages = [OpenRouterService.Message.system(systemPrompt)] + history

                    let messageId = UUID()
                    continuation.yield(.messageStarted(messageId))

                    // Tool-calling loop
                    var fullResponse = ""
                    var maxIterations = 5

                    while maxIterations > 0 {
                        maxIterations -= 1
                        var currentText = ""
                        var toolCall: OpenRouterService.ToolCall?

                        let stream = await router.streamComplete(
                            model: model,
                            messages: messages,
                            tools: toolDefinitions()
                        )

                        for await event in stream {
                            switch event {
                            case .text(let delta):
                                currentText += delta
                                continuation.yield(.textDelta(delta))
                            case .toolCall(let tc):
                                toolCall = tc
                            case .done:
                                break
                            case .error(let msg):
                                continuation.yield(.error(msg))
                                continuation.finish()
                                return
                            }
                        }

                        // If no tool call, we're done
                        guard let tc = toolCall else {
                            fullResponse = currentText
                            break
                        }

                        // Execute tool call
                        continuation.yield(.toolCallStarted(tc.name))
                        let result = try await executeTool(name: tc.name, arguments: tc.arguments)

                        // Add assistant message with tool call + tool result to messages
                        // Build raw messages for tool call flow
                        messages.append(.assistant(currentText.isEmpty ? " " : currentText))
                        messages.append(.user("Tool \(tc.name) returned: \(result)"))
                    }

                    // Save assistant response to history
                    history.append(.assistant(fullResponse))
                    continuation.yield(.messageComplete)
                    continuation.finish()

                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }

    func clearHistory() {
        history = []
    }

    // MARK: - Private

    private func getOrCreateRouter() throws -> OpenRouterService {
        if let router = openRouter { return router }
        let router = try OpenRouterService()
        openRouter = router
        return router
    }

    private func buildSystemPrompt() async throws -> String {
        let overview = try await queryService.getAccountOverview()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"

        return """
        You are a helpful financial assistant for LedgeIt, a personal finance app.
        Today is \(fmt.string(from: Date())).

        Current financial snapshot:
        - This month's income: \(String(format: "%.2f", overview.totalIncome))
        - This month's expenses: \(String(format: "%.2f", overview.totalExpenses))
        - Transaction count: \(overview.transactionCount)
        - Upcoming payments: \(overview.upcomingPayments)
        - Active goals: \(overview.activeGoals)
        - Top spending categories: \(overview.topCategories.map { "\($0.category): \(String(format: "%.2f", $0.totalAmount))" }.joined(separator: ", "))

        Use the available tools to query detailed data when needed. Be concise and helpful.
        Format currency amounts with 2 decimal places.
        Respond in the same language the user uses.
        """
    }

    private func toolDefinitions() -> [OpenRouterService.ToolDefinition] {
        [
            OpenRouterService.ToolDefinition(
                name: "get_transactions",
                description: "Query transactions with optional filters by date, category, merchant, amount, and type",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                        "category": ["type": "string", "description": "Category name"],
                        "merchant": ["type": "string", "description": "Merchant name (partial match)"],
                        "min_amount": ["type": "number", "description": "Minimum amount"],
                        "max_amount": ["type": "number", "description": "Maximum amount"],
                        "type": ["type": "string", "enum": ["debit", "credit", "transfer"]]
                    ] as [String: Any]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_spending_summary",
                description: "Get income/expense summary for a time period",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_category_breakdown",
                description: "Get spending breakdown by category for a time period",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_top_merchants",
                description: "Get top merchants by spending amount",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                        "limit": ["type": "integer", "description": "Max results (default 10)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_upcoming_payments",
                description: "Get upcoming credit card payment due dates",
                parameters: ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_goals",
                description: "Get financial goals, optionally filtered by status",
                parameters: [
                    "type": "object",
                    "properties": [
                        "status": ["type": "string", "enum": ["suggested", "accepted", "completed", "dismissed"]]
                    ] as [String: Any]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "search_transactions",
                description: "Full-text search across merchant, description, and category",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search text"]
                    ] as [String: Any],
                    "required": ["query"]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_account_overview",
                description: "Get a high-level financial overview for the current month",
                parameters: ["type": "object", "properties": [:] as [String: Any]] as [String: Any]
            ),
        ]
    }

    private func executeTool(name: String, arguments: String) async throws -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        switch name {
        case "get_transactions":
            let filter = TransactionFilter(
                startDate: args["start_date"] as? String,
                endDate: args["end_date"] as? String,
                category: args["category"] as? String,
                merchant: args["merchant"] as? String,
                minAmount: args["min_amount"] as? Double,
                maxAmount: args["max_amount"] as? Double,
                type: args["type"] as? String
            )
            let txs = try await queryService.getTransactions(filter: filter)
            let summaries = txs.prefix(20).map {
                "\($0.transactionDate ?? "?"): \($0.merchant ?? "Unknown") - \(String(format: "%.2f", $0.amount)) \($0.currency) [\($0.category ?? "uncategorized")]"
            }
            return "Found \(txs.count) transactions.\n" + summaries.joined(separator: "\n")

        case "get_spending_summary":
            let period = DatePeriod(
                startDate: args["start_date"] as? String ?? "",
                endDate: args["end_date"] as? String ?? ""
            )
            let summary = try await queryService.getTransactionSummary(period: period)
            return String(data: try encoder.encode(summary), encoding: .utf8) ?? "{}"

        case "get_category_breakdown":
            let period = DatePeriod(
                startDate: args["start_date"] as? String ?? "",
                endDate: args["end_date"] as? String ?? ""
            )
            let categories = try await queryService.getCategoryBreakdown(period: period)
            return String(data: try encoder.encode(categories), encoding: .utf8) ?? "[]"

        case "get_top_merchants":
            let period = DatePeriod(
                startDate: args["start_date"] as? String ?? "",
                endDate: args["end_date"] as? String ?? ""
            )
            let limit = args["limit"] as? Int ?? 10
            let merchants = try await queryService.getTopMerchants(period: period, limit: limit)
            return String(data: try encoder.encode(merchants), encoding: .utf8) ?? "[]"

        case "get_upcoming_payments":
            let bills = try await queryService.getUpcomingPayments()
            if bills.isEmpty { return "No upcoming payments." }
            return bills.map { "Due: \($0.dueDate ?? "?") - \($0.bankName ?? "Unknown") \(String(format: "%.2f", $0.amountDue ?? 0))" }.joined(separator: "\n")

        case "get_goals":
            let status = args["status"] as? String
            let goals = try await queryService.getGoals(status: status)
            return goals.map { "\($0.title ?? "Untitled") [\($0.status ?? "?")] - \($0.category ?? "")" }.joined(separator: "\n")

        case "search_transactions":
            let query = args["query"] as? String ?? ""
            let txs = try await queryService.searchTransactions(query: query)
            let summaries = txs.prefix(20).map {
                "\($0.transactionDate ?? "?"): \($0.merchant ?? "Unknown") - \(String(format: "%.2f", $0.amount)) \($0.currency)"
            }
            return "Found \(txs.count) results.\n" + summaries.joined(separator: "\n")

        case "get_account_overview":
            let overview = try await queryService.getAccountOverview()
            return String(data: try encoder.encode(overview), encoding: .utf8) ?? "{}"

        default:
            return "Unknown tool: \(name)"
        }
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (may need minor fixes for CreditCardBill/FinancialGoal field names — adjust to match actual model properties)

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Models/ChatMessage.swift LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "feat: add ChatEngine with LLM tool-calling loop"
```

---

### Task 5: ChatView UI

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Chat/ChatView.swift`
- Create: `LedgeIt/LedgeIt/Views/Chat/MessageBubble.swift`

**Step 1: Create MessageBubble component**

```swift
import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(message.content)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(LocalizedStringKey(message.content))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            message.role == .user
                                ? Color.accentColor
                                : Color(.controlBackgroundColor)
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }
}
```

**Step 2: Create ChatView**

```swift
import SwiftUI

struct ChatView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamingMessageId: UUID?
    @State private var chatEngine = ChatEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(l10n.chatTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if !messages.isEmpty {
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.clearChat)
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField(l10n.chatPlaceholder, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                            sendMessage()
                        }
                    }

                Button(action: sendMessage) {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
                                ? .secondary : .accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(l10n.chatEmptyTitle)
                .font(.title3)
                .fontWeight(.medium)
            Text(l10n.chatEmptyDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true

        Task {
            let assistantId = UUID()
            let assistantMessage = ChatMessage(id: assistantId, role: .assistant, content: "", timestamp: Date())
            messages.append(assistantMessage)
            streamingMessageId = assistantId

            let stream = await chatEngine.send(message: text)

            for await event in stream {
                await MainActor.run {
                    switch event {
                    case .messageStarted:
                        break
                    case .textDelta(let delta):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx].content += delta
                        }
                    case .toolCallStarted(let name):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            if messages[idx].content.isEmpty {
                                messages[idx].content = "Looking up \(name)..."
                            }
                        }
                    case .messageComplete:
                        break
                    case .error(let msg):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx] = .system("Error: \(msg)")
                        }
                    }
                }
            }

            await MainActor.run {
                isStreaming = false
                streamingMessageId = nil
            }
        }
    }

    private func clearChat() {
        messages = []
        Task { await chatEngine.clearHistory() }
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Chat/
git commit -m "feat: add ChatView with streaming message UI"
```

---

### Task 6: Sidebar Integration + L10n

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:4-32` (SidebarItem enum)
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:46-74` (sidebar list)
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:95-122` (detail switch)
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift` (add chat strings)

**Step 1: Add chat to SidebarItem enum**

In `ContentView.swift`, add `case chat = "Chat"` after `case dashboard`:

```swift
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case chat = "Chat"
    // ... rest unchanged
```

Add icon in the `icon` computed property:

```swift
case .chat: return "bubble.left.and.bubble.right.fill"
```

**Step 2: Add chat to sidebar list**

In the sidebar `Section(l10n.overview)`, add after dashboard row:

```swift
sidebarRow(l10n.chat, icon: SidebarItem.chat.icon)
    .tag(SidebarItem.chat)
```

**Step 3: Add chat to detail switch**

In the `switch selectedItem` block, add after `.dashboard`:

```swift
case .chat:
    ChatView()
```

**Step 4: Add L10n strings**

In `Localization.swift`, add a new section:

```swift
// MARK: - Chat

var chat: String { s("Chat", "聊天") }
var chatTitle: String { s("Financial Assistant", "財務助手") }
var chatPlaceholder: String { s("Ask about your finances...", "詢問您的財務狀況...") }
var chatEmptyTitle: String { s("Ask Me Anything", "隨時提問") }
var chatEmptyDescription: String { s("Ask about your spending, transactions, goals, or upcoming payments.", "詢問您的消費、交易、目標或即將到期的付款。") }
var clearChat: String { s("Clear conversation", "清除對話") }
```

**Step 5: Build and verify**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Manual test**

Launch the app. Verify:
- "Chat" appears in sidebar after Dashboard
- Clicking it shows empty state with assistant icon
- Type a message and verify streaming response works

**Step 7: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift LedgeIt/LedgeIt/Utilities/Localization.swift
git commit -m "feat: integrate chat into sidebar with bilingual strings"
```

---

### Task 7: MCP Server — Standalone Executable

**Files:**
- Create: `LedgeIt/LedgeIt/MCP/MCPServer.swift`
- Create: `LedgeIt/LedgeIt/MCP/MCPToolHandler.swift`

**Step 1: Create MCPToolHandler**

This maps MCP tool requests to `FinancialQueryService`. It reads JSON-RPC requests from stdin and writes responses to stdout.

```swift
import Foundation
import GRDB

struct MCPToolHandler: Sendable {
    let queryService: FinancialQueryService

    func handleToolCall(name: String, arguments: [String: Any]) async throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        switch name {
        case "get_transactions":
            let filter = TransactionFilter(
                startDate: arguments["start_date"] as? String,
                endDate: arguments["end_date"] as? String,
                category: arguments["category"] as? String,
                merchant: arguments["merchant"] as? String,
                minAmount: arguments["min_amount"] as? Double,
                maxAmount: arguments["max_amount"] as? Double,
                type: arguments["type"] as? String
            )
            let txs = try await queryService.getTransactions(filter: filter)
            let items = txs.prefix(50).map { tx -> [String: Any] in
                var dict: [String: Any] = [
                    "amount": tx.amount,
                    "currency": tx.currency
                ]
                if let d = tx.transactionDate { dict["date"] = d }
                if let m = tx.merchant { dict["merchant"] = m }
                if let c = tx.category { dict["category"] = c }
                if let t = tx.type { dict["type"] = t }
                if let desc = tx.description { dict["description"] = desc }
                return dict
            }
            return String(data: try JSONSerialization.data(withJSONObject: ["count": txs.count, "transactions": items]), encoding: .utf8) ?? "{}"

        case "get_spending_summary":
            let period = DatePeriod(
                startDate: arguments["start_date"] as? String ?? "",
                endDate: arguments["end_date"] as? String ?? ""
            )
            let summary = try await queryService.getTransactionSummary(period: period)
            return String(data: try encoder.encode(summary), encoding: .utf8) ?? "{}"

        case "get_category_breakdown":
            let period = DatePeriod(
                startDate: arguments["start_date"] as? String ?? "",
                endDate: arguments["end_date"] as? String ?? ""
            )
            let categories = try await queryService.getCategoryBreakdown(period: period)
            return String(data: try encoder.encode(categories), encoding: .utf8) ?? "[]"

        case "get_top_merchants":
            let period = DatePeriod(
                startDate: arguments["start_date"] as? String ?? "",
                endDate: arguments["end_date"] as? String ?? ""
            )
            let limit = arguments["limit"] as? Int ?? 10
            let merchants = try await queryService.getTopMerchants(period: period, limit: limit)
            return String(data: try encoder.encode(merchants), encoding: .utf8) ?? "[]"

        case "get_upcoming_payments":
            let bills = try await queryService.getUpcomingPayments()
            let items = bills.map { bill -> [String: Any] in
                var dict: [String: Any] = [:]
                if let d = bill.dueDate { dict["due_date"] = d }
                if let b = bill.bankName { dict["bank_name"] = b }
                if let a = bill.amountDue { dict["amount_due"] = a }
                return dict
            }
            return String(data: try JSONSerialization.data(withJSONObject: items), encoding: .utf8) ?? "[]"

        case "get_goals":
            let status = arguments["status"] as? String
            let goals = try await queryService.getGoals(status: status)
            let items = goals.map { goal -> [String: Any] in
                var dict: [String: Any] = [:]
                if let t = goal.title { dict["title"] = t }
                if let s = goal.status { dict["status"] = s }
                if let c = goal.category { dict["category"] = c }
                if let ta = goal.targetAmount { dict["target_amount"] = ta }
                return dict
            }
            return String(data: try JSONSerialization.data(withJSONObject: items), encoding: .utf8) ?? "[]"

        case "search_transactions":
            let query = arguments["query"] as? String ?? ""
            let txs = try await queryService.searchTransactions(query: query)
            let items = txs.prefix(20).map { tx -> [String: Any] in
                var dict: [String: Any] = ["amount": tx.amount, "currency": tx.currency]
                if let d = tx.transactionDate { dict["date"] = d }
                if let m = tx.merchant { dict["merchant"] = m }
                if let c = tx.category { dict["category"] = c }
                return dict
            }
            return String(data: try JSONSerialization.data(withJSONObject: ["count": txs.count, "results": items]), encoding: .utf8) ?? "{}"

        case "get_account_overview":
            let overview = try await queryService.getAccountOverview()
            return String(data: try encoder.encode(overview), encoding: .utf8) ?? "{}"

        default:
            return "{\"error\": \"Unknown tool: \(name)\"}"
        }
    }

    func toolDefinitions() -> [[String: Any]] {
        [
            mcpTool("get_transactions", "Query transactions with optional date, category, merchant, amount, and type filters", [
                "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                "category": ["type": "string", "description": "Category name"],
                "merchant": ["type": "string", "description": "Merchant name (partial match)"],
                "min_amount": ["type": "number", "description": "Minimum amount"],
                "max_amount": ["type": "number", "description": "Maximum amount"],
                "type": ["type": "string", "enum": ["debit", "credit", "transfer"], "description": "Transaction type"],
            ]),
            mcpTool("get_spending_summary", "Get income/expense totals for a date range", [
                "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
            ], required: ["start_date", "end_date"]),
            mcpTool("get_category_breakdown", "Get spending by category for a date range", [
                "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
            ], required: ["start_date", "end_date"]),
            mcpTool("get_top_merchants", "Get top merchants by total spend", [
                "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                "limit": ["type": "integer", "description": "Max results (default 10)"],
            ], required: ["start_date", "end_date"]),
            mcpTool("get_upcoming_payments", "Get upcoming credit card payments", [:]),
            mcpTool("get_goals", "Get financial goals optionally filtered by status", [
                "status": ["type": "string", "enum": ["suggested", "accepted", "completed", "dismissed"]],
            ]),
            mcpTool("search_transactions", "Search transactions by merchant, description, or category", [
                "query": ["type": "string", "description": "Search text"],
            ], required: ["query"]),
            mcpTool("get_account_overview", "Get high-level financial overview for the current month", [:]),
        ]
    }

    private func mcpTool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty {
            schema["required"] = required
        }
        return [
            "name": name,
            "description": description,
            "inputSchema": schema,
        ]
    }
}
```

**Step 2: Create MCPServer**

This is the stdio JSON-RPC server implementing MCP protocol.

```swift
import Foundation
import GRDB

@main
struct MCPServer {
    static func main() async {
        // Parse --db argument
        let args = CommandLine.arguments
        var dbPath: String?
        for (i, arg) in args.enumerated() {
            if arg == "--db" && i + 1 < args.count {
                dbPath = (args[i + 1] as NSString).expandingTildeInPath
            }
        }

        guard let path = dbPath else {
            writeError("Usage: LedgeItMCP --db <path-to-db.sqlite>")
            return
        }

        // Open database read-only
        guard let dbQueue = try? DatabaseQueue(path: path) else {
            writeError("Failed to open database at \(path)")
            return
        }

        let database = AppDatabase(dbQueue)
        let queryService = FinancialQueryService(database: database)
        let handler = MCPToolHandler(queryService: queryService)

        // Read JSON-RPC from stdin line by line
        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let id = json["id"]
            let method = json["method"] as? String ?? ""

            switch method {
            case "initialize":
                let response: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id as Any,
                    "result": [
                        "protocolVersion": "2024-11-05",
                        "capabilities": [
                            "tools": [:] as [String: Any]
                        ],
                        "serverInfo": [
                            "name": "LedgeIt",
                            "version": "1.0.0"
                        ]
                    ] as [String: Any]
                ]
                writeJSON(response)

            case "notifications/initialized":
                break // No response needed

            case "tools/list":
                let tools = handler.toolDefinitions()
                let response: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id as Any,
                    "result": ["tools": tools]
                ]
                writeJSON(response)

            case "tools/call":
                let params = json["params"] as? [String: Any] ?? [:]
                let toolName = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]

                do {
                    let result = try await handler.handleToolCall(name: toolName, arguments: arguments)
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id as Any,
                        "result": [
                            "content": [
                                ["type": "text", "text": result]
                            ]
                        ] as [String: Any]
                    ]
                    writeJSON(response)
                } catch {
                    let response: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id as Any,
                        "result": [
                            "content": [
                                ["type": "text", "text": "Error: \(error.localizedDescription)"]
                            ],
                            "isError": true
                        ] as [String: Any]
                    ]
                    writeJSON(response)
                }

            default:
                let response: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": id as Any,
                    "error": [
                        "code": -32601,
                        "message": "Method not found: \(method)"
                    ] as [String: Any]
                ]
                writeJSON(response)
            }
        }
    }

    private static func writeJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        print(str)
        fflush(stdout)
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
```

**Note:** The MCP server needs to be a separate Xcode target or a Swift Package executable. For v1, we can include it in the main app target and gate it behind a command-line flag, OR create a separate target in the Xcode project. During implementation, check which approach compiles cleanly — the `@main` attribute will conflict with the SwiftUI `@main App` struct, so a separate target is required.

**Step 3: Build and verify**

The MCP server needs a separate target. Add a new "Command Line Tool" target in the Xcode project named "LedgeItMCP", sharing the same source files for models, database, and query service.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/MCP/
git commit -m "feat: add MCP stdio server with financial query tools"
```

---

### Task 8: Final Integration + Manual Testing

**Files:**
- No new files

**Step 1: Build the full app**

Run: `xcodebuild build -project LedgeIt/LedgeIt.xcodeproj -scheme LedgeIt -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 2: Manual testing checklist**

- [ ] App launches, Chat appears in sidebar
- [ ] Empty state shows correctly
- [ ] Type "What did I spend this month?" → streaming response with tool call
- [ ] Type "Show my top merchants" → uses get_top_merchants tool
- [ ] Type "Do I have any upcoming payments?" → uses get_upcoming_payments
- [ ] Clear chat button works
- [ ] Language toggle (en/zh) updates chat strings
- [ ] Errors display inline when OpenRouter key is missing

**Step 3: Test MCP server**

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./LedgeItMCP --db ~/Library/Application\ Support/LedgeIt/db.sqlite
```
Expected: JSON response with serverInfo

**Step 4: Final commit**

```bash
git add -A
git commit -m "feat: complete AI chat + MCP server integration"
```
