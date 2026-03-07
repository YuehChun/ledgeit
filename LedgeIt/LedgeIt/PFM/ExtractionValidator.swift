import Foundation

struct ExtractionValidator: Sendable {

    struct ValidatedTransaction: Sendable {
        let transaction: LLMProcessor.ExtractedTransaction
        let correctedType: String?
        let correctedCurrency: String
        let correctedDate: String?
        let correctedAmount: Double
        let wasModified: Bool
        let modifications: [String]
    }

    /// Validate and correct extracted transactions. Returns only valid transactions.
    static func validate(
        _ transactions: [LLMProcessor.ExtractedTransaction],
        emailDate: String?
    ) -> [ValidatedTransaction] {
        transactions.compactMap { validate($0, emailDate: emailDate) }
    }

    private static func validate(
        _ tx: LLMProcessor.ExtractedTransaction,
        emailDate: String?
    ) -> ValidatedTransaction? {
        guard let amount = tx.amount, amount != 0 else { return nil }

        var correctedType = tx.type?.lowercased()
        var correctedCurrency = tx.currency ?? ""
        var correctedDate = tx.date
        var correctedAmount = amount
        var modifications: [String] = []

        // Fix negative amounts — keep absolute value, preserve type
        if correctedAmount < 0 {
            correctedAmount = abs(correctedAmount)
            modifications.append("amount_sign_fixed")
        }

        // Correct type based on merchant/description keywords
        let merchantLower = (tx.merchant ?? "").lowercased()
        let descLower = (tx.description ?? "").lowercased()
        let combined = merchantLower + " " + descLower

        let debitSignals = ["payment", "purchase", "charge", "fee", "subscription",
                            "bill", "order", "checkout", "paid"]
        let creditSignals = ["salary", "refund", "cashback", "reimbursement",
                             "deposit", "credited", "reversal", "payroll"]

        if correctedType == "credit" && debitSignals.contains(where: { combined.contains($0) })
            && !creditSignals.contains(where: { combined.contains($0) }) {
            correctedType = "debit"
            modifications.append("type_corrected_to_debit")
        }

        if correctedType == "debit" && creditSignals.contains(where: { combined.contains($0) })
            && !debitSignals.contains(where: { combined.contains($0) }) {
            correctedType = "credit"
            modifications.append("type_corrected_to_credit")
        }

        // Default empty currency to TWD
        if correctedCurrency.isEmpty {
            correctedCurrency = "TWD"
            modifications.append("currency_defaulted_to_TWD")
        }

        // Fix invalid dates — try multiple formats, fallback to email date
        if let dateStr = correctedDate, !isValidDate(dateStr) {
            if let parsed = tryParseDate(dateStr) {
                correctedDate = parsed
                modifications.append("date_format_fixed")
            } else {
                correctedDate = emailDate
                if emailDate != nil {
                    modifications.append("date_fallback_to_email")
                }
            }
        } else if correctedDate == nil || correctedDate?.isEmpty == true {
            correctedDate = emailDate
            if emailDate != nil {
                modifications.append("date_fallback_to_email")
            }
        }

        return ValidatedTransaction(
            transaction: tx,
            correctedType: correctedType,
            correctedCurrency: correctedCurrency,
            correctedDate: correctedDate,
            correctedAmount: correctedAmount,
            wasModified: !modifications.isEmpty,
            modifications: modifications
        )
    }

    private static func isValidDate(_ dateStr: String) -> Bool {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dateStr) != nil
    }

    static func tryParseDate(_ dateStr: String) -> String? {
        let formats = [
            "yyyy-MM-dd", "yyyy/MM/dd", "dd/MM/yyyy", "MM/dd/yyyy",
            "dd-MM-yyyy", "MM-dd-yyyy", "yyyyMMdd", "dd.MM.yyyy"
        ]
        let fmt = DateFormatter()
        let outFmt = DateFormatter()
        outFmt.dateFormat = "yyyy-MM-dd"

        for format in formats {
            fmt.dateFormat = format
            if let date = fmt.date(from: dateStr) {
                return outFmt.string(from: date)
            }
        }
        return nil
    }
}
