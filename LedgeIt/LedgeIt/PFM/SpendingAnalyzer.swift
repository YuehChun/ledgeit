import Foundation
import GRDB

struct SpendingAnalyzer: Sendable {
    let database: AppDatabase

    // MARK: - Result Types

    struct MonthlyReport: Sendable {
        let year: Int
        let month: Int
        let totalSpending: Double
        let totalIncome: Double
        let savingsRate: Double
        let categoryBreakdown: [CategoryStat]
        let topMerchants: [MerchantStat]
        let anomalies: [AnomalyAlert]
        let transactionCount: Int
    }

    struct CategoryStat: Identifiable, Sendable {
        let id = UUID()
        let category: String
        let amount: Double
        let count: Int
        let percentage: Double
        let previousMonthAmount: Double?
        let changePercent: Double?
    }

    struct MerchantStat: Identifiable, Sendable {
        let id = UUID()
        let merchant: String
        let amount: Double
        let count: Int
    }

    struct AnomalyAlert: Identifiable, Sendable {
        let id = UUID()
        let merchant: String
        let amount: Double
        let currency: String
        let date: String
        let averageForMerchant: Double
        let deviation: Double        // how many times above average
    }

    struct MonthTrend: Identifiable, Sendable {
        let id = UUID()
        let year: Int
        let month: Int
        let label: String            // "Jan 2026"
        let spending: Double
        let income: Double
        let savingsRate: Double
    }

    // MARK: - Monthly Breakdown

    func monthlyBreakdown(year: Int, month: Int) throws -> MonthlyReport {
        let (startDate, endDate) = dateRange(year: year, month: month)

        return try database.db.read { db in
            let totalSpending = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                AND (type = 'debit' OR type IS NULL)
                """, arguments: [startDate, endDate]) ?? 0

            let totalIncome = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(amount), 0) FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                AND type = 'credit'
                """, arguments: [startDate, endDate]) ?? 0

            let transactionCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                """, arguments: [startDate, endDate]) ?? 0

            let savingsRate = totalIncome > 0 ? (totalIncome - totalSpending) / totalIncome : 0

            // Category breakdown with month-over-month comparison
            let (prevStart, prevEnd) = previousMonthRange(year: year, month: month)

            let categoryRows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(ABS(amount)) as total, COUNT(*) as cnt
                FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                AND category IS NOT NULL AND (type = 'debit' OR type IS NULL)
                GROUP BY category ORDER BY total DESC
                """, arguments: [startDate, endDate])

            let prevCategoryRows = try Row.fetchAll(db, sql: """
                SELECT category, SUM(ABS(amount)) as total
                FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                AND category IS NOT NULL AND (type = 'debit' OR type IS NULL)
                GROUP BY category
                """, arguments: [prevStart, prevEnd])

            let prevMap = Dictionary(uniqueKeysWithValues: prevCategoryRows.compactMap { row -> (String, Double)? in
                guard let cat = row["category"] as String? else { return nil }
                return (cat, row["total"] as Double? ?? 0)
            })

            let totalForPct = categoryRows.reduce(0.0) { $0 + ($1["total"] as Double? ?? 0) }
            let categories = categoryRows.map { row -> CategoryStat in
                let amount = row["total"] as Double? ?? 0
                let cat = row["category"] as String? ?? "Unknown"
                let prev = prevMap[cat]
                let change: Double? = prev.flatMap { p in p > 0 ? ((amount - p) / p) * 100 : nil }
                return CategoryStat(
                    category: cat,
                    amount: amount,
                    count: row["cnt"] as Int? ?? 0,
                    percentage: totalForPct > 0 ? (amount / totalForPct) * 100 : 0,
                    previousMonthAmount: prev,
                    changePercent: change
                )
            }

            // Top merchants
            let merchantRows = try Row.fetchAll(db, sql: """
                SELECT merchant, SUM(ABS(amount)) as total, COUNT(*) as cnt
                FROM transactions
                WHERE transaction_date >= ? AND transaction_date < ?
                AND merchant IS NOT NULL AND (type = 'debit' OR type IS NULL)
                GROUP BY merchant ORDER BY total DESC LIMIT 10
                """, arguments: [startDate, endDate])

            let merchants = merchantRows.map { row in
                MerchantStat(
                    merchant: row["merchant"] as String? ?? "Unknown",
                    amount: row["total"] as Double? ?? 0,
                    count: row["cnt"] as Int? ?? 0
                )
            }

            // Anomaly detection
            let anomalies = try detectAnomalies(db: db, startDate: startDate, endDate: endDate)

            return MonthlyReport(
                year: year,
                month: month,
                totalSpending: totalSpending,
                totalIncome: totalIncome,
                savingsRate: savingsRate,
                categoryBreakdown: categories,
                topMerchants: merchants,
                anomalies: anomalies,
                transactionCount: transactionCount
            )
        }
    }

    // MARK: - Spending Trend

    func spendingTrend(months: Int = 6) throws -> [MonthTrend] {
        let calendar = Calendar.current
        let now = Date()

        return try database.db.read { db in
            var trends: [MonthTrend] = []
            for i in (0..<months).reversed() {
                guard let date = calendar.date(byAdding: .month, value: -i, to: now) else { continue }
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                let (startDate, endDate) = dateRange(year: year, month: month)

                let spending = try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
                    WHERE transaction_date >= ? AND transaction_date < ?
                    AND (type = 'debit' OR type IS NULL)
                    """, arguments: [startDate, endDate]) ?? 0

                let income = try Double.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(amount), 0) FROM transactions
                    WHERE transaction_date >= ? AND transaction_date < ?
                    AND type = 'credit'
                    """, arguments: [startDate, endDate]) ?? 0

                let formatter = DateFormatter()
                formatter.dateFormat = "MMM yyyy"
                let savingsRate = income > 0 ? (income - spending) / income : 0

                trends.append(MonthTrend(
                    year: year,
                    month: month,
                    label: formatter.string(from: date),
                    spending: spending,
                    income: income,
                    savingsRate: savingsRate
                ))
            }
            return trends
        }
    }

    // MARK: - Anomaly Detection

    private func detectAnomalies(db: Database, startDate: String, endDate: String) throws -> [AnomalyAlert] {
        // Find transactions that are >2x the merchant's historical average
        let rows = try Row.fetchAll(db, sql: """
            SELECT t.merchant, t.amount, t.currency, t.transaction_date,
                   AVG(h.amount) as avg_amount, COUNT(h.id) as hist_count
            FROM transactions t
            JOIN transactions h ON h.merchant = t.merchant AND h.id != t.id
            WHERE t.transaction_date >= ? AND t.transaction_date < ?
            AND t.merchant IS NOT NULL
            AND (t.type = 'debit' OR t.type IS NULL)
            GROUP BY t.id
            HAVING hist_count >= 2 AND ABS(t.amount) > ABS(avg_amount) * 2
            ORDER BY ABS(t.amount) DESC
            LIMIT 5
            """, arguments: [startDate, endDate])

        return rows.map { row in
            let amount = abs(row["amount"] as Double? ?? 0)
            let avg = abs(row["avg_amount"] as Double? ?? 1)
            return AnomalyAlert(
                merchant: row["merchant"] as String? ?? "Unknown",
                amount: amount,
                currency: row["currency"] as String? ?? "USD",
                date: row["transaction_date"] as String? ?? "",
                averageForMerchant: avg,
                deviation: avg > 0 ? amount / avg : 0
            )
        }
    }

    // MARK: - Helpers

    private func dateRange(year: Int, month: Int) -> (String, String) {
        let startDate = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let endDate = String(format: "%04d-%02d-01", endYear, endMonth)
        return (startDate, endDate)
    }

    private func previousMonthRange(year: Int, month: Int) -> (String, String) {
        let prevMonth = month == 1 ? 12 : month - 1
        let prevYear = month == 1 ? year - 1 : year
        return dateRange(year: prevYear, month: prevMonth)
    }
}
