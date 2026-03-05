# Spending Budget Window Design

## Goal

Add a spending budget card to the Dashboard that shows the user's disposable balance and daily spending allowance based on their AI advisor's savings target, accounting for upcoming bills.

## Context

The Dashboard currently shows 4 stat cards (Spending, Income, Transactions, Net) plus category charts, trends, bills, etc. Users want to know at a glance: "How much can I still spend this month?" and "How much per day to stay on track?"

## Design Decisions

- **Income source**: Auto-detect from credit transactions (same as current dashboard)
- **Bill forecasting**: Subtract unpaid upcoming bills from disposable balance
- **Placement**: New full-width section below the 4 stat cards, above category chart
- **Approach**: Single budget card with disposable balance + daily allowance + progress bar. No per-category breakdown (that detail lives in Financial Analysis view).

## UI Layout

Full-width card with two main sections side by side:

**Left — Disposable Balance:**
- Large number: remaining disposable amount
- Subtitle: "of $X budget this month"
- Circular or linear progress bar showing % of budget consumed

**Right — Daily Allowance:**
- Large number: daily spending limit for remaining days
- Subtitle: "per day for N remaining days"
- Color-coded: green (on track), orange (tight), red (over budget)

**Bottom — Month progress bar:**
- Thin bar showing day-of-month / total-days-in-month

## Calculation

```
monthly_income      = sum of credit transactions this month
savings_reserve     = monthly_income * persona.savingsTarget
upcoming_bills      = sum of unpaid credit card bills due this month
spending_budget     = monthly_income - savings_reserve - upcoming_bills
spent_so_far        = sum of debit transactions this month
disposable_balance  = spending_budget - spent_so_far
days_remaining      = last_day_of_month - today + 1
daily_allowance     = max(0, disposable_balance) / days_remaining
```

## Data Sources (all existing, no new tables)

- `PersonalFinanceService.getMonthlySummary()` → totalIncome, totalSpending
- `PersonalFinanceService.getUpcomingBills()` → unpaid bills with amounts
- `AdvisorPersona.resolveWithVersions()` → savingsTarget
- `Calendar.current` → days remaining in month

## Edge Cases

- **No income**: Show placeholder "Waiting for income data"
- **Over budget**: Disposable negative, show red "Over budget by $X", daily allowance = $0
- **Last day of month**: daily allowance = full remaining disposable
- **No advisor configured**: Fall back to moderate persona (20% savings target)

## Files to Modify

- `LedgeIt/Views/DashboardView.swift` — Add SpendingBudgetCard below stat cards
- `LedgeIt/Services/PersonalFinanceService.swift` — Add `getBudgetSummary()` method
- `LedgeIt/Utilities/Localization.swift` — Add ~10 new strings

## No New Files or DB Tables Required
