import Foundation
import GRDB

struct FewShotProvider: Sendable {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    /// Fetch recent user corrections as few-shot examples for the extraction prompt.
    /// Returns formatted string to append to the prompt, or nil if no corrections exist.
    func fetchFewShotExamples(limit: Int = 5) async throws -> String? {
        let corrections: [(merchant: String, original: String, corrected: String, field: String)] = try await database.db.read { db in
            // Fetch type corrections
            let typeCorrections = try Transaction
                .filter(Transaction.Columns.userCorrectedType != nil)
                .filter(Transaction.Columns.deletedAt == nil)
                .order(Transaction.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { tx -> (String, String, String, String)? in
                    guard let corrected = tx.userCorrectedType,
                          let original = tx.type,
                          corrected != original else { return nil }
                    return (tx.merchant ?? "Unknown", original, corrected, "type")
                }

            // Fetch category corrections
            let catCorrections = try Transaction
                .filter(Transaction.Columns.userCorrectedCategory != nil)
                .filter(Transaction.Columns.deletedAt == nil)
                .order(Transaction.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap { tx -> (String, String, String, String)? in
                    guard let corrected = tx.userCorrectedCategory,
                          let original = tx.category,
                          corrected != original else { return nil }
                    return (tx.merchant ?? "Unknown", original, corrected, "category")
                }

            return Array((typeCorrections + catCorrections).prefix(limit))
        }

        guard !corrections.isEmpty else { return nil }

        var lines = ["Recent corrections from the user (learn from these):"]
        for (merchant, original, corrected, field) in corrections {
            lines.append("- '\(merchant)' -> user corrected \(field) from '\(original)' to '\(corrected)'")
        }

        return lines.joined(separator: "\n")
    }
}
