import Foundation
import AnyLanguageModel

struct GetUpcomingPaymentsTool: Tool {
    let queryService: FinancialQueryService
    let name = "getUpcomingPayments"
    let description = "Get all unpaid credit card bills (including overdue). Use when user asks about credit card payments, due dates, or bills."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let bills = try await queryService.getUpcomingPayments()
        return ToolFormatters.formatBills(bills)
    }
}
