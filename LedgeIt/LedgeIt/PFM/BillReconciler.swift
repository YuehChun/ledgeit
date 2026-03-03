import Foundation
import GRDB

/// Reconciles credit card bill totals against individual transactions
/// to detect overlap and prevent double-counting.
struct BillReconciler: Sendable {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Tolerance for considering a bill "reconciled" (5%).
    private let tolerancePercent: Double = 0.05

    // MARK: - Public API

    /// Reconcile all unmatched bills that have a statement period.
    func reconcileAll() async throws {
        let bills = try await database.db.read { db in
            try CreditCardBill
                .filter(CreditCardBill.Columns.statementPeriod != nil)
                .fetchAll(db)
        }

        for bill in bills {
            try await reconcile(bill)
        }
    }

    /// Reconcile a single bill against its matching transactions.
    func reconcile(_ bill: CreditCardBill) async throws {
        guard let period = bill.statementPeriod else { return }

        // Parse statement period: "YYYY-MM-DD to YYYY-MM-DD" or "YYYY-MM to YYYY-MM"
        let dates = parsePeriod(period)
        guard let startDate = dates.start, let endDate = dates.end else { return }

        // Sum debit transactions in the period
        let txnSum: Double = try await database.db.read { db in
            let sum = try Double.fetchOne(db, sql: """
                SELECT COALESCE(SUM(ABS(amount)), 0)
                FROM transactions
                WHERE transaction_date >= ?
                AND transaction_date <= ?
                AND (type = 'debit' OR type IS NULL)
                AND deleted_at IS NULL
                """, arguments: [startDate, endDate])
            return sum ?? 0
        }

        // Determine reconciliation status
        let billAmount = bill.amountDue
        let status: String
        if txnSum == 0 {
            status = "unmatched"
        } else if billAmount == 0 {
            status = "reconciled"
        } else {
            let difference = abs(txnSum - billAmount) / billAmount
            status = difference < tolerancePercent ? "reconciled" : "gap_detected"
        }

        // Update bill
        try await database.db.write { db in
            var updated = bill
            updated.reconciliationStatus = status
            updated.reconciledAmount = txnSum
            try updated.update(db)
        }
    }

    // MARK: - Period Parsing

    /// Parse statement period string into start and end dates.
    /// Supports: "YYYY-MM-DD to YYYY-MM-DD", "YYYY-MM to YYYY-MM"
    private func parsePeriod(_ period: String) -> (start: String?, end: String?) {
        let parts = period.components(separatedBy: " to ")
        guard parts.count == 2 else { return (nil, nil) }

        let start = parts[0].trimmingCharacters(in: .whitespaces)
        let end = parts[1].trimmingCharacters(in: .whitespaces)

        // If format is YYYY-MM, expand to full date range
        if start.count == 7 {
            return (start + "-01", expandMonthEnd(end))
        }

        return (start, end)
    }

    /// Convert "YYYY-MM" to the last day of that month.
    private func expandMonthEnd(_ yearMonth: String) -> String? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        guard let date = fmt.date(from: yearMonth) else { return yearMonth }

        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: date) else { return yearMonth }
        return "\(yearMonth)-\(String(format: "%02d", range.count))"
    }
}
