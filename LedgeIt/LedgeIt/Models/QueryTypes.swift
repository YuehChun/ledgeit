import Foundation

// MARK: - Filters

struct TransactionFilter: Sendable {
    var startDate: String?
    var endDate: String?
    var category: String?
    var merchant: String?
    var minAmount: Double?
    var maxAmount: Double?
    var type: String? // debit, credit, transfer
}

struct BillFilter: Sendable {
    var startDate: String?
    var endDate: String?
    var bankName: String?
    var isPaid: Bool?
}

struct DatePeriod: Sendable, Codable {
    var startDate: String
    var endDate: String

    static var thisMonth: DatePeriod {
        let now = Date()
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: start), endDate: fmt.string(from: now))
    }

    static var lastMonth: DatePeriod {
        let now = Date()
        let cal = Calendar.current
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfThisMonth)!
        let endOfLastMonth = cal.date(byAdding: .day, value: -1, to: startOfThisMonth)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: startOfLastMonth), endDate: fmt.string(from: endOfLastMonth))
    }

    static var last30Days: DatePeriod {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return DatePeriod(startDate: fmt.string(from: start), endDate: fmt.string(from: now))
    }
}

// MARK: - Summaries

struct SpendingSummary: Sendable, Codable {
    let totalIncome: Double
    let totalExpenses: Double
    let netSavings: Double
    let transactionCount: Int
    let period: DatePeriod
}

struct MerchantSummary: Sendable, Codable {
    let merchant: String
    let totalAmount: Double
    let transactionCount: Int
}

struct CategorySummary: Sendable, Codable {
    let category: String
    let totalAmount: Double
    let transactionCount: Int
    let percentage: Double
}

struct AccountOverview: Sendable, Codable {
    let totalIncome: Double
    let totalExpenses: Double
    let transactionCount: Int
    let topCategories: [CategorySummary]
    let upcomingPayments: Int
    let activeGoals: Int
}

struct GoalProgress: Sendable, Codable {
    let goal: FinancialGoal
    let currentAmount: Double
    let percentComplete: Double
}
