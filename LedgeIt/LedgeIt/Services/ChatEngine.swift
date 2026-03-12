import Foundation
import os.log

private let chatLogger = Logger(subsystem: "com.ledgeit.app", category: "ChatEngine")

actor ChatEngine {
    private let queryService: FinancialQueryService
    private let embeddingService: EmbeddingService
    private let agentFileManager = AgentFileManager()
    private var conversationHistory: [LLMMessage] = []
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

    func restoreMessage(role: LLMMessage.Role, content: String) {
        switch role {
        case .user:
            conversationHistory.append(.user(content))
        case .assistant:
            conversationHistory.append(.assistant(content))
        default:
            break
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

            // Add user message to history
            conversationHistory.append(.user(message))

            // Build system prompt with current financial snapshot
            let systemPrompt = try await buildSystemPrompt()

            // Create session via SessionFactory (instructions not passed here;
            // system prompt is included directly in messages for tool-calling support)
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(
                assignment: config.chat,
                config: config
            )

            // Signal message started
            continuation.yield(.messageStarted(messageId))

            // Build messages: system + conversation history
            var messages: [LLMMessage] = [.system(systemPrompt)]
            messages.append(contentsOf: conversationHistory)

            var fullResponse = ""

            // Tool-calling loop
            for _ in 0..<maxToolIterations {
                var iterationText = ""
                var toolCall: LLMToolCall?

                let stream = await session.streamComplete(
                    messages: messages,
                    tools: toolDefinitions
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

                fullResponse += iterationText

                guard let tc = toolCall else {
                    chatLogger.debug("No tool call in this iteration, done.")
                    break
                }
                chatLogger.debug("Tool call: \(tc.name)")

                continuation.yield(.toolCallStarted(tc.name))

                let toolResult: String
                do {
                    toolResult = try await executeTool(name: tc.name, arguments: tc.arguments)
                } catch {
                    toolResult = "Error executing tool \(tc.name): \(error.localizedDescription)"
                }

                // Append assistant message with tool call + tool result
                messages.append(.assistantWithToolCalls(
                    iterationText.isEmpty ? nil : iterationText,
                    toolCalls: [tc]
                ))
                messages.append(.toolResult(callId: tc.id, content: toolResult))
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

    // MARK: - System Prompt

    private func buildSystemPrompt() async throws -> String {
        let overview = try await queryService.getAccountOverview()

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())

        let categoryList = overview.topCategories
            .map { "\($0.category): \(String(format: "%.2f", $0.totalAmount)) (\(String(format: "%.1f", $0.percentage))%)" }
            .joined(separator: ", ")

        let financialSnapshot = """
            Today is \(today).

            Current financial snapshot:
            - This month's income: \(String(format: "%.2f", overview.totalIncome))
            - This month's expenses: \(String(format: "%.2f", overview.totalExpenses))
            - Transaction count: \(overview.transactionCount)
            - Upcoming payments: \(overview.upcomingPayments)
            - Active goals: \(overview.activeGoals)
            - Top spending categories: \(categoryList.isEmpty ? "None" : categoryList)

            ## Interaction Guidelines
            1. **Understand intent first**: When the user asks a question, briefly confirm your understanding of what they want before diving into data.
            2. **Rephrase when ambiguous**: If the user's request is vague, rephrase their intent and ask for confirmation.
            3. **Summarize findings**: After retrieving data, provide a clear summary with key insights, not just raw numbers.
            4. **Proactive suggestions**: When you notice patterns (overspending, upcoming bills, goal progress), mention them.
            5. **Remember important things**: When you learn something new about the user (preferences, goals, habits), save it to memory using memory_save.

            ## Formatting
            - Use the available tools to query detailed data when needed.
            - Be concise and helpful.
            - Format currency amounts with 2 decimal places.
            - Respond in the same language the user uses.

            ## Tool Selection
            - Use `semantic_search` when the user asks about specific merchants, brands, products, or conceptual spending categories.
            - CRITICAL: Transaction data is stored in BOTH English and Chinese. When searching, ALWAYS provide BOTH the original term AND its translation in the `queries` array.
            - Use `get_transactions` or `search_transactions` when the user specifies exact filters.
            - Use `memory_save` when you learn something important about the user.
            - Use `memory_search` when you need to recall past conversations or user preferences.
            - Use `memory_get` to read full content of a specific memory file.
            """

        return AgentPromptBuilder.build(
            fileManager: agentFileManager,
            financialSnapshot: financialSnapshot
        )
    }

    // MARK: - Tool Definitions

    private var toolDefinitions: [LLMToolDefinition] {
        [
            LLMToolDefinition(
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
            LLMToolDefinition(
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
            LLMToolDefinition(
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
            LLMToolDefinition(
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
            LLMToolDefinition(
                name: "get_upcoming_payments",
                description: "Get all unpaid credit card bills (including overdue). Use when user asks about credit card payments, due dates, or bills.",
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            LLMToolDefinition(
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
            LLMToolDefinition(
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
            LLMToolDefinition(
                name: "get_account_overview",
                description: "Get a high-level overview of the account including income, expenses, upcoming payments, and goals",
                parameters: [
                    "type": "object",
                    "properties": [:] as [String: Any],
                    "required": [] as [String]
                ] as [String: Any]
            ),
            LLMToolDefinition(
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
            ),
            LLMToolDefinition(
                name: "memory_save",
                description: "Save information to the agent's memory. Use when you learn something important about the user (preferences, goals, habits) or need to record a decision or observation.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "file": [
                            "type": "string",
                            "enum": ["user_profile", "long_term", "daily", "active_context"],
                            "description": "Target file: user_profile (preferences), long_term (patterns/facts), daily (today's log), active_context (in-progress work)"
                        ] as [String: Any],
                        "content": ["type": "string", "description": "The text content to save"],
                        "mode": [
                            "type": "string",
                            "enum": ["append", "replace"],
                            "description": "Write mode: append (add to file) or replace (overwrite). Default: append"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["file", "content"] as [String]
                ] as [String: Any]
            ),
            LLMToolDefinition(
                name: "memory_search",
                description: "Search through the agent's memory files by keyword. Use when you need to recall past conversations, user preferences, or previous decisions.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search keywords"],
                        "scope": [
                            "type": "string",
                            "enum": ["all", "daily", "long_term"],
                            "description": "Search scope: all (default), daily (only daily logs), long_term (only MEMORY.md)"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["query"] as [String]
                ] as [String: Any]
            ),
            LLMToolDefinition(
                name: "memory_get",
                description: "Read the full content of a specific memory file. Use when memory_search found relevant results and you need the complete context.",
                parameters: [
                    "type": "object",
                    "properties": [
                        "file": [
                            "type": "string",
                            "description": "File to read: user_profile, long_term, active_context, persona, or daily:YYYY-MM-DD (e.g. daily:2026-03-12)"
                        ] as [String: Any]
                    ] as [String: Any],
                    "required": ["file"] as [String]
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

        case "memory_save":
            let fileStr = args["file"] as? String ?? "daily"
            let content = args["content"] as? String ?? ""
            let modeStr = args["mode"] as? String ?? "append"

            guard !content.isEmpty else {
                return "Error: content parameter is required"
            }

            let file: AgentFileManager.AgentFile
            switch fileStr {
            case "user_profile": file = .userProfile
            case "long_term": file = .longTerm
            case "active_context": file = .activeContext
            default: file = .daily
            }

            let mode: AgentFileManager.WriteMode = modeStr == "replace" ? .replace : .append

            let finalContent: String
            if file == .daily {
                let timeFmt = DateFormatter()
                timeFmt.dateFormat = "HH:mm"
                finalContent = "[\(timeFmt.string(from: Date()))] \(content)"
            } else {
                finalContent = content
            }

            let result = try agentFileManager.write(file: file, content: finalContent, mode: mode)
            return "Saved to \(result.path) (\(result.count) characters)"

        case "memory_search":
            let query = args["query"] as? String ?? ""
            let scope = args["scope"] as? String ?? "all"
            guard !query.isEmpty else {
                return "Error: query parameter is required"
            }
            let searchResults = agentFileManager.search(query: query, scope: scope)
            if searchResults.isEmpty {
                return "No memory entries found for: \(query)"
            }
            return searchResults.map { "[\($0.fileName):\($0.lineNumber)] \($0.content)" }.joined(separator: "\n\n")

        case "memory_get":
            let fileStr = args["file"] as? String ?? ""
            let file: AgentFileManager.AgentFile
            var date: String? = nil

            if fileStr.hasPrefix("daily:") {
                file = .daily
                date = String(fileStr.dropFirst("daily:".count))
            } else {
                switch fileStr {
                case "user_profile": file = .userProfile
                case "long_term": file = .longTerm
                case "active_context": file = .activeContext
                case "persona": file = .persona
                default:
                    return "Error: unknown file '\(fileStr)'. Use: user_profile, long_term, active_context, persona, or daily:YYYY-MM-DD"
                }
            }

            guard let memContent = agentFileManager.read(file: file, date: date) else {
                return "File not found or empty: \(fileStr)"
            }
            if memContent.count > 10_000 {
                return String(memContent.prefix(10_000)) + "\n\n[truncated at 10,000 characters]"
            }
            return memContent

        default:
            return "Unknown tool: \(name)"
        }
    }

    // MARK: - Argument Parsing

    private func parseArguments(_ jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8) else {
            chatLogger.warning("Tool arguments not valid UTF-8: \(jsonString.prefix(200))")
            return [:]
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                chatLogger.warning("Tool arguments not a JSON object: \(jsonString.prefix(200))")
                return [:]
            }
            return json
        } catch {
            chatLogger.warning("Tool arguments JSON parse failed: \(error.localizedDescription), raw: \(jsonString.prefix(200))")
            return [:]
        }
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
