# Financial Advisory Local RAG Design

**Date:** 2026-03-05
**Status:** Approved

## Problem

The current chat system uses structured tool-calling (get_transactions, search_transactions, etc.) which only supports keyword matching and explicit filters. Two major gaps:

1. **No semantic search** — user asks "how much did I spend on dining out?" but merchants aren't categorized consistently. Keyword search misses semantically related results.
2. **No historical report retrieval** — AI-generated financial reports and advice cannot be referenced in chat. (Deferred to future iteration; transactions only for v1.)

## Solution

Add a local RAG (Retrieval-Augmented Generation) layer using:
- **sqlite-vec** — vector search SQLite extension (pure C, single file) for KNN queries
- **Apple NaturalLanguage framework** — local sentence embeddings (512-dim, zero API calls)
- **New `semantic_search` tool** — added to ChatEngine alongside existing structured tools

## Architecture

```
User query in ChatView
    |
    v
ChatEngine (tool-calling loop)
    |
    |-- LLM decides: semantic_search vs get_transactions vs search_transactions
    |
    v
semantic_search tool
    |
    v
EmbeddingService
    |-- embed query via NLEmbedding.sentenceEmbedding(for: .english)
    |-- KNN query against vec0 virtual table
    |-- return top-K transaction IDs + distances
    |
    v
FinancialQueryService.getTransactions(ids:)
    |
    v
Formatted results returned to LLM as tool response
```

## Data Model

### sqlite-vec virtual table (GRDB migration v11)

```sql
CREATE VIRTUAL TABLE transaction_embeddings USING vec0(
  embedding float[512]
);
```

- `rowid` maps 1:1 to `transactions.id`
- KNN query: `SELECT rowid, distance FROM transaction_embeddings WHERE embedding MATCH ? ORDER BY distance LIMIT ?`

### New column on `transactions`

- `embedding_version` (INTEGER, default 0) — tracks embedding state, enables re-indexing

### Text representation per transaction

```
"{merchant} {category} {description} {amount} {currency} {transactionDate}"
```

Example: `"Starbucks dining coffee 150 TWD 2026-02-15"`

## Components

### EmbeddingService (singleton actor)

Responsibilities:
1. **Generate embedding** — transaction text string -> `[Float]` via `NLEmbedding.sentenceEmbedding(for: .english)`
2. **Store embedding** — insert into `transaction_embeddings` vec0 table, update `transactions.embedding_version`
3. **Search** — embed query string, KNN against vec0, return top-K transaction IDs with distances
4. **Batch index** — find all transactions where `embedding_version = 0`, embed and store one by one

### sqlite-vec Integration

**Bundling:** Add `sqlite-vec.c` + `sqlite-vec.h` as a C target in SPM:

```
Package.swift
  Sources/
    LedgeIt/          (existing Swift code)
    CSQLiteVec/       (new C target)
      sqlite-vec.c
      sqlite-vec.h
      include/
```

**Loading:** Register sqlite-vec module with GRDB at database setup time.

### Chat Integration — `semantic_search` tool

```json
{
  "name": "semantic_search",
  "description": "Search transactions by meaning. Use when user asks about spending patterns, categories, or merchants in natural language.",
  "parameters": {
    "query": "string - natural language search query",
    "limit": "integer - max results (default 10)"
  }
}
```

**Tool selection guidance in system prompt:**
- `semantic_search` — vague/conceptual questions ("where did I spend on entertainment?", "any unusual purchases?")
- `get_transactions` / `search_transactions` — specific filters (date range, exact merchant, amount)

## Indexing Strategy

### At import time
- `ExtractionPipeline` calls `EmbeddingService.embed(transaction:)` after saving each new transaction
- One by one, non-blocking

### Batch migration (existing data)
- On app launch, check for `embedding_version = 0` transactions
- Run background task, embed one by one
- Show progress indicator ("Indexing transactions... 142/500")
- Non-blocking — chat works with partial results until complete

### Re-indexing
- Bump `CURRENT_EMBEDDING_VERSION` constant when embedding logic changes
- Batch migration logic automatically picks up stale records (`embedding_version < CURRENT_EMBEDDING_VERSION`)

## Error Handling

- `NLEmbedding` returns nil for unsupported language -> fall back to `.english`
- Embedding fails for single transaction -> skip, log warning, keep `embedding_version = 0` for retry
- sqlite-vec query fails -> `semantic_search` returns error to LLM, which can fall back to `search_transactions`

## Technology Choices

| Component | Choice | Rationale |
|---|---|---|
| Vector store | sqlite-vec (vec0) | Proper KNN indexing, scales beyond 10K, single C file, no dependencies |
| Embedding model | Apple NaturalLanguage | Local, zero API calls, zero dependencies, 512-dim sentence embeddings |
| Vector math | sqlite-vec SIMD | Built into sqlite-vec, hardware-accelerated |
| Data scope | Transactions only (v1) | Covers primary use case; reports/goals can be added later |
| Chat integration | New tool alongside existing | Non-breaking, LLM chooses best tool per query |

## Future Extensions (not in scope)

- Embed financial reports and advice
- Embed financial goals
- Embed email content / PDF statement text
- Hybrid search (FTS5 + vector) with Reciprocal Rank Fusion
