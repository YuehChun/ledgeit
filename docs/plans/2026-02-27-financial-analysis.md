# Financial Analysis & AI Advisory System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add spending behavior analysis, AI financial advisory, goal planning, and PDF attachment parsing to the LedgeIt macOS App.

**Architecture:** Modular extension of existing `PFM/` directory. New modules: PDFExtractor, SpendingAnalyzer, FinancialAdvisor, GoalPlanner, ReportGenerator. New UI views under `Views/Analysis/`. Database migration v5 adds `financial_reports` and `financial_goals` tables. All LLM calls go through existing OpenRouter integration.

**Tech Stack:** Swift 6.0, SwiftUI, GRDB 7.0, PDFKit (Apple native), OpenRouter API, Swift Charts

---

### Task 1: Database Migration v5 — financial_reports and financial_goals tables

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift`

**Step 1: Add migration v5 after the existing v4 migration**

In `DatabaseMigrations.swift`, add after the v4 migration block (after line 134):

```swift
// MARK: - v5: Financial analysis tables
migrator.registerMigration("v5") { db in
    try db.create(table: "financial_reports") { t in
        t.primaryKey("id", .text)
        t.column("report_type", .text).notNull()      // monthly, quarterly, yearly
        t.column("period_start", .text).notNull()
        t.column("period_end", .text).notNull()
        t.column("summary_json", .text).notNull()
        t.column("advice_json", .text).notNull()
        t.column("goals_json", .text).notNull()
        t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
    }
    try db.create(index: "idx_financial_reports_period", on: "financial_reports", columns: ["period_start", "period_end"])

    try db.create(table: "financial_goals") { t in
        t.primaryKey("id", .text)
        t.column("type", .text).notNull()              // short_term, long_term
        t.column("title", .text).notNull()
        t.column("description", .text).notNull()
        t.column("target_amount", .double)
        t.column("target_date", .text)
        t.column("category", .text)                    // savings, budget, investment, debt
        t.column("status", .text).notNull().defaults(to: "suggested")  // suggested, accepted, completed, dismissed
        t.column("progress", .double).notNull().defaults(to: 0)
        t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
    }
    try db.create(index: "idx_financial_goals_status", on: "financial_goals", columns: ["status"])
    try db.create(index: "idx_financial_goals_type", on: "financial_goals", columns: ["type"])
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Database/DatabaseMigrations.swift
git commit -m "feat: add database migration v5 for financial_reports and financial_goals tables"
```

---

### Task 2: FinancialReport and FinancialGoal GRDB models

**Files:**
- Create: `LedgeIt/LedgeIt/Models/FinancialReport.swift`
- Create: `LedgeIt/LedgeIt/Models/FinancialGoal.swift`

**Step 1: Create FinancialReport model**

Create `LedgeIt/LedgeIt/Models/FinancialReport.swift`:

```swift
import Foundation
import GRDB

struct FinancialReport: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var reportType: String          // monthly, quarterly, yearly
    var periodStart: String
    var periodEnd: String
    var summaryJSON: String
    var adviceJSON: String
    var goalsJSON: String
    var createdAt: String?

    static let databaseTableName = "financial_reports"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let reportType = Column(CodingKeys.reportType)
        static let periodStart = Column(CodingKeys.periodStart)
        static let periodEnd = Column(CodingKeys.periodEnd)
        static let summaryJSON = Column(CodingKeys.summaryJSON)
        static let adviceJSON = Column(CodingKeys.adviceJSON)
        static let goalsJSON = Column(CodingKeys.goalsJSON)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reportType = "report_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case summaryJSON = "summary_json"
        case adviceJSON = "advice_json"
        case goalsJSON = "goals_json"
        case createdAt = "created_at"
    }
}
```

**Step 2: Create FinancialGoal model**

Create `LedgeIt/LedgeIt/Models/FinancialGoal.swift`:

```swift
import Foundation
import GRDB

struct FinancialGoal: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: String
    var type: String                // short_term, long_term
    var title: String
    var description: String
    var targetAmount: Double?
    var targetDate: String?
    var category: String?           // savings, budget, investment, debt
    var status: String = "suggested" // suggested, accepted, completed, dismissed
    var progress: Double = 0
    var createdAt: String?

    static let databaseTableName = "financial_goals"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let title = Column(CodingKeys.title)
        static let description = Column(CodingKeys.description)
        static let targetAmount = Column(CodingKeys.targetAmount)
        static let targetDate = Column(CodingKeys.targetDate)
        static let category = Column(CodingKeys.category)
        static let status = Column(CodingKeys.status)
        static let progress = Column(CodingKeys.progress)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case category
        case status
        case progress
        case createdAt = "created_at"
    }
}
```

**Step 3: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Models/FinancialReport.swift LedgeIt/LedgeIt/Models/FinancialGoal.swift
git commit -m "feat: add FinancialReport and FinancialGoal GRDB models"
```

---

### Task 3: PDFExtractor module — parse PDF attachments for financial data

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/PDFExtractor.swift`
- Modify: `LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift`

**Context:** The existing `PDFParserService` (at `Services/PDFParserService.swift`) already extracts raw text from PDFs via PDFKit. The existing `SyncService` downloads PDF attachments and stores extracted text in the `attachments` table. However, this text is only appended to the email body for classification — it is not separately analyzed for structured financial data (like itemized bill line items). `PDFExtractor` adds a dedicated step to parse PDF text through the LLM for structured transaction extraction.

**Step 1: Create PDFExtractor module**

Create `LedgeIt/LedgeIt/PFM/PDFExtractor.swift`:

```swift
import Foundation

struct PDFExtractor: Sendable {
    let llmProcessor: LLMProcessor

    struct PDFFinancialData: Codable, Sendable {
        let transactions: [LLMProcessor.ExtractedTransaction]
        let documentType: String?
        let issuer: String?

        enum CodingKeys: String, CodingKey {
            case transactions
            case documentType = "document_type"
            case issuer
        }
    }

    /// Analyze PDF text content for structured financial data.
    /// Returns nil if the text does not contain extractable financial information.
    func extractFinancialData(
        pdfText: String,
        emailSubject: String,
        emailSender: String
    ) async throws -> PDFFinancialData? {
        let truncated = String(pdfText.prefix(8000))
        guard !truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let systemPrompt = """
        You are a financial document parser specialized in extracting transactions from PDF attachments \
        such as bank statements, credit card statements, invoices, and receipts. \
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Extract all financial transactions from this PDF document content.

        Email subject: \(emailSubject)
        Email sender: \(emailSender)

        PDF content:
        \(truncated)

        Return JSON:
        {
          "transactions": [
            {
              "amount": 123.45,
              "currency": "TWD",
              "merchant": "Store Name",
              "description": "Brief description",
              "date": "YYYY-MM-DD",
              "type": "debit|credit|transfer",
              "category_hint": "optional category hint"
            }
          ],
          "document_type": "statement|invoice|receipt|report",
          "issuer": "Bank or company name"
        }

        Rules:
        - Extract individual line-item transactions, NOT summary totals
        - For bank/credit card statements, extract each transaction row
        - Use exact amounts and dates as shown in the document
        - Skip balance entries, opening/closing balances, and subtotals
        - If no transactions found, return empty transactions array
        """

        let response = try await llmProcessor.openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: PFMConfig.llmTemperature,
            maxTokens: PFMConfig.llmMaxTokens
        )

        return try parseJSON(response)
    }

    private func parseJSON(_ raw: String) throws -> PDFFinancialData {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(PDFFinancialData.self, from: data)
            } catch {
                // Fall through to recovery
            }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(PDFFinancialData.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
```

**Step 2: Integrate PDFExtractor into ExtractionPipeline**

In `ExtractionPipeline.swift`, add a `pdfExtractor` property after line 13:

```swift
private let pdfExtractor: PDFExtractor
```

Update the `init` (replace lines 21-24):

```swift
init(database: AppDatabase, llmProcessor: LLMProcessor) {
    self.database = database
    self.llmProcessor = llmProcessor
    self.pdfExtractor = PDFExtractor(llmProcessor: llmProcessor)
}
```

In `processEmail()`, after the existing attachment text fetching (after line 115), add PDF-specific extraction. Insert before line 117 (`let senderEmail = extractEmail(from: sender)`):

```swift
// Extract structured financial data from PDF attachments
let pdfTransactions: [Transaction] = await {
    guard let text = attachmentText, !text.isEmpty else { return [] }
    do {
        guard let pdfData = try await pdfExtractor.extractFinancialData(
            pdfText: text,
            emailSubject: subject,
            emailSender: sender
        ) else { return [] }

        let now = ISO8601DateFormatter().string(from: Date())
        return pdfData.transactions.compactMap { extracted -> Transaction? in
            guard let amount = extracted.amount else { return nil }
            let category = AutoCategorizer.categorize(
                merchant: extracted.merchant,
                description: extracted.description,
                docType: pdfData.documentType,
                amount: amount
            )
            return Transaction(
                emailId: email.id,
                amount: amount,
                currency: extracted.currency ?? "USD",
                merchant: extracted.merchant,
                category: category.rawValue,
                subcategory: category.dimension,
                transactionDate: extracted.date,
                description: extracted.description,
                type: extracted.type,
                createdAt: now
            )
        }
    } catch {
        return []
    }
}()
```

Then at the end of `processEmail()`, before `return (transactions, !transactions.isEmpty)` (line 283), merge PDF transactions:

```swift
let allTransactions = transactions + pdfTransactions
return (allTransactions, !allTransactions.isEmpty)
```

(And update the return on line 283 to use `allTransactions`.)

**Step 3: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/PDFExtractor.swift LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift
git commit -m "feat: add PDFExtractor for structured financial data extraction from PDF attachments"
```

---

### Task 4: SpendingAnalyzer module — statistical analysis of spending behavior

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/SpendingAnalyzer.swift`

**Context:** This is a pure computation module (no LLM calls). It queries the SQLite database to produce statistical analysis for the FinancialAdvisor to consume. It extends beyond what `PersonalFinanceService` already provides by adding: multi-month comparison, anomaly detection, savings rate calculation, and category trend analysis.

**Step 1: Create SpendingAnalyzer**

Create `LedgeIt/LedgeIt/PFM/SpendingAnalyzer.swift`:

```swift
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
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/SpendingAnalyzer.swift
git commit -m "feat: add SpendingAnalyzer module for statistical spending analysis"
```

---

### Task 5: FinancialAdvisor module — AI-powered spending habit evaluation

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift`

**Context:** Uses OpenRouter LLM (via existing `LLMProcessor.openRouter`) to analyze spending data from a professional CFP perspective. Takes `SpendingAnalyzer.MonthlyReport` as input and produces structured advice.

**Step 1: Create FinancialAdvisor**

Create `LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift`:

```swift
import Foundation

struct FinancialAdvisor: Sendable {
    let openRouter: OpenRouterService

    // MARK: - Result Types

    struct SpendingAdvice: Codable, Sendable {
        let overallAssessment: String
        let healthScore: Int
        let positiveHabits: [String]
        let concerns: [String]
        let actionItems: [String]
        let categoryInsights: [CategoryInsight]

        enum CodingKeys: String, CodingKey {
            case overallAssessment = "overall_assessment"
            case healthScore = "health_score"
            case positiveHabits = "positive_habits"
            case concerns
            case actionItems = "action_items"
            case categoryInsights = "category_insights"
        }
    }

    struct CategoryInsight: Codable, Sendable {
        let category: String
        let assessment: String
        let suggestion: String?
    }

    // MARK: - Analyze Spending Habits

    func analyzeSpendingHabits(report: SpendingAnalyzer.MonthlyReport, trends: [SpendingAnalyzer.MonthTrend]) async throws -> SpendingAdvice {
        let categoryText = report.categoryBreakdown.map { cat in
            var line = "\(cat.category): \(String(format: "%.0f", cat.amount)) (\(String(format: "%.1f", cat.percentage))%)"
            if let change = cat.changePercent {
                line += " [MoM: \(change > 0 ? "+" : "")\(String(format: "%.0f", change))%]"
            }
            return line
        }.joined(separator: "\n")

        let merchantText = report.topMerchants.prefix(8).map {
            "\($0.merchant): \(String(format: "%.0f", $0.amount)) (\($0.count) transactions)"
        }.joined(separator: "\n")

        let anomalyText = report.anomalies.isEmpty ? "None detected" : report.anomalies.map {
            "\($0.merchant): \(String(format: "%.0f", $0.amount)) \($0.currency) (\(String(format: "%.1f", $0.deviation))x above average)"
        }.joined(separator: "\n")

        let trendText = trends.map {
            "\($0.label): spending=\(String(format: "%.0f", $0.spending)), income=\(String(format: "%.0f", $0.income)), savings_rate=\(String(format: "%.1f%%", $0.savingsRate * 100))"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a certified financial planner (CFP) providing personalized financial advice. \
        Analyze the user's spending data and provide professional, actionable advice. \
        Consider local cost of living standards and common financial planning principles. \
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Analyze this monthly spending data and provide professional financial advice.

        MONTHLY SUMMARY:
        - Total Spending: \(String(format: "%.0f", report.totalSpending))
        - Total Income: \(String(format: "%.0f", report.totalIncome))
        - Savings Rate: \(String(format: "%.1f%%", report.savingsRate * 100))
        - Transaction Count: \(report.transactionCount)

        CATEGORY BREAKDOWN:
        \(categoryText)

        TOP MERCHANTS:
        \(merchantText)

        ANOMALIES:
        \(anomalyText)

        MONTHLY TRENDS (last 6 months):
        \(trendText)

        Return JSON:
        {
          "overall_assessment": "2-3 sentence overall evaluation of financial health",
          "health_score": 75,
          "positive_habits": ["specific good habits observed"],
          "concerns": ["specific financial concerns"],
          "action_items": ["concrete, actionable steps to improve finances"],
          "category_insights": [
            {"category": "category_name", "assessment": "brief assessment", "suggestion": "specific suggestion or null"}
          ]
        }

        Rules:
        - health_score: 0-100 (0=critical, 50=needs improvement, 75=good, 90+=excellent)
        - Focus on actionable advice, not generic platitudes
        - If savings rate < 20%, flag it as a concern
        - Highlight any month-over-month spending increases > 30%
        - Provide max 3 action items, ordered by impact
        - Only include category_insights for categories with notable observations
        """

        let response = try await openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: 0.3,
            maxTokens: 2000
        )

        return try parseJSON(response)
    }

    private func parseJSON(_ raw: String) throws -> SpendingAdvice {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(SpendingAdvice.self, from: data)
            } catch { /* fall through */ }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(SpendingAdvice.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift
git commit -m "feat: add FinancialAdvisor module for AI-powered spending evaluation"
```

---

### Task 6: GoalPlanner module — AI-generated short/long-term financial goals

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/GoalPlanner.swift`

**Context:** Uses LLM to generate personalized financial goal suggestions based on spending analysis and advisor assessment. Goals are stored in the `financial_goals` table.

**Step 1: Create GoalPlanner**

Create `LedgeIt/LedgeIt/PFM/GoalPlanner.swift`:

```swift
import Foundation
import GRDB

struct GoalPlanner: Sendable {
    let openRouter: OpenRouterService
    let database: AppDatabase

    // MARK: - Result Types

    struct GoalSuggestions: Codable, Sendable {
        let shortTerm: [GoalSuggestion]
        let longTerm: [GoalSuggestion]

        enum CodingKeys: String, CodingKey {
            case shortTerm = "short_term"
            case longTerm = "long_term"
        }
    }

    struct GoalSuggestion: Codable, Sendable {
        let title: String
        let description: String
        let targetAmount: Double?
        let targetMonths: Int?
        let category: String        // savings, budget, investment, debt
        let reasoning: String

        enum CodingKeys: String, CodingKey {
            case title, description, category, reasoning
            case targetAmount = "target_amount"
            case targetMonths = "target_months"
        }
    }

    // MARK: - Suggest Goals

    func suggestGoals(
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice
    ) async throws -> GoalSuggestions {
        // Fetch existing active goals to avoid duplicates
        let existingGoals: [FinancialGoal] = try await database.db.read { db in
            try FinancialGoal
                .filter(FinancialGoal.Columns.status == "suggested" || FinancialGoal.Columns.status == "accepted")
                .fetchAll(db)
        }

        let existingText = existingGoals.isEmpty ? "None" : existingGoals.map {
            "[\($0.type)] \($0.title) - \($0.status)"
        }.joined(separator: "\n")

        let systemPrompt = """
        You are a certified financial planner creating personalized financial goals. \
        Goals should be SMART (Specific, Measurable, Achievable, Relevant, Time-bound). \
        Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Based on this financial analysis, suggest personalized financial goals.

        MONTHLY SPENDING: \(String(format: "%.0f", report.totalSpending))
        MONTHLY INCOME: \(String(format: "%.0f", report.totalIncome))
        SAVINGS RATE: \(String(format: "%.1f%%", report.savingsRate * 100))
        HEALTH SCORE: \(advice.healthScore)/100

        CONCERNS:
        \(advice.concerns.joined(separator: "\n"))

        ACTION ITEMS:
        \(advice.actionItems.joined(separator: "\n"))

        TOP SPENDING CATEGORIES:
        \(report.categoryBreakdown.prefix(5).map { "\($0.category): \(String(format: "%.0f", $0.amount)) (\(String(format: "%.1f", $0.percentage))%)" }.joined(separator: "\n"))

        EXISTING GOALS (avoid duplicates):
        \(existingText)

        Return JSON:
        {
          "short_term": [
            {
              "title": "Clear goal title",
              "description": "Detailed description with specific actions",
              "target_amount": 10000,
              "target_months": 3,
              "category": "budget",
              "reasoning": "Why this goal matters based on the data"
            }
          ],
          "long_term": [
            {
              "title": "Clear goal title",
              "description": "Detailed description",
              "target_amount": 100000,
              "target_months": 24,
              "category": "savings",
              "reasoning": "Why this goal matters"
            }
          ]
        }

        Rules:
        - short_term: 1-3 goals, achievable in 1-3 months
        - long_term: 1-2 goals, 1-3 year horizon
        - category must be one of: savings, budget, investment, debt
        - target_amount is optional (null for non-monetary goals like "track all expenses")
        - target_months: estimated time to achieve
        - Do NOT suggest goals that duplicate existing ones
        - Be specific: "Reduce dining spending to X/month" not "Spend less on food"
        """

        let response = try await openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: 0.3,
            maxTokens: 2000
        )

        return try parseJSON(response)
    }

    // MARK: - Save Goals to DB

    func saveGoals(_ suggestions: GoalSuggestions) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let calendar = Calendar.current
        let today = Date()

        try await database.db.write { db in
            for goal in suggestions.shortTerm {
                let targetDate = goal.targetMonths.flatMap {
                    calendar.date(byAdding: .month, value: $0, to: today)
                }.map { ISO8601DateFormatter().string(from: $0).prefix(10) }

                let record = FinancialGoal(
                    id: UUID().uuidString,
                    type: "short_term",
                    title: goal.title,
                    description: goal.description,
                    targetAmount: goal.targetAmount,
                    targetDate: targetDate.map(String.init),
                    category: goal.category,
                    status: "suggested",
                    progress: 0,
                    createdAt: now
                )
                try record.insert(db)
            }

            for goal in suggestions.longTerm {
                let targetDate = goal.targetMonths.flatMap {
                    calendar.date(byAdding: .month, value: $0, to: today)
                }.map { ISO8601DateFormatter().string(from: $0).prefix(10) }

                let record = FinancialGoal(
                    id: UUID().uuidString,
                    type: "long_term",
                    title: goal.title,
                    description: goal.description,
                    targetAmount: goal.targetAmount,
                    targetDate: targetDate.map(String.init),
                    category: goal.category,
                    status: "suggested",
                    progress: 0,
                    createdAt: now
                )
                try record.insert(db)
            }
        }
    }

    private func parseJSON(_ raw: String) throws -> GoalSuggestions {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(GoalSuggestions.self, from: data)
            } catch { /* fall through */ }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(GoalSuggestions.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/GoalPlanner.swift
git commit -m "feat: add GoalPlanner module for AI-generated financial goals"
```

---

### Task 7: ReportGenerator — orchestrate full analysis pipeline

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/ReportGenerator.swift`

**Context:** Orchestrates SpendingAnalyzer → FinancialAdvisor → GoalPlanner and persists results to the `financial_reports` table.

**Step 1: Create ReportGenerator**

Create `LedgeIt/LedgeIt/PFM/ReportGenerator.swift`:

```swift
import Foundation
import GRDB

@Observable
@MainActor
final class ReportGenerator {
    let database: AppDatabase
    private let analyzer: SpendingAnalyzer
    private let advisor: FinancialAdvisor
    private let goalPlanner: GoalPlanner

    var isGenerating = false
    var progress: String = ""

    init(database: AppDatabase, openRouter: OpenRouterService) {
        self.database = database
        self.analyzer = SpendingAnalyzer(database: database)
        self.advisor = FinancialAdvisor(openRouter: openRouter)
        self.goalPlanner = GoalPlanner(openRouter: openRouter, database: database)
    }

    // MARK: - Full Report Types

    struct FullReport: Sendable {
        let monthlyReport: SpendingAnalyzer.MonthlyReport
        let trends: [SpendingAnalyzer.MonthTrend]
        let advice: FinancialAdvisor.SpendingAdvice
        let goals: GoalPlanner.GoalSuggestions
    }

    // MARK: - Generate Report

    func generateMonthlyReport(year: Int, month: Int) async throws -> FullReport {
        guard !isGenerating else {
            throw ReportError.alreadyGenerating
        }
        isGenerating = true
        defer { isGenerating = false }

        // Step 1: Statistical analysis
        progress = "Analyzing spending data..."
        let report = try analyzer.monthlyBreakdown(year: year, month: month)
        let trends = try analyzer.spendingTrend(months: 6)

        // Step 2: AI financial advice
        progress = "Generating financial advice..."
        let advice = try await advisor.analyzeSpendingHabits(report: report, trends: trends)

        // Step 3: AI goal suggestions
        progress = "Planning financial goals..."
        let goals = try await goalPlanner.suggestGoals(report: report, advice: advice)

        // Step 4: Save goals to DB
        try await goalPlanner.saveGoals(goals)

        // Step 5: Persist report
        progress = "Saving report..."
        try await persistReport(
            year: year, month: month,
            report: report, advice: advice, goals: goals
        )

        progress = ""
        return FullReport(
            monthlyReport: report,
            trends: trends,
            advice: advice,
            goals: goals
        )
    }

    private func persistReport(
        year: Int, month: Int,
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice,
        goals: GoalPlanner.GoalSuggestions
    ) async throws {
        let encoder = JSONEncoder()

        let summaryDict: [String: Any] = [
            "total_spending": report.totalSpending,
            "total_income": report.totalIncome,
            "savings_rate": report.savingsRate,
            "transaction_count": report.transactionCount,
            "categories": report.categoryBreakdown.map { ["name": $0.category, "amount": $0.amount, "pct": $0.percentage] }
        ]
        let summaryJSON = String(data: try JSONSerialization.data(withJSONObject: summaryDict), encoding: .utf8) ?? "{}"
        let adviceJSON = String(data: try encoder.encode(advice), encoding: .utf8) ?? "{}"
        let goalsJSON = String(data: try encoder.encode(goals), encoding: .utf8) ?? "{}"

        let periodStart = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let periodEnd = String(format: "%04d-%02d-01", endYear, endMonth)

        let record = FinancialReport(
            id: UUID().uuidString,
            reportType: "monthly",
            periodStart: periodStart,
            periodEnd: periodEnd,
            summaryJSON: summaryJSON,
            adviceJSON: adviceJSON,
            goalsJSON: goalsJSON,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        try await database.db.write { [record] db in
            try record.insert(db)
        }
    }

    // MARK: - Fetch Saved Reports

    func getLatestReport() async throws -> FinancialReport? {
        try await database.db.read { db in
            try FinancialReport
                .order(FinancialReport.Columns.createdAt.desc)
                .fetchOne(db)
        }
    }

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

    func updateGoalStatus(goalId: String, status: String) async throws {
        try await database.db.write { db in
            if var goal = try FinancialGoal.fetchOne(db, key: goalId) {
                goal.status = status
                try goal.update(db)
            }
        }
    }
}

enum ReportError: LocalizedError {
    case alreadyGenerating

    var errorDescription: String? {
        switch self {
        case .alreadyGenerating: return "A report is already being generated"
        }
    }
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/ReportGenerator.swift
git commit -m "feat: add ReportGenerator to orchestrate full financial analysis pipeline"
```

---

### Task 8: AnalysisDashboardView — main analysis UI

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift`

**Context:** Main view for the Analysis sidebar item. Shows health score, spending advice, category insights, anomalies, and a "Generate Report" button. Uses the existing card/section patterns from `DashboardView.swift`.

**Step 1: Create AnalysisDashboardView**

Create `LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift`:

```swift
import SwiftUI
import Charts

struct AnalysisDashboardView: View {
    @State private var report: ReportGenerator.FullReport?
    @State private var isGenerating = false
    @State private var progress = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if let report {
                    healthScoreCard(report.advice)
                    adviceSection(report.advice)
                    if !report.monthlyReport.anomalies.isEmpty {
                        anomaliesSection(report.monthlyReport.anomalies)
                    }
                    categoryInsightsSection(report.advice.categoryInsights)
                    savingsTrendChart(report.trends)
                } else if !isGenerating {
                    emptyState
                }
            }
            .padding(20)
        }
        .navigationTitle("Financial Analysis")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Financial Analysis")
                    .font(.title2).fontWeight(.bold)
                Text("AI-powered spending analysis and advice")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { generateReport() } label: {
                    Label("Generate Report", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Health Score

    private func healthScoreCard(_ advice: FinancialAdvisor.SpendingAdvice) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(advice.healthScore) / 100.0)
                    .stroke(healthScoreColor(advice.healthScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(advice.healthScore)")
                        .font(.title).fontWeight(.bold).monospacedDigit()
                    Text("/ 100")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text("Financial Health Score")
                    .font(.headline)
                Text(advice.overallAssessment)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func healthScoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    // MARK: - Advice Section

    private func adviceSection(_ advice: FinancialAdvisor.SpendingAdvice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !advice.positiveHabits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Positive Habits", systemImage: "hand.thumbsup.fill")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    ForEach(advice.positiveHabits, id: \.self) { habit in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            Text(habit).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Action Items", systemImage: "bolt.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                ForEach(advice.actionItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue).font(.caption)
                        Text(item).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !advice.concerns.isEmpty {
                    Divider()
                    ForEach(advice.concerns, id: \.self) { concern in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            Text(concern).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Anomalies

    private func anomaliesSection(_ anomalies: [SpendingAnalyzer.AnomalyAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Unusual Spending", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            ForEach(anomalies) { anomaly in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomaly.merchant).font(.callout).fontWeight(.medium)
                        Text(anomaly.date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(anomaly.currency) \(String(format: "%.0f", anomaly.amount))")
                            .font(.callout).fontWeight(.semibold).monospacedDigit()
                        Text("\(String(format: "%.1f", anomaly.deviation))x avg")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Category Insights

    private func categoryInsightsSection(_ insights: [FinancialAdvisor.CategoryInsight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category Insights").font(.headline)
            ForEach(insights, id: \.category) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                            .font(.callout).fontWeight(.medium)
                        Spacer()
                    }
                    Text(insight.assessment)
                        .font(.caption).foregroundStyle(.secondary)
                    if let suggestion = insight.suggestion {
                        Text(suggestion)
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
                .padding(10)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Savings Trend

    private func savingsTrendChart(_ trends: [SpendingAnalyzer.MonthTrend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Savings Rate Trend").font(.headline)
            Chart(trends) { trend in
                LineMark(
                    x: .value("Month", trend.label),
                    y: .value("Rate", trend.savingsRate * 100)
                )
                .foregroundStyle(.green)
                .symbol(Circle())

                RuleMark(y: .value("Target", 20))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .chartYAxisLabel("Savings Rate %")
            .frame(height: 180)

            Text("Dashed line = 20% savings target")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Analysis Yet",
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Click \"Generate Report\" to create an AI-powered financial analysis.")
        )
        .padding(.top, 40)
    }

    // MARK: - Error

    private func generateReport() {
        isGenerating = true
        errorMessage = nil
        Task {
            defer { isGenerating = false; progress = "" }
            do {
                let openRouter = try OpenRouterService()
                let generator = ReportGenerator(database: AppDatabase.shared, openRouter: openRouter)
                let calendar = Calendar.current
                let now = Date()
                let year = calendar.component(.year, from: now)
                let month = calendar.component(.month, from: now)

                // Observe progress
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        progress = generator.progress
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }

                report = try await generator.generateMonthlyReport(year: year, month: month)
                progressTask.cancel()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift
git commit -m "feat: add AnalysisDashboardView with health score, advice, and insights"
```

---

### Task 9: GoalsView — financial goals list with status management

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Analysis/GoalsView.swift`

**Step 1: Create GoalsView**

Create `LedgeIt/LedgeIt/Views/Analysis/GoalsView.swift`:

```swift
import SwiftUI
import GRDB

struct GoalsView: View {
    @State private var goals: [FinancialGoal] = []
    @State private var filter: GoalFilter = .active
    @State private var cancellable: AnyDatabaseCancellable?

    enum GoalFilter: String, CaseIterable {
        case active = "Active"
        case suggested = "Suggested"
        case completed = "Completed"
        case all = "All"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Financial Goals")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Picker("Filter", selection: $filter) {
                    ForEach(GoalFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if goals.isEmpty {
                ContentUnavailableView(
                    "No Goals",
                    systemImage: "target",
                    description: Text("Generate a financial analysis to get AI-suggested goals.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        let shortTerm = goals.filter { $0.type == "short_term" }
                        let longTerm = goals.filter { $0.type == "long_term" }

                        if !shortTerm.isEmpty {
                            goalSection(title: "Short-Term Goals (1-3 months)", goals: shortTerm)
                        }
                        if !longTerm.isEmpty {
                            goalSection(title: "Long-Term Goals (1-3 years)", goals: longTerm)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Goals")
        .onAppear { startObservation() }
        .onDisappear { cancellable?.cancel() }
        .onChange(of: filter) { _, _ in loadGoals() }
    }

    private func goalSection(title: String, goals: [FinancialGoal]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            ForEach(goals, id: \.id) { goal in
                goalCard(goal)
            }
        }
    }

    private func goalCard(_ goal: FinancialGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: goalIcon(goal.category ?? "savings"))
                    .foregroundStyle(goalColor(goal.category ?? "savings"))
                Text(goal.title)
                    .font(.callout).fontWeight(.semibold)
                Spacer()
                statusBadge(goal.status)
            }

            Text(goal.description)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let amount = goal.targetAmount {
                    Label("\(String(format: "%.0f", amount))", systemImage: "dollarsign.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let date = goal.targetDate {
                    Label(date.prefix(10).description, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()

                if goal.status == "suggested" {
                    Button("Accept") { updateStatus(goal.id, "accepted") }
                        .buttonStyle(.bordered).controlSize(.mini)
                    Button("Dismiss") { updateStatus(goal.id, "dismissed") }
                        .buttonStyle(.plain).controlSize(.mini)
                        .foregroundStyle(.secondary)
                } else if goal.status == "accepted" {
                    Button("Complete") { updateStatus(goal.id, "completed") }
                        .buttonStyle(.borderedProminent).controlSize(.mini)
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusBadge(_ status: String) -> some View {
        Text(status.replacingOccurrences(of: "_", with: " ").capitalized)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status), in: Capsule())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "suggested": return .blue
        case "accepted": return .orange
        case "completed": return .green
        case "dismissed": return .gray
        default: return .secondary
        }
    }

    private func goalIcon(_ category: String) -> String {
        switch category {
        case "savings": return "banknote"
        case "budget": return "chart.pie"
        case "investment": return "chart.line.uptrend.xyaxis"
        case "debt": return "creditcard"
        default: return "target"
        }
    }

    private func goalColor(_ category: String) -> Color {
        switch category {
        case "savings": return .green
        case "budget": return .orange
        case "investment": return .blue
        case "debt": return .red
        default: return .secondary
        }
    }

    private func updateStatus(_ id: String, _ status: String) {
        Task {
            let generator = try ReportGenerator(database: AppDatabase.shared, openRouter: OpenRouterService())
            try await generator.updateGoalStatus(goalId: id, status: status)
        }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> Int in
            try FinancialGoal.fetchCount(db)
        }
        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { _ in } onChange: { _ in loadGoals() }
    }

    private func loadGoals() {
        do {
            goals = try AppDatabase.shared.db.read { db in
                var query = FinancialGoal.all()
                switch filter {
                case .active:
                    query = query.filter(FinancialGoal.Columns.status == "accepted")
                case .suggested:
                    query = query.filter(FinancialGoal.Columns.status == "suggested")
                case .completed:
                    query = query.filter(FinancialGoal.Columns.status == "completed")
                case .all:
                    break
                }
                return try query.order(FinancialGoal.Columns.createdAt.desc).fetchAll(db)
            }
        } catch {}
    }
}
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Analysis/GoalsView.swift
git commit -m "feat: add GoalsView for financial goal management"
```

---

### Task 10: Sidebar integration — add Analysis and Goals to navigation

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

**Step 1: Add new sidebar items**

In `ContentView.swift`, add two new cases to the `SidebarItem` enum (after line 8, before `case settings`):

```swift
case analysis = "Analysis"
case goals = "Goals"
```

Add icons for the new items in the `icon` computed property (before `case .settings`):

```swift
case .analysis: return "chart.bar.doc.horizontal.fill"
case .goals: return "target"
```

**Step 2: Add view routing**

In the `switch selectedItem` block inside the detail view (after the `case .calendar:` block, before `case .settings:`):

```swift
case .analysis:
    AnalysisDashboardView()
case .goals:
    GoalsView()
```

**Step 3: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat: add Analysis and Goals to sidebar navigation"
```

---

### Task 11: Add resetDatabase support for new tables

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/AppDatabase.swift`

**Step 1: Add new table cleanup to resetDatabase**

In `AppDatabase.swift` `resetDatabase()` method, add before the `DELETE FROM credit_card_bills` line:

```swift
try db.execute(sql: "DELETE FROM financial_goals")
try db.execute(sql: "DELETE FROM financial_reports")
```

**Step 2: Verify the app compiles**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Database/AppDatabase.swift
git commit -m "feat: add financial_reports and financial_goals to database reset"
```

---

## Task Dependencies

```
Task 1 (DB migration) ──► Task 2 (Models) ──► Task 4 (SpendingAnalyzer)
                                             ├► Task 5 (FinancialAdvisor)
                                             └► Task 6 (GoalPlanner)
Task 3 (PDFExtractor) — independent                     │
                                                         ▼
Tasks 4+5+6 ──► Task 7 (ReportGenerator) ──► Task 8 (AnalysisDashboardView)
                                           ├► Task 9 (GoalsView)
                                           └► Task 10 (Sidebar integration)
Task 11 (DB reset) — can run anytime after Task 1
```

## Parallel Agent Assignment

| Agent | Tasks | Worktree |
|-------|-------|----------|
| **foundation** | 1, 2, 11 | No (sequential foundation) |
| **pdf-parser** | 3 | Yes (independent) |
| **analyzer** | 4 | Yes (after foundation) |
| **ai-modules** | 5, 6 | Yes (after foundation) |
| **integration** | 7, 8, 9, 10 | No (needs all above merged) |
