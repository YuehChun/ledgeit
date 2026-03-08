import Foundation
import AnyLanguageModel

struct GetAccountOverviewTool: Tool {
    let queryService: FinancialQueryService
    let name = "getAccountOverview"
    let description = "Get a high-level overview of the account including income, expenses, upcoming payments, and goals"

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let overview = try await queryService.getAccountOverview()
        return ToolFormatters.encodeToJSON(overview)
    }
}
