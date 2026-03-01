import Foundation
import GRDB

@Observable
@MainActor
final class PersonalFinanceService: Sendable {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    struct SpendingSummary: Sendable {
        let totalSpending: Double
        let totalIncome: Double
        let transactionCount: Int
        let categoryBreakdown: [CategoryAmount]
        let topMerchants: [MerchantAmount]
    }

    struct CategoryAmount: Identifiable, Sendable {
        let id = UUID()
        let category: String
        let amount: Double
        let count: Int
        var percentage: Double = 0
    }

    struct MerchantAmount: Identifiable, Sendable {
        let id = UUID()
        let merchant: String
        let amount: Double
        let count: Int
    }

    struct MonthlyTrend: Identifiable, Sendable {
        let id = UUID()
        let month: String
        let spending: Double
        let income: Double
    }

    func getMonthlySummary(year: Int, month: Int) throws -> SpendingSummary {
        let startDate = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let endDate = String(format: "%04d-%02d-01", endYear, endMonth)

        return try database.db.read { db in
            let totalSpending = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [startDate, endDate]) ?? 0

            let totalIncome = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND type = 'credit'
                """, arguments: [startDate, endDate]) ?? 0

            let transactionCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                """, arguments: [startDate, endDate]) ?? 0

            let categoryRows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(amount) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND category IS NOT NULL
                GROUP BY category
                ORDER BY total DESC
                """, arguments: [startDate, endDate])

            let totalForPercentage = categoryRows.reduce(0.0) { $0 + ($1["total"] as Double? ?? 0) }
            let categories = categoryRows.map { row -> CategoryAmount in
                let amount = row["total"] as Double? ?? 0
                let pct = totalForPercentage > 0 ? (amount / totalForPercentage) * 100 : 0
                return CategoryAmount(
                    category: row["category"] as String? ?? "Unknown",
                    amount: amount,
                    count: row["cnt"] as Int? ?? 0,
                    percentage: pct
                )
            }

            let merchantRows = try Row.fetchAll(db, sql: """
                SELECT merchant, SUM(amount) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND merchant IS NOT NULL
                GROUP BY merchant
                ORDER BY total DESC
                LIMIT 10
                """, arguments: [startDate, endDate])

            let merchants = merchantRows.map { row in
                MerchantAmount(
                    merchant: row["merchant"] as String? ?? "Unknown",
                    amount: row["total"] as Double? ?? 0,
                    count: row["cnt"] as Int? ?? 0
                )
            }

            return SpendingSummary(
                totalSpending: abs(totalSpending),
                totalIncome: totalIncome,
                transactionCount: transactionCount,
                categoryBreakdown: categories,
                topMerchants: merchants
            )
        }
    }

    func getMonthlyTrends(months: Int = 6) throws -> [MonthlyTrend] {
        let calendar = Calendar.current
        let now = Date()

        return try database.db.read { db in
            var trends: [MonthlyTrend] = []
            for i in (0..<months).reversed() {
                guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                let startDate = String(format: "%04d-%02d-01", year, month)
                let endMonth = month == 12 ? 1 : month + 1
                let endYear = month == 12 ? year + 1 : year
                let endDate = String(format: "%04d-%02d-01", endYear, endMonth)

                let spending = try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                    WHERE deleted_at IS NULL
                    AND transaction_date >= ? AND transaction_date < ?
                    AND (type = 'debit' OR type IS NULL)
                    """, arguments: [startDate, endDate]) ?? 0

                let income = try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(amount), 0) FROM transactions
                    WHERE deleted_at IS NULL
                    AND transaction_date >= ? AND transaction_date < ?
                    AND type = 'credit'
                    """, arguments: [startDate, endDate]) ?? 0

                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                trends.append(MonthlyTrend(
                    month: formatter.string(from: date),
                    spending: spending,
                    income: income
                ))
            }
            return trends
        }
    }

    func getRecentTransactions(limit: Int = 20) throws -> [Transaction] {
        try database.db.read { db in
            try Transaction
                .filter(Transaction.Columns.deletedAt == nil)
                .order(Transaction.Columns.transactionDate.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Recurring Payments

    struct RecurringPayment: Identifiable, Sendable {
        let id = UUID()
        let merchant: String
        let currency: String
        let averageAmount: Double
        let frequency: Int // occurrences
        let distinctMonths: Int
        let category: String?
    }

    func detectRecurringPayments() throws -> [RecurringPayment] {
        try database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT merchant, currency, AVG(ABS(amount)) as avg_amount,
                       COUNT(*) as cnt,
                       COUNT(DISTINCT strftime('%Y-%m', transaction_date)) as months,
                       category
                FROM transactions
                WHERE deleted_at IS NULL
                AND merchant IS NOT NULL
                AND transaction_date IS NOT NULL
                AND (type = 'debit' OR type IS NULL)
                GROUP BY merchant, currency
                HAVING COUNT(DISTINCT strftime('%Y-%m', transaction_date)) >= 2
                ORDER BY avg_amount DESC
                """)

            return rows.map { row in
                RecurringPayment(
                    merchant: row["merchant"] as String? ?? "Unknown",
                    currency: row["currency"] as String? ?? "USD",
                    averageAmount: row["avg_amount"] as Double? ?? 0,
                    frequency: row["cnt"] as Int? ?? 0,
                    distinctMonths: row["months"] as Int? ?? 0,
                    category: row["category"] as String?
                )
            }
        }
    }

    // MARK: - Spending Velocity

    struct SpendingVelocity: Sendable {
        let currentWeekSpending: Double
        let weeklyAverage: Double
        let percentageOverAverage: Double
        let isAlert: Bool // true if >30% over average
    }

    func getSpendingVelocity() throws -> SpendingVelocity {
        try database.db.read { db in
            let now = Date()
            let calendar = Calendar.current

            // Current week spending
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let weekStartStr = ISO8601DateFormatter().string(from: weekStart).prefix(10)

            let currentWeek = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [String(weekStartStr)]) ?? 0

            // 12-week average (excluding current week)
            let twelveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -12, to: weekStart)!
            let twelveWeeksAgoStr = ISO8601DateFormatter().string(from: twelveWeeksAgo).prefix(10)

            let historicalTotal = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [String(twelveWeeksAgoStr), String(weekStartStr)]) ?? 0

            let weeklyAverage = historicalTotal / 12.0
            let percentOver = weeklyAverage > 0 ? ((currentWeek - weeklyAverage) / weeklyAverage) * 100 : 0

            return SpendingVelocity(
                currentWeekSpending: currentWeek,
                weeklyAverage: weeklyAverage,
                percentageOverAverage: percentOver,
                isAlert: percentOver > 30
            )
        }
    }

    // MARK: - Credit Card Bills

    func getUpcomingBills() throws -> [CreditCardBill] {
        try database.db.read { db in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let today = formatter.string(from: Date())
            let calendar = Calendar.current
            let twoMonthsOut = calendar.date(byAdding: .month, value: 2, to: Date()) ?? Date()
            let futureDate = formatter.string(from: twoMonthsOut)

            // Show: unpaid bills (even overdue) + upcoming bills within 2 months
            return try CreditCardBill
                .filter(
                    (CreditCardBill.Columns.isPaid == false) ||
                    (CreditCardBill.Columns.dueDate >= today && CreditCardBill.Columns.dueDate <= futureDate)
                )
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    func getBillsForMonth(year: Int, month: Int) throws -> [CreditCardBill] {
        try database.db.read { db in
            let startDate = String(format: "%04d-%02d-01", year, month)
            let endDate: String
            if month == 12 {
                endDate = String(format: "%04d-01-01", year + 1)
            } else {
                endDate = String(format: "%04d-%02d-01", year, month + 1)
            }
            return try CreditCardBill
                .filter(CreditCardBill.Columns.dueDate >= startDate)
                .filter(CreditCardBill.Columns.dueDate < endDate)
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    func markBillAsPaid(_ billId: Int64, paid: Bool = true) throws {
        try database.db.write { db in
            if var bill = try CreditCardBill.fetchOne(db, key: billId) {
                bill.isPaid = paid
                try bill.update(db)
            }
        }
    }

    // MARK: - Budget Summary

    struct BudgetSummary: Sendable {
        let monthlyIncome: Double
        let savingsTarget: Double
        let savingsReserve: Double
        let unpaidBills: Double
        let spendingBudget: Double
        let spentSoFar: Double
        let disposableBalance: Double
        let daysRemaining: Int
        let daysInMonth: Int
        let dailyAllowance: Double
        let currency: String
    }

    func getBudgetSummary(year: Int, month: Int, savingsTarget: Double) throws -> BudgetSummary? {
        try database.db.read { db in
            let startDate = String(format: "%04d-%02d-01", year, month)
            let endMonth = month == 12 ? 1 : month + 1
            let endYear = month == 12 ? year + 1 : year
            let endDate = String(format: "%04d-%02d-01", endYear, endMonth)

            let totalIncome = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND type = 'credit'
                """, arguments: [startDate, endDate]) ?? 0

            guard totalIncome > 0 else { return nil }

            let totalSpending = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [startDate, endDate]) ?? 0

            let unpaidBills = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount_due), 0) FROM credit_card_bills
                WHERE due_date >= ? AND due_date < ?
                AND is_paid = 0
                """, arguments: [startDate, endDate]) ?? 0

            let currency = try String.fetchOne(db, sql: """
                SELECT currency FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date < ?
                LIMIT 1
                """, arguments: [startDate, endDate]) ?? "TWD"

            let calendar = Calendar.current
            let now = Date()
            let range = calendar.range(of: .day, in: .month, for: now)!
            let daysInMonth = range.count
            let today = calendar.component(.day, from: now)
            let daysRemaining = max(1, daysInMonth - today + 1)

            let savingsReserve = totalIncome * savingsTarget
            let spendingBudget = totalIncome - savingsReserve - unpaidBills
            let disposable = spendingBudget - totalSpending
            let daily = max(0, disposable) / Double(daysRemaining)

            return BudgetSummary(
                monthlyIncome: totalIncome,
                savingsTarget: savingsTarget,
                savingsReserve: savingsReserve,
                unpaidBills: unpaidBills,
                spendingBudget: max(0, spendingBudget),
                spentSoFar: totalSpending,
                disposableBalance: disposable,
                daysRemaining: daysRemaining,
                daysInMonth: daysInMonth,
                dailyAllowance: daily,
                currency: currency
            )
        }
    }

    func getAllTransactions(category: String? = nil, searchText: String? = nil) throws -> [Transaction] {
        try database.db.read { db in
            var query = Transaction.filter(Transaction.Columns.deletedAt == nil)
            if let category {
                query = query.filter(Transaction.Columns.category == category)
            }
            if let searchText, !searchText.isEmpty {
                let pattern = "%\(searchText)%"
                query = query.filter(
                    Transaction.Columns.merchant.like(pattern) ||
                    Transaction.Columns.description.like(pattern)
                )
            }
            return try query
                .order(Transaction.Columns.transactionDate.desc)
                .fetchAll(db)
        }
    }
}
