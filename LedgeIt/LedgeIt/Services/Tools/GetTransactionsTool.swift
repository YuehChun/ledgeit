import Foundation
import AnyLanguageModel

struct GetTransactionsTool: Tool {
    let queryService: FinancialQueryService
    let name = "getTransactions"
    let description = "Get a list of transactions with optional filters"

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)")
        var startDate: String?
        @Guide(description: "End date (yyyy-MM-dd)")
        var endDate: String?
        @Guide(description: "Filter by category")
        var category: String?
        @Guide(description: "Filter by merchant name")
        var merchant: String?
        @Guide(description: "Minimum transaction amount")
        var minAmount: Double?
        @Guide(description: "Maximum transaction amount")
        var maxAmount: Double?
        @Guide(description: "Transaction type: debit, credit, or transfer")
        var type: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let filter = TransactionFilter(
            startDate: arguments.startDate,
            endDate: arguments.endDate,
            category: arguments.category,
            merchant: arguments.merchant,
            minAmount: arguments.minAmount,
            maxAmount: arguments.maxAmount,
            type: arguments.type
        )
        let transactions = try await queryService.getTransactions(filter: filter)
        return ToolFormatters.formatTransactions(transactions)
    }
}
