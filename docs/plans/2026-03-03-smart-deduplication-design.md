# Smart Deduplication Design

**Date:** 2026-03-03
**Status:** Approved

## Problem

LedgeIt has two duplication scenarios:

1. **Transaction-to-Transaction**: Individual merchant notification emails create transactions, then the same transactions appear again when a PDF credit card statement is imported and its line items are extracted.
2. **Bill-to-Transaction Overlap**: Individual transaction emails are counted alongside the CreditCardBill total amount. When both exist for the same period, spending calculations may double-count or display incorrect amounts (e.g., 0-amount entries).

### Current State

- Dedup uses only `amount + currency + transactionDate` (exact match) — no merchant matching
- Credit card statement emails route entirely to `credit_card_bills` table (no line-item transactions)
- PDF statement imports via `StatementService` create individual `Transaction` records
- No cross-table reconciliation between transactions and bills
- Spending calculations query only `transactions` table; bills are separate

## Solution: Rule-Based Fuzzy Matching + LLM Tiebreaker

### Approach

- **Step 1**: Find candidate matches from DB using broad filters (currency, amount ±5%, date ±3 days)
- **Step 2**: Score candidates with deterministic rules (amount, merchant similarity, source, description)
- **Step 3**: If score is ambiguous (50-80), use LLM to make final decision
- **Step 4**: Soft-delete duplicates via existing `deletedAt` field, log decisions to `dedup_log`

### Why This Approach

- Fast for obvious cases (~90% of transactions match or clearly don't match)
- LLM only called for ambiguous cases (~10%), keeping costs low
- Soft-delete preserves data — wrong matches can be reviewed and restored
- Full audit trail via `dedup_log` table

## Architecture

### New Components

| Component | Responsibility |
|-----------|---------------|
| `DeduplicationService` | Core matching engine: find candidates, score, LLM tiebreaker |
| `BillReconciler` | Compare bill totals vs transaction sums for overlap detection |

### Database Changes

#### New table: `dedup_log`

```sql
CREATE TABLE dedup_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kept_transaction_id INTEGER NOT NULL,
    removed_transaction_id INTEGER NOT NULL,
    match_score REAL NOT NULL,
    match_method TEXT NOT NULL,     -- "rule_match" | "llm_match" | "llm_reject"
    match_details TEXT,             -- JSON: field-by-field breakdown
    created_at TEXT NOT NULL
);
```

#### Modified table: `transactions`

Add column: `is_duplicate_of INTEGER?` — FK pointing to the original transaction ID.

#### Modified table: `credit_card_bills`

Add columns:
- `reconciliation_status TEXT?` — "reconciled" | "gap_detected" | "unmatched"
- `reconciled_amount REAL?` — sum of matched individual transactions

## Dedup Flow: Transaction-to-Transaction

```
New transaction extracted
    |
    v
Find candidates from DB:
  - same currency
  - amount within +/-5%
  - date within +/-3 days
  - deletedAt IS NULL
    |
    v
Score each candidate:
  - Exact amount match:        +40 pts
  - Merchant similarity > 0.7: +30 pts  (normalized Levenshtein)
  - Same source email:         +20 pts
  - Description word overlap:  +10 pts
    |
    |-- Score > 80  --> Auto-match: soft-delete new txn, log "rule_match"
    |-- Score 50-80 --> LLM tiebreaker, log "llm_match" or "llm_reject"
    |-- Score < 50  --> Not duplicate, insert normally
```

### Merchant Name Normalization

Before comparing merchant names:
1. Lowercase both names
2. Strip common suffixes: Co., Ltd., Inc., Corp.
3. Remove whitespace and punctuation
4. Compare using normalized Levenshtein distance (0.0 = identical, 1.0 = completely different)

### LLM Tiebreaker

When match score is 50-80, send to LLM:

```
Compare these two transactions and determine if they are the same purchase:

Transaction A: {merchant_a} | {amount_a} {currency} | {date_a} | {description_a}
Transaction B: {merchant_b} | {amount_b} {currency} | {date_b} | {description_b}

Answer in JSON: {"is_duplicate": true/false, "confidence": 0.0-1.0, "reason": "..."}
```

Use a fast/cheap model (e.g., classification model from PFMConfig) with low max tokens.

## Dedup Flow: Bill Reconciliation

```
After transactions are extracted/updated for a billing period:
    |
    v
Sum transactions where:
  - transactionDate within bill.statementPeriod
  - type = "debit"
  - deletedAt IS NULL
    |
    v
Compare txn_sum vs bill.amountDue:
  - Difference < 5%  --> reconciliation_status = "reconciled"
  - Difference >= 5%  --> reconciliation_status = "gap_detected"
  - No transactions   --> reconciliation_status = "unmatched"
    |
    v
Update bill.reconciledAmount = txn_sum
```

## Integration Points

### ExtractionPipeline

Replace existing `deduplicateTransactions()` with call to `DeduplicationService.deduplicate()`.

### StatementService

After importing PDF statement line items, trigger dedup check against existing email-derived transactions.

### Query Layer

No changes needed — all spending queries already filter `deletedAt IS NULL`, so soft-deleted duplicates are automatically excluded from:
- `SpendingAnalyzer`
- `FinancialQueryService`
- `PersonalFinanceService`

## Timing

Deduplication runs at extraction time — when new transactions are created from emails or PDF imports. Duplicates are caught before they appear in the UI.

## Data Preservation

- Duplicates are **soft-deleted** (set `deletedAt`, set `is_duplicate_of`)
- Every decision is logged to `dedup_log` with scores and method
- Users can review and restore incorrectly flagged duplicates
- No data is ever permanently deleted by the dedup system
