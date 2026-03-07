import Foundation
import AnyLanguageModel

struct GetCategoryBreakdownTool: Tool {
    let queryService: FinancialQueryService
    let name = "getCategoryBreakdown"
    let description = "Get spending breakdown by category for a date range"

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)")
        var startDate: String
        @Guide(description: "End date (yyyy-MM-dd)")
        var endDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let breakdown = try await queryService.getCategoryBreakdown(
            period: DatePeriod(startDate: arguments.startDate, endDate: arguments.endDate)
        )
        return ToolFormatters.encodeToJSON(breakdown)
    }
}
