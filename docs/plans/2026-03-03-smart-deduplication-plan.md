# Smart Deduplication Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a rule-based fuzzy matching + LLM tiebreaker deduplication system that prevents duplicate transactions and reconciles credit card bill totals against individual transactions.

**Architecture:** New `DeduplicationService` replaces the existing 3-field dedup in `ExtractionPipeline`. It scores candidates on amount, merchant similarity, source email, and description overlap, using LLM only for ambiguous cases (score 50-80). A separate `BillReconciler` compares bill totals vs transaction sums. Both integrate at extraction time.

**Tech Stack:** Swift 6.0, GRDB 7.0, OpenRouter API (classification model for LLM tiebreaker)

**Design doc:** `docs/plans/2026-03-03-smart-deduplication-design.md`

---

### Task 1: Database Migration v11 — dedup_log table + new columns

**Files:**
- Modify: `LedgeIt/Database/DatabaseMigrations.swift:221` (add v11 after v10)
- Modify: `LedgeIt/Models/Transaction.swift` (add `isDuplicateOf` column)
- Modify: `LedgeIt/Models/CreditCardBill.swift` (add reconciliation columns)

**Step 1: Add migration v11 to DatabaseMigrations.swift**

After line 221 (closing brace of v10), add:

```swift
// MARK: - v11: Smart deduplication support
migrator.registerMigration("v11") { db in
    // Dedup audit log
    try db.create(table: "dedup_log") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("kept_transaction_id", .integer).notNull()
        t.column("removed_transaction_id", .integer).notNull()
        t.column("match_score", .double).notNull()
        t.column("match_method", .text).notNull()
        t.column("match_details", .text)
        t.column("created_at", .text).notNull()
    }
    try db.create(index: "idx_dedup_log_removed", on: "dedup_log", columns: ["removed_transaction_id"])

    // Link duplicate to its original
    try db.alter(table: "transactions") { t in
        t.add(column: "is_duplicate_of", .integer)
    }

    // Bill reconciliation tracking
    try db.alter(table: "credit_card_bills") { t in
        t.add(column: "reconciliation_status", .text)
        t.add(column: "reconciled_amount", .double)
    }
}
```

**Step 2: Add `isDuplicateOf` to Transaction model**

In `LedgeIt/Models/Transaction.swift`:

Add property after `deletedAt` (line 22):
```swift
var isDuplicateOf: Int64?
```

Add to `Columns` enum after `deletedAt` (line 44):
```swift
static let isDuplicateOf = Column(CodingKeys.isDuplicateOf)
```

Add to `CodingKeys` enum after `deletedAt` (line 65):
```swift
case isDuplicateOf = "is_duplicate_of"
```

**Step 3: Add reconciliation columns to CreditCardBill model**

In `LedgeIt/Models/CreditCardBill.swift`:

Add properties after `createdAt`:
```swift
var reconciliationStatus: String?
var reconciledAmount: Double?
```

Add to `Columns` enum:
```swift
static let reconciliationStatus = Column(CodingKeys.reconciliationStatus)
static let reconciledAmount = Column(CodingKeys.reconciledAmount)
```

Add to `CodingKeys` enum:
```swift
case reconciliationStatus = "reconciliation_status"
case reconciledAmount = "reconciled_amount"
```

**Step 4: Create Dedup log model**

Create new file `LedgeIt/Models/DedupLog.swift`:

```swift
import Foundation
import GRDB

struct DedupLog: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var keptTransactionId: Int64
    var removedTransactionId: Int64
    var matchScore: Double
    var matchMethod: String
    var matchDetails: String?
    var createdAt: String

    static let databaseTableName = "dedup_log"

    enum CodingKeys: String, CodingKey {
        case id
        case keptTransactionId = "kept_transaction_id"
        case removedTransactionId = "removed_transaction_id"
        case matchScore = "match_score"
        case matchMethod = "match_method"
        case matchDetails = "match_details"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

**Step 5: Build and verify**

Run: `cd LedgeIt && swift build`
Expected: Build succeeds with no errors.

**Step 6: Commit**

```bash
git add -A
git commit -m "feat: add database migration v11 for smart deduplication support"
```

---

### Task 2: DeduplicationService — Core matching engine

**Files:**
- Create: `LedgeIt/PFM/DeduplicationService.swift`

**Step 1: Create DeduplicationService**

Create `LedgeIt/PFM/DeduplicationService.swift`:

```swift
import Foundation
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
            let duplicateOf = try await findDuplicate(for: txn)
            if let originalId = duplicateOf {
                // Insert the duplicate with soft-delete markers
                var duplicate = txn
                duplicate.isDuplicateOf = originalId
                duplicate.deletedAt = ISO8601DateFormatter().string(from: Date())
                try await database.db.write { db in
                    try duplicate.insert(db)
                }
            } else {
                result.append(txn)
            }
        }

        return result
    }

    // MARK: - Find Duplicate

    /// Check if a transaction matches an existing one in the DB.
    /// Returns the ID of the original transaction if a match is found, nil otherwise.
    private func findDuplicate(for txn: Transaction) async throws -> Int64? {
        guard let date = txn.transactionDate else { return nil }

        // Step 1: Find candidates — broad filters
        let candidates = try await findCandidates(
            amount: txn.amount,
            currency: txn.currency,
            date: date
        )

        guard !candidates.isEmpty else { return nil }

        // Step 2: Score each candidate
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

        // Step 3: Decide based on score
        if match.score >= Score.autoMatchThreshold {
            // Auto-match: log and return
            try await logMatch(
                keptId: match.transaction.id!,
                removedTxn: txn,
                score: match.score,
                method: "rule_match",
                details: scoreDetails(new: txn, existing: match.transaction)
            )
            return match.transaction.id
        }

        // Score 50-80: LLM tiebreaker
        let llmResult = try await llmTiebreaker(new: txn, existing: match.transaction)
        if llmResult.isDuplicate {
            try await logMatch(
                keptId: match.transaction.id!,
                removedTxn: txn,
                score: match.score,
                method: "llm_match",
                details: llmResult.reason
            )
            return match.transaction.id
        } else {
            try await logMatch(
                keptId: match.transaction.id!,
                removedTxn: txn,
                score: match.score,
                method: "llm_reject",
                details: llmResult.reason
            )
            return nil
        }
    }

    // MARK: - Candidate Search

    /// Find transactions in DB that could potentially match (broad filters).
    private func findCandidates(amount: Double, currency: String, date: String) async throws -> [Transaction] {
        let minAmount = amount * 0.95
        let maxAmount = amount * 1.05

        guard let dateObj = parseDate(date) else { return [] }
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .day, value: -3, to: dateObj),
              let endDate = calendar.date(byAdding: .day, value: 3, to: dateObj) else { return [] }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let startStr = fmt.string(from: startDate)
        let endStr = fmt.string(from: endDate)

        return try await database.db.read { db in
            try Transaction
                .filter(Transaction.Columns.currency == currency)
                .filter(Transaction.Columns.amount >= minAmount)
                .filter(Transaction.Columns.amount <= maxAmount)
                .filter(Transaction.Columns.transactionDate >= startStr)
                .filter(Transaction.Columns.transactionDate <= endStr)
                .filter(Transaction.Columns.deletedAt == nil)
                .fetchAll(db)
        }
    }

    // MARK: - Scoring

    /// Compute a match score (0-100) between a new and existing transaction.
    func computeScore(new: Transaction, existing: Transaction) -> Double {
        var score: Double = 0

        // Exact amount match: +40
        if new.amount == existing.amount {
            score += Score.exactAmount
        }

        // Merchant similarity: +30 (scaled by similarity ratio)
        if let m1 = new.merchant, let m2 = existing.merchant {
            let similarity = merchantSimilarity(m1, m2)
            if similarity > 0.7 {
                score += Score.merchantSimilarity * similarity
            }
        }

        // Same source email: +20
        if let e1 = new.emailId, let e2 = existing.emailId, e1 == e2 {
            score += Score.sameSourceEmail
        }

        // Description word overlap: +10 (scaled by overlap ratio)
        if let d1 = new.description, let d2 = existing.description {
            let overlap = descriptionOverlap(d1, d2)
            score += Score.descriptionOverlap * overlap
        }

        return score
    }

    /// Build a JSON string with field-by-field score breakdown.
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

    /// Normalize a merchant name for comparison.
    static func normalizeMerchant(_ name: String) -> String {
        var result = name.lowercased()
        // Strip common suffixes
        let suffixes = ["co.", "ltd.", "inc.", "corp.", "corporation",
                        "company", "limited", "llc", "plc"]
        for suffix in suffixes {
            if result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
            }
        }
        // Remove non-alphanumeric characters (keep CJK characters)
        result = result.filter { $0.isLetter || $0.isNumber }
        return result
    }

    /// Compute similarity ratio (0.0 = completely different, 1.0 = identical).
    func merchantSimilarity(_ a: String, _ b: String) -> Double {
        let na = Self.normalizeMerchant(a)
        let nb = Self.normalizeMerchant(b)

        if na == nb { return 1.0 }
        if na.isEmpty || nb.isEmpty { return 0.0 }

        // Normalized Levenshtein distance
        let distance = levenshteinDistance(na, nb)
        let maxLen = max(na.count, nb.count)
        return 1.0 - Double(distance) / Double(maxLen)
    }

    /// Classic Levenshtein distance.
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

    /// Compute word overlap ratio between two descriptions.
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

    /// Call LLM to determine if two transactions are the same purchase.
    private func llmTiebreaker(new: Transaction, existing: Transaction) async throws -> LLMResult {
        let router = try OpenRouterService()
        let prompt = """
            Compare these two transactions and determine if they are the same purchase:

            Transaction A: \(existing.merchant ?? "Unknown") | \(String(format: "%.2f", existing.amount)) \(existing.currency) | \(existing.transactionDate ?? "no date") | \(existing.description ?? "")
            Transaction B: \(new.merchant ?? "Unknown") | \(String(format: "%.2f", new.amount)) \(new.currency) | \(new.transactionDate ?? "no date") | \(new.description ?? "")

            Answer ONLY in JSON: {"is_duplicate": true/false, "confidence": 0.0-1.0, "reason": "brief explanation"}
            """

        let response = try await router.complete(
            model: PFMConfig.classificationModel,
            messages: [.user(prompt)],
            temperature: 0.0,
            maxTokens: 200
        )

        // Parse LLM response
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isDuplicate = json["is_duplicate"] as? Bool else {
            return LLMResult(isDuplicate: false, confidence: 0, reason: "Failed to parse LLM response: \(response)")
        }

        let confidence = json["confidence"] as? Double ?? 0
        let reason = json["reason"] as? String ?? ""
        return LLMResult(isDuplicate: isDuplicate, confidence: confidence, reason: reason)
    }

    // MARK: - Logging

    /// Log a dedup decision to the dedup_log table.
    private func logMatch(keptId: Int64, removedTxn: Transaction, score: Double, method: String, details: String) async throws {
        // removedTxn may not have an ID yet if not inserted; use 0 as placeholder
        let removedId = removedTxn.id ?? 0
        let log = DedupLog(
            keptTransactionId: keptId,
            removedTransactionId: removedId,
            matchScore: score,
            matchMethod: method,
            matchDetails: details,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        try await database.db.write { db in
            var mutableLog = log
            try mutableLog.insert(db)
        }
    }

    // MARK: - Date Parsing

    private func parseDate(_ dateString: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: dateString)
    }
}
```

**Step 2: Build and verify**

Run: `cd LedgeIt && swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LedgeIt/PFM/DeduplicationService.swift
git commit -m "feat: add DeduplicationService with fuzzy matching and LLM tiebreaker"
```

---

### Task 3: BillReconciler — Bill vs transaction overlap detection

**Files:**
- Create: `LedgeIt/PFM/BillReconciler.swift`

**Step 1: Create BillReconciler**

Create `LedgeIt/PFM/BillReconciler.swift`:

```swift
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
        let status: String
        if txnSum == 0 {
            status = "unmatched"
        } else {
            let difference = abs(txnSum - bill.amountDue) / bill.amountDue
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
```

**Step 2: Build and verify**

Run: `cd LedgeIt && swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LedgeIt/PFM/BillReconciler.swift
git commit -m "feat: add BillReconciler for bill vs transaction overlap detection"
```

---

### Task 4: Integrate into ExtractionPipeline

**Files:**
- Modify: `LedgeIt/PFM/ExtractionPipeline.swift:7` (add dedup service property)
- Modify: `LedgeIt/PFM/ExtractionPipeline.swift:49-52` (replace old dedup call)
- Modify: `LedgeIt/PFM/ExtractionPipeline.swift:326-348` (remove old deduplicateTransactions method)
- Modify: `LedgeIt/PFM/ExtractionPipeline.swift:219-245` (trigger bill reconciliation after bill insert)

**Step 1: Add dedup service as property**

In `ExtractionPipeline.swift`, add after `pdfExtractor` declaration (line 14):
```swift
private let deduplicationService: DeduplicationService
private let billReconciler: BillReconciler
```

Update `init` (line 22-26) to initialize them:
```swift
init(database: AppDatabase, llmProcessor: LLMProcessor) {
    self.database = database
    self.llmProcessor = llmProcessor
    self.pdfExtractor = PDFExtractor(llmProcessor: llmProcessor)
    self.deduplicationService = DeduplicationService(database: database)
    self.billReconciler = BillReconciler(database: database)
}
```

**Step 2: Replace dedup call in processUnprocessedEmails()**

Replace line 51-52:
```swift
// Dedup: filter out transactions that already exist in DB (same amount + currency + date)
let deduped = try await deduplicateTransactions(transactions)
```

With:
```swift
// Smart dedup: fuzzy matching + LLM tiebreaker
let deduped = try await deduplicationService.deduplicate(transactions)
```

**Step 3: Add bill reconciliation after credit card bill insert**

After the credit card bill insert block (around line 237-244), add:
```swift
// Trigger bill reconciliation
if let insertedBill = try CreditCardBill
    .filter(CreditCardBill.Columns.bankName == bill.bankName)
    .filter(CreditCardBill.Columns.dueDate == bill.dueDate)
    .fetchOne(db) {
    Task {
        try? await billReconciler.reconcile(insertedBill)
    }
}
```

Note: The bill reconciliation runs in a detached Task because we're inside a `db.write` block at this point. Alternatively, move the reconciliation call outside the write block.

**Step 4: Remove old deduplicateTransactions method**

Delete lines 326-348 (the entire `deduplicateTransactions` method and its comment block):
```swift
// MARK: - Deduplication

/// Filter out transactions that already exist in the DB (same amount + currency + date)
private func deduplicateTransactions(_ transactions: [Transaction]) async throws -> [Transaction] {
    // ... entire method
}
```

**Step 5: Build and verify**

Run: `cd LedgeIt && swift build`
Expected: Build succeeds.

**Step 6: Commit**

```bash
git add LedgeIt/PFM/ExtractionPipeline.swift
git commit -m "feat: integrate DeduplicationService into ExtractionPipeline"
```

---

### Task 5: Integrate into StatementService

**Files:**
- Modify: `LedgeIt/Services/StatementService.swift:129-157` (add dedup before insert)

**Step 1: Add dedup to saveTransactions()**

In `StatementService.swift`, add a property:
```swift
private let deduplicationService = DeduplicationService()
```

Refactor `saveTransactions()` (line 129-157) to run dedup before DB insert:

```swift
func saveTransactions(_ extracted: [ExtractedTransaction], filename: String, bankName: String?) async throws {
    let now = ISO8601DateFormatter().string(from: Date())

    // Build Transaction objects
    var transactions: [Transaction] = extracted.map { tx in
        Transaction(
            amount: tx.amount,
            currency: tx.currency,
            merchant: tx.merchant,
            category: tx.category,
            subcategory: tx.subcategory,
            transactionDate: tx.transactionDate,
            description: tx.description,
            type: tx.type,
            transferType: tx.transferType,
            transferMetadata: tx.transferMetadata,
            createdAt: now
        )
    }

    // Smart dedup against existing transactions
    let deduped = try await deduplicationService.deduplicate(transactions)

    // Save non-duplicate transactions
    try await database.db.write { db in
        for var txn in deduped {
            try txn.insert(db)
        }
        var record = StatementImport(
            filename: filename,
            bankName: bankName,
            transactionCount: deduped.count,
            importedAt: now,
            status: "done"
        )
        try record.insert(db)
    }

    // Reconcile any bills that overlap with this statement's period
    let reconciler = BillReconciler()
    try await reconciler.reconcileAll()
}
```

**Step 2: Build and verify**

Run: `cd LedgeIt && swift build`
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LedgeIt/Services/StatementService.swift
git commit -m "feat: integrate smart dedup into StatementService PDF imports"
```

---

### Task 6: Add Xcode project file references (if needed)

**Context:** This project uses both SPM and Xcode. New `.swift` files need to be discoverable by the build system.

**Step 1: Check if new files are picked up by the build**

Run: `cd LedgeIt && swift build`

If the build succeeds, the SPM-based build found them. Skip this task.

If the build fails with "file not found" errors for `DedupLog.swift`, `DeduplicationService.swift`, or `BillReconciler.swift`, add them to the Xcode project:

Check the `.pbxproj` file for how existing files are referenced and add the new files following the same pattern.

**Step 2: Commit if changes were made**

```bash
git add -A
git commit -m "chore: add new dedup files to Xcode project"
```

---

### Task 7: Build, launch, and verify end-to-end

**Step 1: Full clean build**

```bash
cd LedgeIt && swift build
```

**Step 2: Launch and test**

```bash
bash build.sh && open /Applications/LedgeIt.app
```

Or run directly:
```bash
swift run
```

**Step 3: Verify by importing a PDF statement**

1. Import a PDF credit card statement that contains transactions already in the DB
2. Check that duplicates are soft-deleted (not visible in transaction list)
3. Check that `dedup_log` table has entries (via SQLite browser or debug logging)
4. Verify spending totals are not double-counted

**Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: resolve any build or runtime issues from dedup integration"
```
