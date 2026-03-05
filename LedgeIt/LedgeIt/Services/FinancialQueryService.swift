import Foundation
import GRDB

actor FinancialQueryService {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Transactions

    func getTransactions(filter: TransactionFilter) async throws -> [Transaction] {
        try await database.db.read { db in
            var query = Transaction.filter(Transaction.Columns.deletedAt == nil)

            if let startDate = filter.startDate {
                query = query.filter(Transaction.Columns.transactionDate >= startDate)
            }
            if let endDate = filter.endDate {
                query = query.filter(Transaction.Columns.transactionDate <= endDate)
            }
            if let category = filter.category {
                query = query.filter(Transaction.Columns.category == category)
            }
            if let merchant = filter.merchant {
                query = query.filter(Transaction.Columns.merchant == merchant)
            }
            if let minAmount = filter.minAmount {
                query = query.filter(Transaction.Columns.amount >= minAmount)
            }
            if let maxAmount = filter.maxAmount {
                query = query.filter(Transaction.Columns.amount <= maxAmount)
            }
            if let type = filter.type {
                query = query.filter(Transaction.Columns.type == type)
            }

            return try query
                .order(Transaction.Columns.transactionDate.desc)
                .limit(100)
                .fetchAll(db)
        }
    }

    func getTransactions(ids: [Int64]) async throws -> [Transaction] {
        guard !ids.isEmpty else { return [] }
        return try await database.db.read { db in
            try Transaction
                .filter(ids.contains(Transaction.Columns.id))
                .filter(Transaction.Columns.deletedAt == nil)
                .fetchAll(db)
        }
    }

    func getTransactionSummary(period: DatePeriod) async throws -> SpendingSummary {
        try await database.db.read { db in
            let totalIncome = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date <= ?
                AND type = 'credit'
                """, arguments: [period.startDate, period.endDate]) ?? 0

            let totalExpenses = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date <= ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [period.startDate, period.endDate]) ?? 0

            let transactionCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date <= ?
                """, arguments: [period.startDate, period.endDate]) ?? 0

            return SpendingSummary(
                totalIncome: totalIncome,
                totalExpenses: totalExpenses,
                netSavings: totalIncome - totalExpenses,
                transactionCount: transactionCount,
                period: period
            )
        }
    }

    func getTopMerchants(period: DatePeriod, limit: Int = 10) async throws -> [MerchantSummary] {
        try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT merchant, SUM(ABS(amount)) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date <= ?
                AND merchant IS NOT NULL
                AND (type = 'debit' OR type IS NULL)
                GROUP BY merchant
                ORDER BY total DESC
                LIMIT ?
                """, arguments: [period.startDate, period.endDate, limit])

            return rows.map { row in
                MerchantSummary(
                    merchant: row["merchant"] as String? ?? "Unknown",
                    totalAmount: row["total"] as Double? ?? 0,
                    transactionCount: row["cnt"] as Int? ?? 0
                )
            }
        }
    }

    func getCategoryBreakdown(period: DatePeriod) async throws -> [CategorySummary] {
        try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(ABS(amount)) as total, COUNT(*) as cnt
                FROM transactions
                WHERE deleted_at IS NULL
                AND transaction_date >= ? AND transaction_date <= ?
                AND category IS NOT NULL
                AND (type = 'debit' OR type IS NULL)
                GROUP BY category
                ORDER BY total DESC
                """, arguments: [period.startDate, period.endDate])

            let grandTotal = rows.reduce(0.0) { $0 + ($1["total"] as Double? ?? 0) }

            return rows.map { row in
                let amount = row["total"] as Double? ?? 0
                let percentage = grandTotal > 0 ? (amount / grandTotal) * 100 : 0
                return CategorySummary(
                    category: row["category"] as String? ?? "Unknown",
                    totalAmount: amount,
                    transactionCount: row["cnt"] as Int? ?? 0,
                    percentage: percentage
                )
            }
        }
    }

    // MARK: - Credit Card Bills

    func getCreditCardBills(filter: BillFilter) async throws -> [CreditCardBill] {
        try await database.db.read { db in
            var query = CreditCardBill.all()

            if let startDate = filter.startDate {
                query = query.filter(CreditCardBill.Columns.dueDate >= startDate)
            }
            if let endDate = filter.endDate {
                query = query.filter(CreditCardBill.Columns.dueDate <= endDate)
            }
            if let bankName = filter.bankName {
                query = query.filter(CreditCardBill.Columns.bankName == bankName)
            }
            if let isPaid = filter.isPaid {
                query = query.filter(CreditCardBill.Columns.isPaid == isPaid)
            }

            return try query
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    func getUpcomingPayments() async throws -> [CreditCardBill] {
        try await database.db.read { db in
            // Return ALL unpaid bills (including past-due) so users see overdue payments
            return try CreditCardBill
                .filter(CreditCardBill.Columns.isPaid == false)
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    // MARK: - Goals

    func getGoals(status: String? = nil) async throws -> [FinancialGoal] {
        try await database.db.read { db in
            var query = FinancialGoal.all()
            if let status {
                query = query.filter(FinancialGoal.Columns.status == status)
            }
            return try query
                .order(FinancialGoal.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Reports

    func getLatestReport() async throws -> FinancialReport? {
        try await database.db.read { db in
            try FinancialReport
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

    func getReports(period: DatePeriod) async throws -> [FinancialReport] {
        try await database.db.read { db in
            try FinancialReport
                .filter(FinancialReport.Columns.createdAt >= period.startDate)
                .filter(FinancialReport.Columns.createdAt <= period.endDate)
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Search

    func searchTransactions(query: String) async throws -> [Transaction] {
        try await database.db.read { db in
            let escaped = query
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let pattern = "%\(escaped)%"
            return try Transaction
                .filter(Transaction.Columns.deletedAt == nil)
                .filter(
                    Transaction.Columns.merchant.like(pattern) ||
                    Transaction.Columns.description.like(pattern) ||
                    Transaction.Columns.category.like(pattern)
                )
                .order(Transaction.Columns.transactionDate.desc)
                .limit(50)
                .fetchAll(db)
        }
    }

    // MARK: - Account Overview

    func getAccountOverview() async throws -> AccountOverview {
        let summary = try await getTransactionSummary(period: .thisMonth)
        let categories = try await getCategoryBreakdown(period: .thisMonth)
        let upcoming = try await getUpcomingPayments()
        let goals = try await getGoals(status: "accepted")

        return AccountOverview(
            totalIncome: summary.totalIncome,
            totalExpenses: summary.totalExpenses,
            transactionCount: summary.transactionCount,
            topCategories: Array(categories.prefix(5)),
            upcomingPayments: upcoming.count,
            activeGoals: goals.count
        )
    }
}
