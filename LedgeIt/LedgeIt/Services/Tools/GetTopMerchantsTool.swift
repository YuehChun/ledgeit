import Foundation
import AnyLanguageModel

struct GetTopMerchantsTool: Tool {
    let queryService: FinancialQueryService
    let name = "getTopMerchants"
    let description = "Get top merchants by spending amount for a date range"

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)")
        var startDate: String
        @Guide(description: "End date (yyyy-MM-dd)")
        var endDate: String
        @Guide(description: "Max number of merchants to return (default 10)")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let merchants = try await queryService.getTopMerchants(
            period: DatePeriod(startDate: arguments.startDate, endDate: arguments.endDate),
            limit: arguments.limit ?? 10
        )
        return ToolFormatters.encodeToJSON(merchants)
    }
}
