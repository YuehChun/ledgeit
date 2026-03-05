# Credit Card Payment Due Dates — Design Document

**Date:** 2026-02-27
**Status:** Approved

## Problem

LedgeIt tracks past transactions but has no concept of future payment obligations. Credit card statement emails are currently excluded from extraction (v3 migration purges them). Users need to see upcoming credit card payment due dates to avoid missing payments.

## Solution: New `CreditCardBill` model + LLM extraction

Add a dedicated data model and extraction path for credit card statement emails, with UI surfaces on both the Dashboard and Calendar views.

## Data Model

New table: `credit_card_bills`

| Column | Type | Description |
|--------|------|-------------|
| `id` | INTEGER PK | Auto-increment |
| `email_id` | TEXT FK | Links to the source email |
| `bank_name` | TEXT NOT NULL | e.g., "中國信託", "Citi" |
| `due_date` | TEXT NOT NULL | "YYYY-MM-DD" |
| `amount_due` | DOUBLE NOT NULL | Total statement amount |
| `currency` | TEXT DEFAULT "TWD" | Statement currency |
| `statement_period` | TEXT | e.g., "2026-01-01 to 2026-01-31" |
| `is_paid` | INTEGER DEFAULT 0 | Whether user marked it as paid |
| `created_at` | TEXT | Timestamp |

New Swift model: `CreditCardBill` — conforms to `Codable, FetchableRecord, PersistableRecord, Identifiable`.

Credit card bills are kept separate from the `transactions` table to prevent double-counting in spending analytics.

## Email Extraction Pipeline Changes

1. **Remove v3 migration purge** of credit card statement emails.
2. **New IntentClassifier result**: `"credit_card_statement"` — detected via keywords: "帳單", "繳款", "信用卡", "statement", "payment due", "amount due".
3. **New LLM extraction prompt** in `LLMProcessor` for bill metadata:
   ```json
   {
     "bank_name": "中國信託",
     "due_date": "2026-03-15",
     "amount_due": 12345.00,
     "currency": "TWD",
     "statement_period": "2026-02-01 to 2026-02-28"
   }
   ```
4. **ExtractionPipeline routing**: When `classification == "credit_card_statement"`, extract bill metadata into `credit_card_bills` instead of `transactions`.

Supports both Chinese (Taiwan banks) and English (international banks) statement emails.

## UI: Dashboard — "Upcoming Bills" Section

Placed between Charts Row and AI Insights card on DashboardView.

- Sorted by due date (nearest first)
- Shows: bank name, due date, days remaining countdown, amount
- Unpaid bills have a checkbox to mark as paid
- Paid bills show "PAID" badge in green
- Overdue bills (past due, not paid) get red highlight and "OVERDUE" badge
- Only shows bills from the current and next month

## UI: Calendar View — Due Date Markers

- Due dates appear as a colored triangle marker in the corner of day cells (distinct from transaction category dots)
- Color coding:
  - Orange — upcoming (future)
  - Red — overdue (past due, not paid)
  - Green — paid
- Clicking a day with a due date shows bill info (bank, amount, status) above any transaction details in the right panel
