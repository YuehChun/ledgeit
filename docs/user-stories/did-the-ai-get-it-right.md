# Did the AI Get It Right?

> **As a user**, I want to review AI-extracted transactions grouped by their source email, so I can verify accuracy and correct any mistakes before they affect my reports.

![Transaction Review](../../screenshots/transactions_review.png)

## The Problem

AI extraction isn't perfect. A merchant name might be slightly wrong, a category might be misclassified, or a transfer between your own accounts might be counted as an expense. Without a review step, these errors compound and make your financial reports unreliable.

## How LedgeIt Solves It

The **Review** view shows unreviewed transactions grouped by their source email:

### Email-Grouped Review

Each card shows:
- **Email header** — Sender, subject, date (e.g., "台新銀行" <pay.noted@taishinbank.com.tw>)
- **Extracted transaction** — Merchant name, date, category badge, and amount
- **View original email** — Expandable section to compare the AI extraction against the source email
- **Actions** — Mark Reviewed or Delete

### Visual Category Badges

Each transaction has a colored category badge for quick scanning:
- Purple: Utilities
- Red: Bank Fees
- Green: General
- Blue: Shopping

### Bulk Actions

- **Mark All Reviewed** — Approve all transactions at once when you've confirmed they're correct
- **Filter** — Toggle between Unreviewed and all transactions
- **Search** — Find specific transactions by merchant or description

### Transaction Count

The header shows "132 unreviewed transactions" so you always know how much review work remains.

### Why Review Matters

Reviewed transactions feed into your financial analysis, goals, and AI advisor. Catching errors early means more accurate reports and better advice downstream.
