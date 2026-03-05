# Credit Card Payment Due Dates — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-detect credit card statement emails and surface payment due dates on the Dashboard and Calendar views.

**Architecture:** New `CreditCardBill` model with its own DB table, a dedicated LLM extraction prompt for statement emails, pipeline routing based on `documentType == "statement"`, and two new UI sections (Dashboard card + Calendar markers).

**Tech Stack:** Swift 6 / SwiftUI / GRDB 7 / OpenRouter LLM API

---

### Task 1: Create CreditCardBill Model

**Files:**
- Create: `LedgeIt/LedgeIt/Models/CreditCardBill.swift`

**Step 1: Create the model file**

```swift
import Foundation
import GRDB

struct CreditCardBill: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: Int64?
    var emailId: String?
    var bankName: String
    var dueDate: String
    var amountDue: Double
    var currency: String = "TWD"
    var statementPeriod: String?
    var isPaid: Bool = false
    var createdAt: String?

    static let databaseTableName = "credit_card_bills"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let emailId = Column(CodingKeys.emailId)
        static let bankName = Column(CodingKeys.bankName)
        static let dueDate = Column(CodingKeys.dueDate)
        static let amountDue = Column(CodingKeys.amountDue)
        static let currency = Column(CodingKeys.currency)
        static let statementPeriod = Column(CodingKeys.statementPeriod)
        static let isPaid = Column(CodingKeys.isPaid)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emailId = "email_id"
        case bankName = "bank_name"
        case dueDate = "due_date"
        case amountDue = "amount_due"
        case currency
        case statementPeriod = "statement_period"
        case isPaid = "is_paid"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Models/CreditCardBill.swift
git commit -m "feat: add CreditCardBill model"
```

---

### Task 2: Add Database Migration v4

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift` — add v4 migration before the closing `}` of `registerMigrations`
- Modify: `LedgeIt/LedgeIt/Database/AppDatabase.swift` — add DELETE to `resetDatabase()`

**Step 1: Add v4 migration to DatabaseMigrations.swift**

Insert after the v3 migration closing brace (before the final `}` of `registerMigrations`):

```swift
        // MARK: - v4: Credit card bills table
        migrator.registerMigration("v4") { db in
            try db.create(table: "credit_card_bills") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("email_id", .text).references("emails", onDelete: .setNull)
                t.column("bank_name", .text).notNull()
                t.column("due_date", .text).notNull()
                t.column("amount_due", .double).notNull()
                t.column("currency", .text).notNull().defaults(to: "TWD")
                t.column("statement_period", .text)
                t.column("is_paid", .integer).notNull().defaults(to: false)
                t.column("created_at", .text).defaults(sql: "CURRENT_TIMESTAMP")
            }
            try db.create(index: "idx_credit_card_bills_due_date", on: "credit_card_bills", columns: ["due_date"])
            try db.create(index: "idx_credit_card_bills_bank_name", on: "credit_card_bills", columns: ["bank_name"])
        }
```

**Step 2: Add to resetDatabase() in AppDatabase.swift**

Add this line in `resetDatabase()` before `DELETE FROM transactions`:

```swift
try db.execute(sql: "DELETE FROM credit_card_bills")
```

**Step 3: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Database/DatabaseMigrations.swift LedgeIt/LedgeIt/Database/AppDatabase.swift
git commit -m "feat: add v4 migration for credit_card_bills table"
```

---

### Task 3: Add LLM Bill Extraction Method

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/LLMProcessor.swift` — add `BillExtractionResult` struct and `extractCreditCardBill()` method

**Step 1: Add result struct after `BankInfo` (around line 60)**

```swift
    struct BillExtractionResult: Codable, Sendable {
        let bankName: String?
        let dueDate: String?
        let amountDue: Double?
        let currency: String?
        let statementPeriod: String?

        enum CodingKeys: String, CodingKey {
            case bankName = "bank_name"
            case dueDate = "due_date"
            case amountDue = "amount_due"
            case currency
            case statementPeriod = "statement_period"
        }
    }
```

**Step 2: Add extraction method after `extractTransactions()` (around line 187)**

```swift
    func extractCreditCardBill(subject: String, body: String, sender: String) async throws -> BillExtractionResult? {
        let systemPrompt = """
        You are a credit card statement parser. Extract the payment due date and amount from credit card statement emails.
        Return ONLY valid JSON, no markdown or explanation.
        """

        let truncatedBody = String(body.prefix(4000))

        let userPrompt = """
        Extract the credit card bill information from this email:

        Subject: \(subject)
        Sender: \(sender)

        Body:
        \(truncatedBody)

        Return JSON in this exact format:
        {
          "bank_name": "The bank or credit card issuer name",
          "due_date": "YYYY-MM-DD format payment deadline",
          "amount_due": 12345.00,
          "currency": "TWD or USD or other ISO currency code",
          "statement_period": "YYYY-MM-DD to YYYY-MM-DD or null"
        }

        Rules:
        - due_date is the PAYMENT DEADLINE, not the statement date
        - amount_due is the TOTAL amount due (本期應繳總金額 / total amount due / statement balance)
        - For Taiwan banks: look for 繳款截止日, 繳款期限, 最後繳款日
        - For English statements: look for "payment due date", "due by", "pay by"
        - currency: use TWD for Taiwan dollar (NT$), USD for US dollar, etc.
        - If you cannot find a due date, return null for due_date
        """

        let response = try await openRouter.chat(
            model: PFMConfig.extractionModel,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 300
        )

        return try parseJSON(BillExtractionResult.self, from: response)
    }
```

**Step 3: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/LLMProcessor.swift
git commit -m "feat: add LLM credit card bill extraction method"
```

---

### Task 4: Update IntentClassifier for Statement Detection

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/IntentClassifier.swift` — add `isCreditCardStatement` property to `ClassificationResult`

**Step 1: Add statement detection flag to ClassificationResult**

In the `ClassificationResult` struct, add:

```swift
var isCreditCardStatement: Bool = false
```

**Step 2: Add credit card statement keyword detection**

In the `classify()` method, after the rule-based classification produces a result but before returning, add statement detection logic:

```swift
        // Detect credit card statement emails
        let combinedText = (subject + " " + body).lowercased()
        let statementKeywords = [
            "帳單", "繳款", "信用卡帳單", "本期應繳", "繳款截止",
            "最後繳款日", "繳款期限", "信用卡對帳單",
            "credit card statement", "payment due", "amount due",
            "statement balance", "minimum payment due", "pay by",
            "billing statement", "account statement"
        ]
        let isStatement = statementKeywords.contains { combinedText.contains($0) }
        result.isCreditCardStatement = isStatement && result.decision != .reject
```

**Step 3: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/IntentClassifier.swift
git commit -m "feat: add credit card statement detection to IntentClassifier"
```

---

### Task 5: Update ExtractionPipeline to Route Statement Emails

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift` — add bill extraction path in `processEmail()`

**Step 1: Add bill extraction routing in processEmail()**

In `processEmail()`, after the intent classification produces an accepted result and before calling `llmProcessor.extractTransactions()`, add the statement routing logic:

```swift
            // Route credit card statements to bill extraction
            if classification.isCreditCardStatement {
                if let billResult = try await llmProcessor.extractCreditCardBill(
                    subject: email.subject ?? "",
                    body: bodyText,
                    sender: email.sender ?? ""
                ), let dueDate = billResult.dueDate, let amountDue = billResult.amountDue {
                    var bill = CreditCardBill(
                        emailId: email.id,
                        bankName: billResult.bankName ?? email.sender ?? "Unknown Bank",
                        dueDate: dueDate,
                        amountDue: amountDue,
                        currency: billResult.currency ?? "TWD",
                        statementPeriod: billResult.statementPeriod
                    )
                    try await database.db.write { db in
                        // Deduplicate: skip if same bank + same due date already exists
                        let existing = try CreditCardBill
                            .filter(CreditCardBill.Columns.bankName == bill.bankName)
                            .filter(CreditCardBill.Columns.dueDate == bill.dueDate)
                            .fetchOne(db)
                        if existing == nil {
                            try bill.insert(db)
                        }
                    }
                }
                return []  // Don't extract individual transactions from statement emails
            }
```

Insert this AFTER the classification check accepts the email and BEFORE the `extractTransactions` call. The `return []` ensures statement emails don't produce duplicate transaction records.

**Step 2: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift
git commit -m "feat: route credit card statement emails to bill extraction"
```

---

### Task 6: Add PersonalFinanceService Query Methods

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/PersonalFinanceService.swift` — add due date query and mark-as-paid methods

**Step 1: Add query methods at the end of the class (before closing `}`)**

```swift
    // MARK: - Credit Card Bills

    func getUpcomingBills() throws -> [CreditCardBill] {
        try database.db.read { db in
            let today = DateFormatters.dateToString(Date())
            let calendar = Calendar.current
            let nextMonth = calendar.date(byAdding: .month, value: 2, to: Date()) ?? Date()
            let futureDate = DateFormatters.dateToString(nextMonth)

            return try CreditCardBill
                .filter(CreditCardBill.Columns.dueDate >= today || CreditCardBill.Columns.isPaid == false)
                .filter(CreditCardBill.Columns.dueDate <= futureDate)
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }
    }

    func getAllBillsForMonth(year: Int, month: Int) throws -> [CreditCardBill] {
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
```

**Step 2: Check if DateFormatters has the helper needed**

Read `LedgeIt/LedgeIt/Utilities/DateFormatters.swift` — if `dateToString` does not exist, add a simple helper:

```swift
static func dateToString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
```

**Step 3: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Services/PersonalFinanceService.swift LedgeIt/LedgeIt/Utilities/DateFormatters.swift
git commit -m "feat: add credit card bill query and mark-as-paid methods"
```

---

### Task 7: Add Dashboard "Upcoming Bills" Section

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/DashboardView.swift`

**Step 1: Add state variable (after existing @State declarations, around line 11)**

```swift
@State private var upcomingBills: [CreditCardBill] = []
```

**Step 2: Add data loading in loadData() (after the existing service calls)**

```swift
upcomingBills = try service.getUpcomingBills()
```

**Step 3: Add the section view in body**

Insert between the velocity alert banner and the charts HStack:

```swift
                // Upcoming Bills
                if !upcomingBills.isEmpty {
                    upcomingBillsSection
                }
```

**Step 4: Add the section computed property (alongside other section views)**

```swift
    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.orange)
                Text("Upcoming Bills")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(upcomingBills) { bill in
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.18))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.bankName)
                                .font(.system(size: 13, weight: .medium))
                            Text("Due \(formatDueDate(bill.dueDate))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Days remaining or status badge
                        if bill.isPaid {
                            Text("PAID")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                        } else if let days = daysUntilDue(bill.dueDate) {
                            if days < 0 {
                                Text("OVERDUE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.red, in: Capsule())
                            } else {
                                Text("\(days)d")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(days <= 3 ? .red : days <= 7 ? .orange : .secondary)
                            }
                        }

                        Text("\(bill.currency) \(String(format: "%.2f", bill.amountDue))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))

                        // Pay toggle
                        if !bill.isPaid {
                            Button {
                                if let id = bill.id {
                                    try? PersonalFinanceService(database: AppDatabase.shared).markBillAsPaid(id)
                                    Task { loadData() }
                                }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        bill.isPaid ? Color.clear :
                            (daysUntilDue(bill.dueDate).map { $0 < 0 } ?? false)
                            ? Color.red.opacity(0.08) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
```

**Step 5: Add helper methods**

```swift
    private func formatDueDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    private func daysUntilDue(_ dateStr: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dueDate = formatter.date(from: dateStr) else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let due = calendar.startOfDay(for: dueDate)
        return calendar.dateComponents([.day], from: today, to: due).day
    }
```

**Step 6: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 7: Commit**

```bash
git add LedgeIt/LedgeIt/Views/DashboardView.swift
git commit -m "feat: add Upcoming Bills section to dashboard"
```

---

### Task 8: Add Calendar View Due Date Markers

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/CalendarView.swift`

**Step 1: Add state and computed properties (after existing state vars, around line 8)**

```swift
@State private var bills: [CreditCardBill] = []
```

After existing computed properties, add:

```swift
    private var billsByDate: [String: [CreditCardBill]] {
        Dictionary(grouping: bills, by: { $0.dueDate })
    }
```

**Step 2: Update startObservation() to also observe credit_card_bills**

After the existing `ValueObservation` for transactions, add a second observation:

```swift
        let billObservation = ValueObservation.tracking { db -> [CreditCardBill] in
            try CreditCardBill
                .order(CreditCardBill.Columns.dueDate.asc)
                .fetchAll(db)
        }

        billObservation.start(in: database.db) { error in
            print("Bill observation error: \(error)")
        } onChange: { [weak self] bills in
            Task { @MainActor in
                self?.bills = bills
            }
        }
```

Note: You'll need a second `@State private var billCancellable: AnyDatabaseCancellable?` to store this observation, and assign it properly.

**Step 3: Add due date marker in dayCell()**

In `dayCell()`, after the transaction category dots HStack, add:

```swift
                        // Due date marker
                        if let dayBills = billsByDate[dateStr], !dayBills.isEmpty {
                            let color: Color = {
                                if dayBills.allSatisfy({ $0.isPaid }) {
                                    return .green
                                }
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd"
                                if let dueDate = formatter.date(from: dateStr),
                                   dueDate < Calendar.current.startOfDay(for: Date()) {
                                    return .red
                                }
                                return .orange
                            }()
                            Image(systemName: "creditcard.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(color)
                        }
```

**Step 4: Add bill details in selectedDayDetail**

In `selectedDayDetail`, before the transaction list, add:

```swift
                    // Due date bills for this day
                    let dateStr = dayFormatter.string(from: selectedDate)
                    if let dayBills = billsByDate[dateStr], !dayBills.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Payment Due")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)

                            ForEach(dayBills) { bill in
                                HStack {
                                    Image(systemName: "creditcard.fill")
                                        .foregroundStyle(.orange)
                                        .frame(width: 20)
                                    Text(bill.bankName)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    if bill.isPaid {
                                        Text("PAID")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(.green, in: Capsule())
                                    }
                                    Text("\(bill.currency) \(String(format: "%.2f", bill.amountDue))")
                                        .font(.system(size: 12, design: .monospaced))
                                }
                            }
                        }
                        .padding(.bottom, 8)

                        Divider()
                    }
```

**Step 5: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/Views/CalendarView.swift
git commit -m "feat: add credit card due date markers to calendar view"
```

---

### Task 9: Update v3 Migration to Stop Purging Bill Emails

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift` — remove credit card bill deletion from v3

**Important context:** The v3 migration has already run on existing databases. Changing it won't re-run. However, we should remove the deletion SQL so that fresh installs and future email re-syncs don't purge statement data. For existing users, the damage is done (old bills deleted), but new statement emails will be properly extracted going forward.

**Step 1: Comment out or remove the credit card bill deletion block in v3**

In the v3 migration, remove or comment the block that deletes rows matching:
- `merchant LIKE '%銀行%' AND description LIKE '%本期應繳%'`
- `description LIKE '%自動扣繳%'`
- `description LIKE '%扣款失敗%'`
- `description LIKE '%credit card bill%'`

**Note:** Do NOT remove the deduplication logic (keeping only MIN(id) for duplicates) — that's still valuable.

**Step 2: Build to verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Database/DatabaseMigrations.swift
git commit -m "fix: stop purging credit card statement data in v3 migration"
```

---

### Task 10: Build Release and Install

**Step 1: Full release build**

Run: `cd LedgeIt && swift build -c release 2>&1 | tail -5`
Expected: `Build complete!`

**Step 2: Rebuild .app bundle**

```bash
APP="/Applications/LedgeIt.app"
cp LedgeIt/.build/release/LedgeIt "$APP/Contents/MacOS/LedgeIt"
cp -R LedgeIt/.build/release/LedgeIt_LedgeIt.bundle "$APP/Contents/Resources/"
```

**Step 3: Register and verify**

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/LedgeIt.app
```

**Step 4: Final commit with all changes**

```bash
git add -A
git commit -m "feat: complete credit card payment due dates feature"
```
