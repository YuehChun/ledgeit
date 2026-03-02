import Foundation

struct MCPToolHandler: Sendable {
    let queryService: FinancialQueryService

    // MARK: - Tool Definitions

    func toolDefinitions() -> [[String: Any]] {
        [
            [
                "name": "get_transactions",
                "description": "Get transactions with optional filters for date range, category, merchant, amount, and type",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (YYYY-MM-DD)"],
                        "end_date": ["type": "string", "description": "End date (YYYY-MM-DD)"],
                        "category": ["type": "string", "description": "Filter by category"],
                        "merchant": ["type": "string", "description": "Filter by merchant name"],
                        "min_amount": ["type": "number", "description": "Minimum amount"],
                        "max_amount": ["type": "number", "description": "Maximum amount"],
                        "type": ["type": "string", "description": "Transaction type: debit, credit, or transfer"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "get_spending_summary",
                "description": "Get spending summary for a date range including total income, expenses, net savings, and transaction count",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (YYYY-MM-DD)"],
                        "end_date": ["type": "string", "description": "End date (YYYY-MM-DD)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ],
            [
                "name": "get_category_breakdown",
                "description": "Get expense breakdown by category for a date range, with amounts and percentages",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (YYYY-MM-DD)"],
                        "end_date": ["type": "string", "description": "End date (YYYY-MM-DD)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ],
            [
                "name": "get_top_merchants",
                "description": "Get top merchants by spending for a date range",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "start_date": ["type": "string", "description": "Start date (YYYY-MM-DD)"],
                        "end_date": ["type": "string", "description": "End date (YYYY-MM-DD)"],
                        "limit": ["type": "integer", "description": "Number of merchants to return (default 10)"]
                    ] as [String: Any],
                    "required": ["start_date", "end_date"]
                ] as [String: Any]
            ],
            [
                "name": "get_upcoming_payments",
                "description": "Get upcoming unpaid credit card bill payments",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "get_goals",
                "description": "Get financial goals, optionally filtered by status (suggested, accepted, completed, dismissed)",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "status": ["type": "string", "description": "Filter by status: suggested, accepted, completed, dismissed"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            [
                "name": "search_transactions",
                "description": "Search transactions by keyword across merchant, description, and category fields",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search keyword"]
                    ] as [String: Any],
                    "required": ["query"]
                ] as [String: Any]
            ],
            [
                "name": "get_account_overview",
                "description": "Get a high-level account overview including income, expenses, top categories, upcoming payments, and active goals for the current month",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ] as [String: Any]
            ]
        ]
    }

    // MARK: - Tool Call Dispatch

    func handleToolCall(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        case "get_transactions":
            return try await handleGetTransactions(arguments)
        case "get_spending_summary":
            return try await handleGetSpendingSummary(arguments)
        case "get_category_breakdown":
            return try await handleGetCategoryBreakdown(arguments)
        case "get_top_merchants":
            return try await handleGetTopMerchants(arguments)
        case "get_upcoming_payments":
            return try await handleGetUpcomingPayments()
        case "get_goals":
            return try await handleGetGoals(arguments)
        case "search_transactions":
            return try await handleSearchTransactions(arguments)
        case "get_account_overview":
            return try await handleGetAccountOverview()
        default:
            throw MCPError.unknownTool(name)
        }
    }

    // MARK: - Tool Implementations

    private func handleGetTransactions(_ args: [String: Any]) async throws -> String {
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
        let items: [[String: Any]] = transactions.map { txn in
            var dict: [String: Any] = [
                "amount": txn.amount,
                "currency": txn.currency
            ]
            if let date = txn.transactionDate { dict["date"] = date }
            if let merchant = txn.merchant { dict["merchant"] = merchant }
            if let category = txn.category { dict["category"] = category }
            if let type = txn.type { dict["type"] = type }
            if let description = txn.description { dict["description"] = description }
            return dict
        }
        let result: [String: Any] = [
            "count": transactions.count,
            "transactions": items
        ]
        return try jsonString(result)
    }

    private func handleGetSpendingSummary(_ args: [String: Any]) async throws -> String {
        guard let startDate = args["start_date"] as? String,
              let endDate = args["end_date"] as? String else {
            throw MCPError.missingParameter("start_date and end_date are required")
        }
        let period = DatePeriod(startDate: startDate, endDate: endDate)
        let summary = try await queryService.getTransactionSummary(period: period)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(summary)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleGetCategoryBreakdown(_ args: [String: Any]) async throws -> String {
        guard let startDate = args["start_date"] as? String,
              let endDate = args["end_date"] as? String else {
            throw MCPError.missingParameter("start_date and end_date are required")
        }
        let period = DatePeriod(startDate: startDate, endDate: endDate)
        let categories = try await queryService.getCategoryBreakdown(period: period)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(categories)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func handleGetTopMerchants(_ args: [String: Any]) async throws -> String {
        guard let startDate = args["start_date"] as? String,
              let endDate = args["end_date"] as? String else {
            throw MCPError.missingParameter("start_date and end_date are required")
        }
        let period = DatePeriod(startDate: startDate, endDate: endDate)
        let limit = args["limit"] as? Int ?? 10
        let merchants = try await queryService.getTopMerchants(period: period, limit: limit)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(merchants)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func handleGetUpcomingPayments() async throws -> String {
        let bills = try await queryService.getUpcomingPayments()
        let items: [[String: Any]] = bills.map { bill in
            var dict: [String: Any] = [
                "bank_name": bill.bankName,
                "due_date": bill.dueDate,
                "amount_due": bill.amountDue,
                "currency": bill.currency
            ]
            if let period = bill.statementPeriod { dict["statement_period"] = period }
            return dict
        }
        return try jsonString(items)
    }

    private func handleGetGoals(_ args: [String: Any]) async throws -> String {
        let status = args["status"] as? String
        let goals = try await queryService.getGoals(status: status)
        let items: [[String: Any]] = goals.map { goal in
            var dict: [String: Any] = [
                "title": goal.title,
                "status": goal.status,
                "type": goal.type,
                "progress": goal.progress
            ]
            if let category = goal.category { dict["category"] = category }
            if let targetAmount = goal.targetAmount { dict["target_amount"] = targetAmount }
            if let targetDate = goal.targetDate { dict["target_date"] = targetDate }
            return dict
        }
        return try jsonString(items)
    }

    private func handleSearchTransactions(_ args: [String: Any]) async throws -> String {
        guard let query = args["query"] as? String else {
            throw MCPError.missingParameter("query is required")
        }
        let transactions = try await queryService.searchTransactions(query: query)
        let items: [[String: Any]] = transactions.map { txn in
            var dict: [String: Any] = [
                "amount": txn.amount,
                "currency": txn.currency
            ]
            if let date = txn.transactionDate { dict["date"] = date }
            if let merchant = txn.merchant { dict["merchant"] = merchant }
            if let category = txn.category { dict["category"] = category }
            if let type = txn.type { dict["type"] = type }
            if let description = txn.description { dict["description"] = description }
            return dict
        }
        let result: [String: Any] = [
            "count": transactions.count,
            "transactions": items
        ]
        return try jsonString(result)
    }

    private func handleGetAccountOverview() async throws -> String {
        let overview = try await queryService.getAccountOverview()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(overview)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Helpers

    private func jsonString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let str = String(data: data, encoding: .utf8) else {
            throw MCPError.serializationFailed
        }
        return str
    }
}

// MARK: - Errors

enum MCPError: Error, LocalizedError {
    case unknownTool(String)
    case missingParameter(String)
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingParameter(let msg):
            return "Missing parameter: \(msg)"
        case .serializationFailed:
            return "Failed to serialize result to JSON"
        }
    }
}
