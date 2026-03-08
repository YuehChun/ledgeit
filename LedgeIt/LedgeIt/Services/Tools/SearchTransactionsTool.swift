import Foundation
import AnyLanguageModel

struct SearchTransactionsTool: Tool {
    let queryService: FinancialQueryService
    let name = "searchTransactions"
    let description = "Search transactions by merchant, description, or category keyword"

    @Generable
    struct Arguments {
        @Guide(description: "Search keyword")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let transactions = try await queryService.searchTransactions(query: arguments.query)
        return ToolFormatters.formatTransactions(transactions)
    }
}
