import Foundation
import AnyLanguageModel

struct GetSpendingSummaryTool: Tool {
    let queryService: FinancialQueryService
    let name = "getSpendingSummary"
    let description = "Get a spending summary for a date range including income, expenses, and net savings"

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)")
        var startDate: String
        @Guide(description: "End date (yyyy-MM-dd)")
        var endDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let summary = try await queryService.getTransactionSummary(
            period: DatePeriod(startDate: arguments.startDate, endDate: arguments.endDate)
        )
        return ToolFormatters.encodeToJSON(summary)
    }
}
