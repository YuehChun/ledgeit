# Transaction Review Screen Design

**Date**: 2026-03-01
**Problem**: LLM extraction from bank/credit card emails produces false positives — fee descriptions, service charge documents, and non-spending notifications get classified as transactions, inflating spending numbers.
**Solution**: Email-grouped review screen where users can verify extracted transactions and permanently delete incorrect ones.

## Design Decisions

- **Auto-count with review to remove**: Transactions count in spending immediately. Users remove wrong ones from the review screen.
- **Permanent delete**: Rejected transactions are deleted from the database, not soft-deleted.
- **Email-grouped layout**: Transactions grouped by source email for context. Expandable original email body for verification.
- **Minimal scope**: No changes to extraction pipeline, budget calculations, or existing views.

## Data Model

Add `isReviewed` boolean column to `Transaction` table (default: `false`).

- New extractions start as `isReviewed = false`
- User marks as reviewed after verifying (per email card or batch)
- Deleted transactions are permanently removed

## Screen Layout

New sidebar item: "Review" under Data section (between Transactions and Emails).

### Structure
- **Header**: Title + unreviewed count + "Mark All Reviewed" button
- **Controls**: Search bar + filter dropdown (Unreviewed/All/Reviewed)
- **Email cards**: Grouped by source email
  - Email subject, sender, date
  - "Reviewed" button per card
  - Expandable "View original email" section
  - Transaction rows within each card:
    - Category icon, merchant, amount, date
    - Delete button per transaction

### Interactions
- **Delete**: Permanently removes transaction from database
- **Reviewed**: Marks all remaining transactions from that email as `isReviewed = true`
- **Mark All Reviewed**: Batch operation for all visible transactions
- **View original email**: Toggles display of raw email body text
- **Filter**: Default "Unreviewed only", options for "All" and "Reviewed"
- **Search**: By merchant name, email subject, or sender

## Integration Points

### New Files
- `TransactionReviewView.swift` — The review screen
- GRDB migration to add `isReviewed` column

### Modified Files
- `ContentView.swift` — Add `.review` sidebar navigation case

### Unchanged
- ExtractionPipeline.swift (extraction logic untouched)
- PersonalFinanceService.swift (budget calculations use all transactions)
- DashboardView.swift, TransactionListView.swift
- LLMProcessor.swift, IntentClassifier.swift, AutoCategorizer.swift

## UI Patterns (matching existing app)
- Cards: `.background.secondary` + `RoundedRectangle(cornerRadius: 10)`
- Reactive data: GRDB `ValueObservation`
- Localization: `L10n(appLanguage)` for all strings
- Empty state: `ContentUnavailableView`
- Colors: semantic (red=delete, green=confirmed, blue=primary)
- Spacing: 14px padding, 8-16px gaps
