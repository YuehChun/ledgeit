import Foundation
import os.log

private let chatLogger = Logger(subsystem: "com.ledgeit.app", category: "ChatEngine")

actor ChatEngine {
    private let queryService: FinancialQueryService
    private let embeddingService: EmbeddingService
    private var openRouter: OpenRouterService?
    private var conversationHistory: [OpenRouterService.Message] = []

    private var model: String { PFMConfig.chatModel }
    private let maxToolIterations = 5

    init(
        queryService: FinancialQueryService = FinancialQueryService(),
        embeddingService: EmbeddingService = EmbeddingService()
    ) {
        self.queryService = queryService
        self.embeddingService = embeddingService
    }

    // MARK: - Public API

    func send(message: String) -> AsyncStream<ChatStreamEvent> {
        let messageId = UUID()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.yield(.error("ChatEngine deallocated"))
                    continuation.finish()
                    return
                }
                await self.processMessage(message, messageId: messageId, continuation: continuation)
            }
        }
    }

    func clearHistory() {
        conversationHistory.removeAll()
    }

    func restoreMessage(role: String, content: String) {
        if role == "user" {
            conversationHistory.append(.user(content))
        } else {
            conversationHistory.append(.assistant(content))
        }
    }

    // MARK: - Message Processing

    private func processMessage(
        _ message: String,
        messageId: UUID,
        continuation: AsyncStream<ChatStreamEvent>.Continuation
    ) async {
        do {
            chatLogger.debug("User: \(message)")
            // Ensure OpenRouterService is initialized
            let router = try getOrCreateOpenRouter()

            // Add user message to history
            conversationHistory.append(.user(message))

            // Build system prompt with current financial snapshot
            let systemPrompt = try await buildSystemPrompt()

            // Signal message started
            continuation.yield(.messageStarted(messageId))

            // Build raw messages array: system + conversation history
            var rawMessages: [[String: Any]] = [["role": "system", "content": systemPrompt]]
            for msg in conversationHistory {
                switch msg.content {
                case .text(let str):
                    rawMessages.append(["role": msg.role, "content": str])
                case .parts:
                    rawMessages.append(["role": msg.role, "content": ""])
                }
            }

            var fullResponse = ""

            // Tool-calling loop
            for _ in 0..<maxToolIterations {
                var iterationText = ""
                var toolCall: OpenRouterService.ToolCall?

                let routerApiKey = await router.apiKey
                let routerSession = await router.session
                let stream = OpenRouterService.performStreamComplete(
                    model: model,
                    rawMessages: rawMessages,
                    tools: toolDefinitions,
                    apiKey: routerApiKey,
                    session: routerSession
                )

                for await event in stream {
                    switch event {
                    case .text(let text):
                        iterationText += text
                        continuation.yield(.textDelta(text))
                    case .toolCall(let tc):
                        toolCall = tc
                    case .done:
                        break
                    case .error(let errorMsg):
                        continuation.yield(.error(errorMsg))
                        continuation.finish()
                        return
                    }
                }

                // If we got text, accumulate it
                fullResponse += iterationText

                // If no tool call, we are done
                guard let tc = toolCall else {
                    chatLogger.debug("No tool call in this iteration, done.")
                    break
                }
                chatLogger.debug("Tool call: \(tc.name)")

                // Execute tool call
                continuation.yield(.toolCallStarted(tc.name))

                let toolResult: String
                do {
                    toolResult = try await executeTool(name: tc.name, arguments: tc.arguments)
                } catch {
                    toolResult = "Error executing tool \(tc.name): \(error.localizedDescription)"
                }

                // Append assistant message WITH tool_calls metadata
                var assistantMsg: [String: Any] = ["role": "assistant"]
                if !iterationText.isEmpty {
                    assistantMsg["content"] = iterationText
                }
                assistantMsg["tool_calls"] = [[
                    "id": tc.id,
                    "type": "function",
                    "function": ["name": tc.name, "arguments": tc.arguments]
                ] as [String: Any]]
                rawMessages.append(assistantMsg)

                // Append tool result with proper role and tool_call_id
                rawMessages.append([
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": toolResult
                ])
            }

            // Save the full assistant response to conversation history
            if !fullResponse.isEmpty {
                conversationHistory.append(.assistant(fullResponse))
            }

            continuation.yield(.messageComplete)
            continuation.finish()
        } catch {
            continuation.yield(.error(error.localizedDescription))
            continuation.finish()
        }
    }

    // MARK: - OpenRouter Init

    private func getOrCreateOpenRouter() throws -> OpenRouterService {
        if let existing = openRouter {
            return existing
        }
        let service = try OpenRouterService()
        openRouter = service
        return service
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() async throws -> String {
        let overview = try await queryService.getAccountOverview()

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        let categoryList = overview.topCategories
            .map { "\($0.category): \(String(format: "%.2f", $0.totalAmount)) (\(String(format: "%.1f", $0.percentage))%)" }
            .joined(separator: ", ")

        return """
            You are a helpful financial assistant for LedgeIt, a personal finance app.
            Today is \(today).

            Current financial snapshot:
            - This month's income: \(String(format: "%.2f", overview.totalIncome))
            - This month's expenses: \(String(format: "%.2f", overview.totalExpenses))
            - Transaction count: \(overview.transactionCount)
            - Upcoming payments: \(overview.upcomingPayments)
            - Active goals: \(overview.activeGoals)
            - Top spending categories: \(categoryList.isEmpty ? "None" : categoryList)

            ## Interaction Guidelines
            1. **Understand intent first**: When the user asks a question, briefly confirm your understanding of what they want before diving into data. For example: "Let me look up your dining spending this month..." or "I'll check your upcoming payments..."
            2. **Rephrase when ambiguous**: If the user's request is vague or could mean multiple things, rephrase their intent and ask for confirmation before querying data. For example: "It sounds like you want to compare this month's spending to last month — is that right?"
            3. **Summarize findings**: After retrieving data, provide a clear summary with key insights, not just raw numbers.
            4. **Proactive suggestions**: When you notice patterns (overspending, upcoming bills, goal progress), mention them.

            ## Formatting
            - Use the available tools to query detailed data when needed.
            - Be concise and helpful.
            - Format currency amounts with 2 decimal places.
            - Respond in the same language the user uses.

            ## Tool Selection
            - Use `semantic_search` when the user asks about specific merchants, brands, products, or conceptual spending categories. It uses hybrid search (vector + keyword).
            - CRITICAL: Transaction data is stored in BOTH English and Chinese. When searching, ALWAYS provide BOTH the original term AND its translation in the `queries` array. Examples:
              - User asks "寶可夢" → queries: ["寶可夢", "Pokémon", "Pokemon"]
              - User asks "星巴克" → queries: ["星巴克", "Starbucks"]
              - User asks "日本旅遊" → queries: ["日本", "Japan", "JR", "虎航", "Tigerair"]
              - User asks "Uber Eats" → queries: ["Uber Eats", "外送"]
            - Use `get_transactions` or `search_transactions` when the user specifies exact filters (date range, amount range, transaction type).
            - You can combine both: use semantic_search first to discover relevant transactions, then get_transactions for precise filtering.
            """
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [OpenRouterService.ToolDefinition] {
        [
            OpenRouterService.ToolDefinition(
                name: "get_transactions",
                description: "Get a list of transactions with optional filters",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                        "category": ["type": "string", "description": "Filter by category"],
                        "merchant": ["type": "string", "description": "Filter by merchant name"],
                        "min_amount": ["type": "number", "description": "Minimum transaction amount"],
                        "max_amount": ["type": "number", "description": "Maximum transaction amount"],
                        "type": ["type": "string", "description": "Transaction type: debit, credit, or transfer"]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_spending_summary",
                description: "Get a spending summary for a date range including income, expenses, and net savings",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_category_breakdown",
                description: "Get spending breakdown by category for a date range",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_top_merchants",
                description: "Get top merchants by spending amount for a date range",
                parameters: [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (yyyy-MM-dd)"],
                        "end_date": ["type": "string", "description": "End date (yyyy-MM-dd)"],
                        "limit": ["type": "integer", "description": "Max number of merchants to return (default 10)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_upcoming_payments",
                description: "Get all unpaid credit card bills (including overdue). Use when user asks about credit card payments, due dates, or bills.",
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_goals",
                description: "Get financial goals, optionally filtered by status",
                parameters: [
                    "type": "object",
                    "properties": [
                        "status": ["type": "string", "description": "Filter by status: suggested, accepted, completed, dismissed"]
                    ] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "search_transactions",
                description: "Search transactions by merchant, description, or category keyword",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search keyword"]
                    ] as [String: Any],
                    "required": ["query"] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "get_account_overview",
                description: "Get a high-level overview of the account including income, expenses, upcoming payments, and goals",
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            OpenRouterService.ToolDefinition(
                name: "semantic_search",
                description: "Search transactions using hybrid search (semantic + keyword). IMPORTANT: Always provide BOTH the original term AND its English/Chinese translation in the queries array for cross-language matching.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "queries": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Search queries - include both original and translated terms (e.g., [\"寶可夢\", \"Pokémon\", \"Pokemon\"])"
                        ] as [String: Any],
                        "limit": ["type": "integer", "description": "Max results to return (default 10)"]
                    ] as [String: Any],
                    "required": ["queries"] as [String]
                ] as [String: Any]
            )
        ]
    }

    // MARK: - Tool Execution

    private func executeTool(name: String, arguments: String) async throws -> String {
        chatLogger.debug("executeTool: name=\(name) args=\(arguments)")
        let args = parseArguments(arguments)

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
            let transactions = try await queryService.getTransactions(filter: filter)
            return formatTransactions(transactions)

        case "get_spending_summary":
            guard let startDate = args["start_date"] as? String,
                  let endDate = args["end_date"] as? String else {
                return "Error: start_date and end_date are required"
            }
            let summary = try await queryService.getTransactionSummary(
                period: DatePeriod(startDate: startDate, endDate: endDate)
            )
            return encodeToJSON(summary)

        case "get_category_breakdown":
            guard let startDate = args["start_date"] as? String,
                  let endDate = args["end_date"] as? String else {
                return "Error: start_date and end_date are required"
            }
            let breakdown = try await queryService.getCategoryBreakdown(
                period: DatePeriod(startDate: startDate, endDate: endDate)
            )
            return encodeToJSON(breakdown)

        case "get_top_merchants":
            guard let startDate = args["start_date"] as? String,
                  let endDate = args["end_date"] as? String else {
                return "Error: start_date and end_date are required"
            }
            let limit: Int
            if let intVal = args["limit"] as? Int {
                limit = intVal
            } else if let doubleVal = args["limit"] as? Double {
                limit = Int(doubleVal)
            } else {
                limit = 10
            }
            let merchants = try await queryService.getTopMerchants(
                period: DatePeriod(startDate: startDate, endDate: endDate),
                limit: limit
            )
            return encodeToJSON(merchants)

        case "get_upcoming_payments":
            let bills = try await queryService.getUpcomingPayments()
            return formatBills(bills)

        case "get_goals":
            let status = args["status"] as? String
            let goals = try await queryService.getGoals(status: status)
            return formatGoals(goals)

        case "search_transactions":
            guard let query = args["query"] as? String else {
                return "Error: query parameter is required"
            }
            let transactions = try await queryService.searchTransactions(query: query)
            return formatTransactions(transactions)

        case "get_account_overview":
            let overview = try await queryService.getAccountOverview()
            return encodeToJSON(overview)

        case "semantic_search":
            // Support both "queries" (array) and legacy "query" (string)
            var queries: [String] = []
            if let arr = args["queries"] as? [String] {
                queries = arr
            } else if let single = args["query"] as? String {
                queries = [single]
            }
            guard !queries.isEmpty else {
                return "Error: queries parameter is required"
            }
            let limit: Int
            if let intVal = args["limit"] as? Int {
                limit = intVal
            } else if let doubleVal = args["limit"] as? Double {
                limit = Int(doubleVal)
            } else {
                limit = 10
            }
            chatLogger.debug("semantic_search queries=\(queries) limit=\(limit)")

            // Run hybrid search for each query, merge with RRF
            var bestScores: [Int64: Float] = [:]
            for q in queries {
                let results = try await embeddingService.hybridSearch(query: q, limit: limit)
                chatLogger.debug("  query '\(q)': \(results.count) results")
                for r in results {
                    // Keep best (most negative = highest RRF) score per transaction
                    if let existing = bestScores[r.transactionId] {
                        bestScores[r.transactionId] = min(existing, r.distance)
                    } else {
                        bestScores[r.transactionId] = r.distance
                    }
                }
            }

            // Sort by best score (most negative = best match)
            let sorted = bestScores.sorted { $0.value < $1.value }
            let topIds = sorted.prefix(limit).map { $0.key }
            chatLogger.debug("merged \(bestScores.count) unique results, top \(topIds.count)")

            if topIds.isEmpty {
                return "No transactions found for: \(queries.joined(separator: ", "))"
            }
            let transactions = try await queryService.getTransactions(ids: Array(topIds))
            for t in transactions {
                chatLogger.debug("  tx: \(t.merchant ?? "?") id=\(t.id ?? 0) amt=\(t.amount)")
            }
            return formatTransactions(transactions)

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Argument Parsing

    private func parseArguments(_ jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    // MARK: - Result Formatting

    private func formatTransactions(_ transactions: [Transaction]) -> String {
        if transactions.isEmpty {
            return "No transactions found."
        }

        let limited = Array(transactions.prefix(20))
        var lines = ["Found \(transactions.count) transactions (showing \(limited.count)):"]

        for t in limited {
            let date = t.transactionDate ?? "no date"
            let merchant = t.merchant ?? "Unknown"
            let amount = String(format: "%.2f", t.amount)
            let category = t.category ?? "uncategorized"
            let type = t.type ?? "debit"
            lines.append("- \(date) | \(merchant) | \(amount) \(t.currency) | \(category) | \(type)")
        }

        if transactions.count > 20 {
            lines.append("... and \(transactions.count - 20) more transactions")
        }

        return lines.joined(separator: "\n")
    }

    private func formatBills(_ bills: [CreditCardBill]) -> String {
        if bills.isEmpty {
            return "No unpaid bills found."
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        var lines = ["\(bills.count) unpaid bill(s):"]
        for bill in bills {
            let amount = String(format: "%.2f", bill.amountDue)
            let status = bill.dueDate < today ? " [OVERDUE]" : ""
            lines.append("- \(bill.bankName) | Due: \(bill.dueDate) | \(amount) \(bill.currency)\(status)")
        }
        return lines.joined(separator: "\n")
    }

    private func formatGoals(_ goals: [FinancialGoal]) -> String {
        if goals.isEmpty {
            return "No financial goals found."
        }

        var lines = ["\(goals.count) goal(s):"]
        for goal in goals {
            let target = goal.targetAmount.map { String(format: "%.2f", $0) } ?? "N/A"
            let category = goal.category ?? "general"
            lines.append("- \(goal.title) | \(goal.status) | \(category) | Target: \(target) | Type: \(goal.type)")
        }
        return lines.joined(separator: "\n")
    }

    private func encodeToJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "Error: failed to encode result"
        }
        return json
    }
}
