# Transaction Review Screen Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add an email-grouped transaction review screen where users can verify LLM-extracted transactions and permanently delete incorrect ones.

**Architecture:** New GRDB migration adds `isReviewed` column to transactions table. New `TransactionReviewView` groups transactions by source email with expandable original email body. New sidebar item in ContentView. No changes to extraction pipeline or budget calculations.

**Tech Stack:** SwiftUI, GRDB (SQLite), ValueObservation for reactive updates

---

### Task 1: Add `isReviewed` column to Transaction model

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift:182` (before closing `}`)
- Modify: `LedgeIt/LedgeIt/Models/Transaction.swift:4-65`

**Step 1: Add migration v7 to DatabaseMigrations.swift**

Add after the `v6` migration block (line 181), before the closing `}` on line 182:

```swift
// MARK: - v7: Transaction review support
migrator.registerMigration("v7") { db in
    try db.alter(table: "transactions") { t in
        t.add(column: "is_reviewed", .integer).notNull().defaults(to: false)
    }
    try db.create(index: "idx_transactions_is_reviewed", on: "transactions", columns: ["is_reviewed"])
}
```

**Step 2: Add `isReviewed` field to Transaction model**

In `Models/Transaction.swift`, add to the struct (after line 19, after `rawExtraction`):

```swift
var isReviewed: Bool = false
```

Add to `Columns` enum (after line 39, after `rawExtraction`):

```swift
static let isReviewed = Column(CodingKeys.isReviewed)
```

Add to `CodingKeys` enum (after line 58, after `rawExtraction`):

```swift
case isReviewed = "is_reviewed"
```

**Step 3: Build the project to verify migration runs**

Run: Cmd+B in Xcode, or `xcodebuild -scheme LedgeIt build`
Expected: Build succeeds. App launches and migrates DB to v7.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Database/DatabaseMigrations.swift LedgeIt/LedgeIt/Models/Transaction.swift
git commit -m "feat: add isReviewed column to transactions table (migration v7)"
```

---

### Task 2: Add L10n strings for the review screen

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift:172-224`

**Step 1: Add review section strings**

Insert after the "Transaction Verification" section (after line 186, after `lowConfidence`), before the "Dashboard" section:

```swift
// MARK: - Transaction Review

var review: String { s("Review", "審核") }
var transactionReview: String { s("Transaction Review", "交易審核") }
func unreviewedCount(_ count: Int) -> String {
    s("\(count) unreviewed transactions", "\(count) 筆未審核交易")
}
var markAllReviewed: String { s("Mark All Reviewed", "全部標為已審核") }
var markReviewed: String { s("Mark Reviewed", "標為已審核") }
var viewOriginalEmail: String { s("View original email", "查看原始郵件") }
var hideOriginalEmail: String { s("Hide original email", "隱藏原始郵件") }
var deleteTransaction: String { s("Delete", "刪除") }
var deleteConfirmTitle: String { s("Delete Transaction?", "刪除交易？") }
var deleteConfirmMessage: String { s("This transaction will be permanently removed from your records.", "此交易將從您的記錄中永久刪除。") }
var filterUnreviewed: String { s("Unreviewed", "未審核") }
var filterReviewed: String { s("Reviewed", "已審核") }
var noUnreviewedTransactions: String { s("All Caught Up", "全部完成") }
var noUnreviewedDescription: String { s("No transactions need review right now.", "目前沒有需要審核的交易。") }
var fromEmail: String { s("from email", "來自郵件") }
func transactionsFromEmail(_ count: Int) -> String {
    s("\(count) transaction\(count == 1 ? "" : "s")", "\(count) 筆交易")
}
```

**Step 2: Build to verify compilation**

Run: Cmd+B
Expected: Build succeeds.

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Utilities/Localization.swift
git commit -m "feat: add L10n strings for transaction review screen"
```

---

### Task 3: Add sidebar item for Review

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:4-12` (SidebarItem enum)
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:47-53` (Data section in sidebar)
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:87-110` (detail switch)

**Step 1: Add `.review` case to SidebarItem enum**

In `ContentView.swift`, add `review` case after `transactions` (line 6):

```swift
case review = "Review"
```

Add icon case in the `icon` computed property (after `case .transactions`, line 19):

```swift
case .review: return "checkmark.circle.fill"
```

**Step 2: Add Review to sidebar Data section**

In the `Section(l10n.data)` block (around line 47-53), add after the Transactions label (after line 49):

```swift
Label(l10n.review, systemImage: SidebarItem.review.icon)
    .tag(SidebarItem.review)
```

**Step 3: Add Review to detail switch**

In the `switch selectedItem` block (around line 87-110), add after `.transactions` case (after line 91):

```swift
case .review:
    TransactionReviewView()
```

**Step 4: Build to verify — will fail because TransactionReviewView doesn't exist yet**

Expected: Compile error `Cannot find 'TransactionReviewView' in scope` — this is correct.

**Step 5: Commit (with build error noted — will resolve in Task 4)**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat: add Review sidebar item to navigation"
```

---

### Task 4: Create TransactionReviewView

**Files:**
- Create: `LedgeIt/LedgeIt/Views/TransactionReviewView.swift`

**Step 1: Create the view file**

Create `LedgeIt/LedgeIt/Views/TransactionReviewView.swift`:

```swift
import SwiftUI
import GRDB

struct TransactionReviewView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var groupedData: [EmailGroup] = []
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var searchText = ""
    @State private var filterMode: FilterMode = .unreviewed
    @State private var expandedEmails: Set<String> = []
    @State private var deleteTarget: Transaction?
    @State private var showDeleteConfirm = false

    enum FilterMode: String, CaseIterable {
        case unreviewed, reviewed, all
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.transactionReview)
                        .font(.title2)
                        .fontWeight(.bold)
                    let unreviewedTotal = groupedData.filter { !$0.isAllReviewed }.reduce(0) { $0 + $1.transactions.count }
                    Text(l10n.unreviewedCount(unreviewedTotal))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l10n.markAllReviewed) {
                    markAllReviewed()
                }
                .buttonStyle(.bordered)
                .disabled(groupedData.allSatisfy { $0.isAllReviewed })
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Filter bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                Picker("Filter", selection: $filterMode) {
                    Text(l10n.filterUnreviewed).tag(FilterMode.unreviewed)
                    Text(l10n.filterReviewed).tag(FilterMode.reviewed)
                    Text(l10n.all).tag(FilterMode.all)
                }
                .frame(width: 140)

                Text("\(groupedData.reduce(0) { $0 + $1.transactions.count })")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Content
            if groupedData.isEmpty {
                ContentUnavailableView(
                    l10n.noUnreviewedTransactions,
                    systemImage: "checkmark.seal.fill",
                    description: Text(l10n.noUnreviewedDescription)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupedData) { group in
                            EmailGroupCard(
                                group: group,
                                l10n: l10n,
                                isExpanded: expandedEmails.contains(group.id),
                                onToggleExpand: { toggleExpand(group.id) },
                                onMarkReviewed: { markEmailReviewed(group) },
                                onDeleteTransaction: { tx in
                                    deleteTarget = tx
                                    showDeleteConfirm = true
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(l10n.review)
        .onAppear { startObservation() }
        .onChange(of: searchText) { _, _ in startObservation() }
        .onChange(of: filterMode) { _, _ in startObservation() }
        .onDisappear { cancellable?.cancel() }
        .alert(l10n.deleteConfirmTitle, isPresented: $showDeleteConfirm, presenting: deleteTarget) { tx in
            Button(l10n.deleteTransaction, role: .destructive) {
                deleteTransaction(tx)
            }
            Button(l10n.cancel, role: .cancel) {}
        } message: { _ in
            Text(l10n.deleteConfirmMessage)
        }
    }

    // MARK: - Observation

    private func startObservation() {
        let filter = filterMode
        let search = searchText.isEmpty ? nil : searchText

        let observation = ValueObservation.tracking { db -> [EmailGroup] in
            // Query transactions with filter
            var txQuery = Transaction.all()
            switch filter {
            case .unreviewed:
                txQuery = txQuery.filter(Transaction.Columns.isReviewed == false)
            case .reviewed:
                txQuery = txQuery.filter(Transaction.Columns.isReviewed == true)
            case .all:
                break
            }

            if let search {
                let pattern = "%\(search)%"
                txQuery = txQuery.filter(
                    Transaction.Columns.merchant.like(pattern) ||
                    Transaction.Columns.description.like(pattern)
                )
            }

            let transactions = try txQuery
                .order(Transaction.Columns.transactionDate.desc)
                .fetchAll(db)

            // Group by emailId
            let grouped = Dictionary(grouping: transactions) { $0.emailId ?? "no-email" }

            // Fetch associated emails
            let emailIds = Set(transactions.compactMap { $0.emailId })
            let emails: [String: Email]
            if !emailIds.isEmpty {
                let emailRows = try Email
                    .filter(emailIds.contains(Email.Columns.id))
                    .fetchAll(db)
                emails = Dictionary(uniqueKeysWithValues: emailRows.map { ($0.id, $0) })
            } else {
                emails = [:]
            }

            // Also filter by email subject/sender if searching
            var filteredGrouped = grouped
            if let search {
                let pattern = search.lowercased()
                filteredGrouped = grouped.filter { key, txs in
                    // Keep if any transaction matched (already filtered above)
                    if !txs.isEmpty { return true }
                    // Or if email subject/sender matches
                    if let email = emails[key] {
                        if email.subject?.lowercased().contains(pattern) == true { return true }
                        if email.sender?.lowercased().contains(pattern) == true { return true }
                    }
                    return false
                }
            }

            // Build groups sorted by most recent transaction date
            return filteredGrouped.map { emailId, txs in
                let email = emails[emailId]
                return EmailGroup(
                    emailId: emailId,
                    email: email,
                    transactions: txs.sorted { ($0.transactionDate ?? "") > ($1.transactionDate ?? "") }
                )
            }
            .sorted { ($0.latestDate) > ($1.latestDate) }
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            print("Review observation error: \(error)")
        } onChange: { newData in
            groupedData = newData
        }
    }

    // MARK: - Actions

    private func toggleExpand(_ emailId: String) {
        if expandedEmails.contains(emailId) {
            expandedEmails.remove(emailId)
        } else {
            expandedEmails.insert(emailId)
        }
    }

    private func deleteTransaction(_ tx: Transaction) {
        guard let id = tx.id else { return }
        do {
            try AppDatabase.shared.db.write { db in
                _ = try Transaction.deleteOne(db, id: id)
            }
        } catch {
            print("Failed to delete transaction: \(error)")
        }
    }

    private func markEmailReviewed(_ group: EmailGroup) {
        let ids = group.transactions.compactMap { $0.id }
        guard !ids.isEmpty else { return }
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(ids.contains(Transaction.Columns.id))
                    .updateAll(db, Transaction.Columns.isReviewed.set(to: true))
            }
        } catch {
            print("Failed to mark reviewed: \(error)")
        }
    }

    private func markAllReviewed() {
        let allIds = groupedData.flatMap { $0.transactions.compactMap { $0.id } }
        guard !allIds.isEmpty else { return }
        do {
            try AppDatabase.shared.db.write { db in
                try Transaction
                    .filter(allIds.contains(Transaction.Columns.id))
                    .updateAll(db, Transaction.Columns.isReviewed.set(to: true))
            }
        } catch {
            print("Failed to mark all reviewed: \(error)")
        }
    }
}

// MARK: - Data Models

struct EmailGroup: Identifiable {
    let emailId: String
    let email: Email?
    let transactions: [Transaction]

    var id: String { emailId }

    var isAllReviewed: Bool {
        transactions.allSatisfy { $0.isReviewed }
    }

    var latestDate: String {
        transactions.first?.transactionDate ?? ""
    }
}

// MARK: - Email Group Card

private struct EmailGroupCard: View {
    let group: EmailGroup
    let l10n: L10n
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onMarkReviewed: () -> Void
    let onDeleteTransaction: (Transaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Email header
            HStack(spacing: 8) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(.blue)
                    .font(.callout)

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.email?.sender ?? "Unknown sender")
                        .font(.callout)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(group.email?.subject ?? "No subject")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(l10n.transactionsFromEmail(group.transactions.count))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let date = group.email?.date {
                    Text(date.prefix(10))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Divider()

            // Transactions
            ForEach(group.transactions) { tx in
                HStack(spacing: 8) {
                    if let category = tx.category {
                        CategoryIcon(category: category, size: 22)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.merchant ?? "Unknown")
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let date = tx.transactionDate {
                                Text(date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let category = tx.category {
                                CategoryBadge(category: category)
                            }
                            if tx.isReviewed {
                                Text("✓")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .foregroundStyle(.green)
                                    .background(.green.opacity(0.1), in: Capsule())
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    AmountText(amount: tx.amount, currency: tx.currency, type: tx.type)

                    Button(role: .destructive) {
                        onDeleteTransaction(tx)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 1)
            }

            // Actions row
            HStack {
                Button {
                    onToggleExpand()
                } label: {
                    Label(
                        isExpanded ? l10n.hideOriginalEmail : l10n.viewOriginalEmail,
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)

                Spacer()

                if !group.isAllReviewed {
                    Button(l10n.markReviewed) {
                        onMarkReviewed()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Expanded email body
            if isExpanded, let bodyText = group.email?.bodyText {
                Text(bodyText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
```

**Step 2: Add file to Xcode project**

If using Xcode, ensure the file is added to the LedgeIt target. Since this is a Swift Package / SPM project structure, placing it in the Views directory should auto-include it.

**Step 3: Build and run**

Run: Cmd+B, then Cmd+R
Expected: App builds. "Review" appears in sidebar under Data. Clicking it shows the review screen. If there are existing transactions, they appear grouped by email.

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/TransactionReviewView.swift
git commit -m "feat: add transaction review screen with email-grouped layout"
```

---

### Task 5: Manual testing and polish

**Step 1: Test the full flow**

1. Open the app, click "Review" in sidebar
2. Verify unreviewed transactions appear grouped by source email
3. Click "View original email" — verify email body expands
4. Click trash icon on a transaction — verify confirmation dialog appears
5. Confirm delete — verify transaction disappears and spending numbers update on Dashboard
6. Click "Mark Reviewed" on an email card — verify transactions get the ✓ badge
7. Switch filter to "Reviewed" — verify reviewed transactions appear
8. Switch filter to "Unreviewed" — verify only unreviewed remain
9. Click "Mark All Reviewed" — verify all visible transactions are marked
10. Test search — type a merchant name, verify filtering works

**Step 2: Fix any issues found during testing**

Address layout, spacing, or behavior issues as needed.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete transaction review screen implementation"
```
