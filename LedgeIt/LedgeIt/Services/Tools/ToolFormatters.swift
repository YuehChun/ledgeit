import Foundation

enum ToolFormatters {
    static func formatTransactions(_ transactions: [Transaction]) -> String {
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

    static func formatBills(_ bills: [CreditCardBill]) -> String {
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

    static func formatGoals(_ goals: [FinancialGoal]) -> String {
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

    static func encodeToJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "Error: failed to encode result"
        }
        return json
    }
}
