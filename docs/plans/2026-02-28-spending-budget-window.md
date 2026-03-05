# Spending Budget Window Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a spending budget card to the Dashboard showing disposable balance and daily spending allowance based on the active AI advisor's savings target.

**Architecture:** Add a `getBudgetSummary()` method to `PersonalFinanceService` that computes budget math from existing transaction/bill data + advisor persona. Add a `SpendingBudgetCard` SwiftUI view to DashboardView, placed between the overview stat cards and the velocity alert. No new DB tables.

**Tech Stack:** Swift 6.0, SwiftUI, GRDB 7.0

---

### Task 1: Add `getBudgetSummary()` to PersonalFinanceService

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/PersonalFinanceService.swift`

**Step 1: Add BudgetSummary struct and method**

Add the following after the `getUpcomingBills()` method (around line 271) in `PersonalFinanceService.swift`:

```swift
// MARK: - Budget Summary

struct BudgetSummary: Sendable {
    let monthlyIncome: Double
    let savingsTarget: Double       // e.g. 0.20
    let savingsReserve: Double      // income * savingsTarget
    let unpaidBills: Double         // sum of unpaid bills due this month
    let spendingBudget: Double      // income - savingsReserve - unpaidBills
    let spentSoFar: Double
    let disposableBalance: Double   // spendingBudget - spentSoFar
    let daysRemaining: Int          // including today
    let daysInMonth: Int
    let dailyAllowance: Double      // max(0, disposable) / daysRemaining
    let currency: String
}

func getBudgetSummary(year: Int, month: Int, savingsTarget: Double) throws -> BudgetSummary? {
    try database.db.read { db in
        let startDate = String(format: "%04d-%02d-01", year, month)
        let endMonth = month == 12 ? 1 : month + 1
        let endYear = month == 12 ? year + 1 : year
        let endDate = String(format: "%04d-%02d-01", endYear, endMonth)

        let totalIncome = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(amount), 0) FROM transactions
            WHERE transaction_date >= ? AND transaction_date < ?
            AND type = 'credit'
            """, arguments: [startDate, endDate]) ?? 0

        guard totalIncome > 0 else { return nil }

        let totalSpending = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(ABS(amount)), 0) FROM transactions
            WHERE transaction_date >= ? AND transaction_date < ?
            AND (type = 'debit' OR type IS NULL)
            """, arguments: [startDate, endDate]) ?? 0

        let unpaidBills = try Double.fetchOne(db, sql: """
            SELECT COALESCE(SUM(amount_due), 0) FROM credit_card_bills
            WHERE due_date >= ? AND due_date < ?
            AND is_paid = 0
            """, arguments: [startDate, endDate]) ?? 0

        let currency = try String.fetchOne(db, sql: """
            SELECT currency FROM transactions
            WHERE transaction_date >= ? AND transaction_date < ?
            LIMIT 1
            """, arguments: [startDate, endDate]) ?? "TWD"

        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now)!
        let daysInMonth = range.count
        let today = calendar.component(.day, from: now)
        let daysRemaining = max(1, daysInMonth - today + 1)

        let savingsReserve = totalIncome * savingsTarget
        let spendingBudget = totalIncome - savingsReserve - unpaidBills
        let disposable = spendingBudget - totalSpending
        let daily = max(0, disposable) / Double(daysRemaining)

        return BudgetSummary(
            monthlyIncome: totalIncome,
            savingsTarget: savingsTarget,
            savingsReserve: savingsReserve,
            unpaidBills: unpaidBills,
            spendingBudget: max(0, spendingBudget),
            spentSoFar: totalSpending,
            disposableBalance: disposable,
            daysRemaining: daysRemaining,
            daysInMonth: daysInMonth,
            dailyAllowance: daily,
            currency: currency
        )
    }
}
```

**Step 2: Build to verify compilation**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/Services/PersonalFinanceService.swift
git commit -m "feat: add getBudgetSummary() to PersonalFinanceService"
```

---

### Task 2: Add localization strings for the budget card

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift`

**Step 1: Add strings**

Add the following after the existing `// MARK: - Dashboard` section (after line 194, the `savingsRate` property):

```swift
var spendingBudget: String { s("Spending Budget", "消費預算") }
var disposableBalance: String { s("Disposable Balance", "可動用餘額") }
var dailyAllowance: String { s("Daily Allowance", "每日可消費") }
var ofBudget: String { s("of budget this month", "本月預算") }
func perDayForDays(_ days: Int) -> String {
    s("per day for \(days) remaining days", "剩餘 \(days) 天，每日額度")
}
var overBudget: String { s("Over Budget", "超出預算") }
func overBudgetBy(_ amount: String) -> String {
    s("Over budget by \(amount)", "超出預算 \(amount)")
}
var waitingForIncome: String { s("Waiting for income data", "等待收入資料") }
var waitingForIncomeDesc: String { s("Income transactions will appear after email sync.", "收入交易紀錄將在郵件同步後出現。") }
var budgetUsed: String { s("Budget Used", "已使用預算") }
var monthProgress: String { s("Month Progress", "月份進度") }
```

**Step 2: Build to verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/Utilities/Localization.swift
git commit -m "feat: add localization strings for spending budget card"
```

---

### Task 3: Add SpendingBudgetCard to DashboardView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/DashboardView.swift`

**Step 1: Add state variable and load call**

In `DashboardView`, add this state variable after line 17 (`@State private var primaryCurrency`):

```swift
@State private var budgetSummary: PersonalFinanceService.BudgetSummary?
@AppStorage("advisorPersonaId") private var personaId = "moderate"
@AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
@AppStorage("customRiskLevel") private var customRiskLevel = "medium"
@AppStorage("appLanguage") private var appLanguage = "en"
private var l10n: L10n { L10n(appLanguage) }
```

In the `loadData()` method, add after the `upcomingBills` assignment (after line 110):

```swift
let persona = AdvisorPersona.resolveWithVersions(
    id: personaId,
    customSavingsTarget: customSavingsTarget,
    customRiskLevel: customRiskLevel
)
budgetSummary = try service.getBudgetSummary(year: year, month: month, savingsTarget: persona.savingsTarget)
```

**Step 2: Insert the budget card in the body**

In the `body`, insert the budget card right after `overviewCards(summary)` (after line 23) and before the velocity alert check:

```swift
spendingBudgetCard
```

**Step 3: Add the card view**

Add this new computed property after the `overviewCards` method (after line 129):

```swift
// MARK: - Spending Budget

@ViewBuilder
private var spendingBudgetCard: some View {
    if let budget = budgetSummary {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "wallet.bifold.fill")
                    .foregroundStyle(.blue)
                Text(l10n.spendingBudget)
                    .font(.headline)
                Spacer()
                Text("\(Int(budget.savingsTarget * 100))% \(l10n.savingsRate)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.blue.opacity(0.1), in: Capsule())
            }

            HStack(spacing: 20) {
                // Left: Disposable Balance
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.disposableBalance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(budget.currency) \(String(format: "%.0f", budget.disposableBalance))")
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(budget.disposableBalance >= 0 ? .primary : .red)
                    if budget.disposableBalance < 0 {
                        Text(l10n.overBudgetBy("\(budget.currency) \(String(format: "%.0f", abs(budget.disposableBalance)))"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("\(l10n.ofBudget): \(budget.currency) \(String(format: "%.0f", budget.spendingBudget))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 50)

                // Right: Daily Allowance
                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.dailyAllowance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(budget.currency) \(String(format: "%.0f", budget.dailyAllowance))")
                        .font(.title)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(budgetHealthColor(budget))
                    Text(l10n.perDayForDays(budget.daysRemaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Budget usage progress bar
            VStack(spacing: 4) {
                HStack {
                    Text(l10n.budgetUsed)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    let usedPct = budget.spendingBudget > 0
                        ? min(budget.spentSoFar / budget.spendingBudget, 1.5) : 0
                    Text("\(String(format: "%.0f", budget.spentSoFar)) / \(String(format: "%.0f", budget.spendingBudget))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    let usedRatio = budget.spendingBudget > 0
                        ? budget.spentSoFar / budget.spendingBudget : 0
                    let clampedRatio = min(max(usedRatio, 0), 1.0)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.quaternary)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(budgetBarColor(usedRatio))
                            .frame(width: geo.size.width * clampedRatio, height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Month progress
            VStack(spacing: 4) {
                HStack {
                    Text(l10n.monthProgress)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    let dayOfMonth = budget.daysInMonth - budget.daysRemaining + 1
                    Text("\(dayOfMonth) / \(budget.daysInMonth)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { geo in
                    let dayOfMonth = budget.daysInMonth - budget.daysRemaining + 1
                    let ratio = Double(dayOfMonth) / Double(budget.daysInMonth)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.quaternary)
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.secondary.opacity(0.5))
                            .frame(width: geo.size.width * ratio, height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    } else {
        // No income placeholder
        HStack(spacing: 12) {
            Image(systemName: "wallet.bifold")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.spendingBudget)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(l10n.waitingForIncomeDesc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private func budgetHealthColor(_ budget: PersonalFinanceService.BudgetSummary) -> Color {
    guard budget.spendingBudget > 0 else { return .red }
    let remainingRatio = budget.disposableBalance / budget.spendingBudget
    let timeRatio = Double(budget.daysRemaining) / Double(budget.daysInMonth)
    // If remaining budget ratio >= time ratio, you're on track
    if remainingRatio >= timeRatio * 0.8 { return .green }
    if remainingRatio >= timeRatio * 0.4 { return .orange }
    return .red
}

private func budgetBarColor(_ usedRatio: Double) -> Color {
    if usedRatio <= 0.6 { return .green }
    if usedRatio <= 0.85 { return .orange }
    return .red
}
```

**Step 4: Build to verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 5: Commit**

```bash
git add LedgeIt/Views/DashboardView.swift
git commit -m "feat: add spending budget card to dashboard"
```

---

### Task 4: Visual verification

**Step 1: Build the app bundle**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && bash build.sh`

**Step 2: Launch and verify**

Run: `open .build/LedgeIt.app`

Verify:
- Dashboard shows the spending budget card below the 4 stat cards
- Disposable balance shows a dollar amount
- Daily allowance shows per-day amount with remaining days
- Budget used progress bar shows proportion spent
- Month progress thin bar shows day position in month
- If no income data: shows "Waiting for income data" placeholder
- Colors change based on budget health (green/orange/red)

**Step 3: Deploy to Applications**

Run: `cp -R .build/LedgeIt.app /Applications/LedgeIt.app`
