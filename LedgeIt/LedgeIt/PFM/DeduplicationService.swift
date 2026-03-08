import Foundation
import AnyLanguageModel
import GRDB

/// Smart deduplication service using rule-based scoring + LLM tiebreaker.
/// Replaces the old amount+currency+date exact-match dedup.
struct DeduplicationService: Sendable {
    private let database: AppDatabase

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Scoring Constants

    private enum Score {
        static let exactAmount: Double = 40
        static let merchantSimilarity: Double = 30
        static let sameSourceEmail: Double = 20
        static let descriptionOverlap: Double = 10

        static let autoMatchThreshold: Double = 80
        static let llmThreshold: Double = 50
    }

    // MARK: - Public API

    /// Deduplicate a batch of new transactions against the database.
    /// Returns only non-duplicate transactions. Duplicates are inserted with soft-delete.
    func deduplicate(_ transactions: [Transaction]) async throws -> [Transaction] {
        var result: [Transaction] = []

        for txn in transactions {
            let matchResult = try await findDuplicate(for: txn)
            if let (originalId, score, method, details) = matchResult {
                // Insert the duplicate with soft-delete markers and capture its ID
                var duplicate = txn
                duplicate.isDuplicateOf = originalId
                duplicate.deletedAt = ISO8601DateFormatter().string(from: Date())
                let duplicateToInsert = duplicate
                let insertedId = try await database.db.write { db -> Int64 in
                    var mutable = duplicateToInsert
                    try mutable.insert(db)
                    return mutable.id ?? db.lastInsertedRowID
                }
                // Log with real inserted ID
                try await logMatch(
                    keptId: originalId,
                    removedId: insertedId,
                    score: score,
                    method: method,
                    details: details
                )
            } else {
                result.append(txn)
            }
        }

        return result
    }

    // MARK: - Find Duplicate

    /// Returns (originalId, score, method, details) if duplicate found, nil otherwise.
    private func findDuplicate(for txn: Transaction) async throws -> (Int64, Double, String, String)? {
        guard let date = txn.transactionDate else { return nil }

        let candidates = try await findCandidates(
            amount: txn.amount,
            currency: txn.currency,
            date: date
        )

        guard !candidates.isEmpty else { return nil }

        var bestMatch: (transaction: Transaction, score: Double)?

        for candidate in candidates {
            let score = computeScore(new: txn, existing: candidate)
            if let current = bestMatch {
                if score > current.score {
                    bestMatch = (candidate, score)
                }
            } else if score >= Score.llmThreshold {
                bestMatch = (candidate, score)
            }
        }

        guard let match = bestMatch else { return nil }

        if match.score >= Score.autoMatchThreshold {
            let details = scoreDetails(new: txn, existing: match.transaction)
            guard let matchId = match.transaction.id else { return nil }
            return (matchId, match.score, "rule_match", details)
        }

        // Score 50-80: LLM tiebreaker
        let llmResult = try await llmTiebreaker(new: txn, existing: match.transaction)
        if llmResult.isDuplicate {
            guard let matchId = match.transaction.id else { return nil }
            return (matchId, match.score, "llm_match", llmResult.reason)
        }
        return nil
    }

    // MARK: - Candidate Search

    private func findCandidates(amount: Double, currency: String, date: String) async throws -> [Transaction] {
        let absAmount = abs(amount)
        let minAmount = absAmount * 0.95
        let maxAmount = absAmount * 1.05

        guard let dateObj = parseDate(date) else { return [] }
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -3, to: dateObj),
              let endDate = calendar.date(byAdding: .day, value: 3, to: dateObj) else { return [] }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)

        return try await database.db.read { db in
            try Transaction.fetchAll(db, sql: """
                SELECT * FROM transactions
                WHERE currency = ?
                AND ABS(amount) >= ? AND ABS(amount) <= ?
                AND transaction_date >= ? AND transaction_date <= ?
                AND deleted_at IS NULL
                """, arguments: [currency, minAmount, maxAmount, startStr, endStr])
        }
    }

    // MARK: - Scoring

    func computeScore(new: Transaction, existing: Transaction) -> Double {
        var score: Double = 0

        if abs(new.amount) == abs(existing.amount) {
            score += Score.exactAmount
        }

        if let m1 = new.merchant, let m2 = existing.merchant {
            let similarity = merchantSimilarity(m1, m2)
            if similarity > 0.7 {
                score += Score.merchantSimilarity * similarity
            }
        }

        if let e1 = new.emailId, let e2 = existing.emailId, e1 == e2 {
            score += Score.sameSourceEmail
        }

        if let d1 = new.description, let d2 = existing.description {
            let overlap = descriptionOverlap(d1, d2)
            score += Score.descriptionOverlap * overlap
        }

        return score
    }

    private func scoreDetails(new: Transaction, existing: Transaction) -> String {
        var details: [String: Any] = [
            "amount_match": new.amount == existing.amount,
            "new_merchant": new.merchant ?? "nil",
            "existing_merchant": existing.merchant ?? "nil"
        ]
        if let m1 = new.merchant, let m2 = existing.merchant {
            details["merchant_similarity"] = merchantSimilarity(m1, m2)
        }
        if let data = try? JSONSerialization.data(withJSONObject: details),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    // MARK: - Merchant Similarity

    static func normalizeMerchant(_ name: String) -> String {
        var result = name.lowercased()
        let suffixes = ["co.", "ltd.", "inc.", "corp.", "corporation",
                        "company", "limited", "llc", "plc"]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }
        result = result.filter { $0.isLetter || $0.isNumber }
        return result
    }

    func merchantSimilarity(_ a: String, _ b: String) -> Double {
        let na = Self.normalizeMerchant(a)
        let nb = Self.normalizeMerchant(b)

        if na == nb { return 1.0 }
        if na.isEmpty || nb.isEmpty { return 0.0 }

        let distance = levenshteinDistance(na, nb)
        let maxLen = max(na.count, nb.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[m][n]
    }

    // MARK: - Description Overlap

    private func descriptionOverlap(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " ").map(String.init))
        let wordsB = Set(b.lowercased().split(separator: " ").map(String.init))

        if wordsA.isEmpty || wordsB.isEmpty { return 0.0 }

        let intersection = wordsA.intersection(wordsB)
        let union = wordsA.union(wordsB)

        return Double(intersection.count) / Double(union.count)
    }

    // MARK: - LLM Tiebreaker

    private struct LLMResult {
        let isDuplicate: Bool
        let confidence: Double
        let reason: String
    }

    private func llmTiebreaker(new: Transaction, existing: Transaction) async throws -> LLMResult {
        let providerConfig = AIProviderConfigStore.load()
        let session = try SessionFactory.makeSession(
            assignment: providerConfig.extraction,
            config: providerConfig
        )
        let prompt = """
            Compare these two transactions and determine if they are the same purchase:

            Transaction A: \(existing.merchant ?? "Unknown") | \(String(format: "%.2f", existing.amount)) \(existing.currency) | \(existing.transactionDate ?? "no date") | \(existing.description ?? "")
            Transaction B: \(new.merchant ?? "Unknown") | \(String(format: "%.2f", new.amount)) \(new.currency) | \(new.transactionDate ?? "no date") | \(new.description ?? "")

            Answer ONLY in JSON: {"is_duplicate": true/false, "confidence": 0.0-1.0, "reason": "brief explanation"}
            """

        let response = try await session.respond(
            to: prompt,
            options: GenerationOptions(temperature: 0.0)
        )

        // Strip markdown code fences if present
        var cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isDuplicate = json["is_duplicate"] as? Bool else {
            return LLMResult(isDuplicate: false, confidence: 0, reason: "Failed to parse LLM response: \(response.content)")
        }

        let confidence = json["confidence"] as? Double ?? 0
        let reason = json["reason"] as? String ?? ""
        return LLMResult(isDuplicate: isDuplicate, confidence: confidence, reason: reason)
    }

    // MARK: - Logging

    private func logMatch(keptId: Int64, removedId: Int64, score: Double, method: String, details: String) async throws {
        let log = DedupLog(
            keptTransactionId: keptId,
            removedTransactionId: removedId,
            matchScore: score,
            matchMethod: method,
            matchDetails: details,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try await database.db.write { [log] db in
            var record = log
            try record.insert(db)
        }
    }

    // MARK: - Date Parsing

    private func parseDate(_ dateString: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dateString)
    }
}
