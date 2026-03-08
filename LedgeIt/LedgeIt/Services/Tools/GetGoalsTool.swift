import Foundation
import AnyLanguageModel

struct GetGoalsTool: Tool {
    let queryService: FinancialQueryService
    let name = "getGoals"
    let description = "Get financial goals, optionally filtered by status"

    @Generable
    struct Arguments {
        @Guide(description: "Filter by status: suggested, accepted, completed, dismissed")
        var status: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let goals = try await queryService.getGoals(status: arguments.status)
        return ToolFormatters.formatGoals(goals)
    }
}
