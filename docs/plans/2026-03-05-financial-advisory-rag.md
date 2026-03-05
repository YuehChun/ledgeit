# Financial Advisory Local RAG Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add semantic transaction search to the chat interface using sqlite-vec + Apple NaturalLanguage embeddings.

**Architecture:** sqlite-vec C extension compiled as an SPM C target, loaded into GRDB at database init. EmbeddingService generates 512-dim vectors via NLEmbedding, stores them in a vec0 virtual table, and exposes KNN search. ChatEngine gets a new `semantic_search` tool.

**Tech Stack:** Swift 6.0, GRDB 7.0, sqlite-vec (pure C), Apple NaturalLanguage framework, Accelerate framework

**Design doc:** `docs/plans/2026-03-05-financial-advisory-rag-design.md`

---

### Task 1: Bundle sqlite-vec as SPM C target

**Files:**
- Create: `LedgeIt/Sources/CSQLiteVec/include/module.modulemap`
- Create: `LedgeIt/Sources/CSQLiteVec/include/sqlite-vec.h`
- Create: `LedgeIt/Sources/CSQLiteVec/sqlite-vec.c`
- Modify: `LedgeIt/Package.swift`

**Step 1: Download sqlite-vec amalgamation**

Download `sqlite-vec.c` and `sqlite-vec.h` from the sqlite-vec GitHub releases (v0.1.6 or latest).

```bash
mkdir -p LedgeIt/Sources/CSQLiteVec/include
# Download from https://github.com/asg017/sqlite-vec/releases
# Place sqlite-vec.c in LedgeIt/Sources/CSQLiteVec/
# Place sqlite-vec.h in LedgeIt/Sources/CSQLiteVec/include/
```

**Step 2: Create module.modulemap**

```c
// LedgeIt/Sources/CSQLiteVec/include/module.modulemap
module CSQLiteVec {
    header "sqlite-vec.h"
    link "sqlite3"
    export *
}
```

**Step 3: Update Package.swift**

Add a new C target `CSQLiteVec` and add it as a dependency of `LedgeIt`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LedgeIt",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "CSQLiteVec",
            path: "Sources/CSQLiteVec",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_CORE"),
            ]
        ),
        .executableTarget(
            name: "LedgeIt",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "CSQLiteVec",
            ],
            path: "LedgeIt",
            exclude: ["Info.plist", "LedgeIt.entitlements"],
            resources: [
                .process("Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "LedgeItTests",
            dependencies: [
                "LedgeIt",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests"
        ),
    ]
)
```

**Step 4: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds (or warnings only — no errors about missing sqlite-vec symbols)

**Step 5: Commit**

```bash
git add LedgeIt/Sources/CSQLiteVec/ LedgeIt/Package.swift
git commit -m "feat: bundle sqlite-vec as SPM C target"
```

---

### Task 2: Register sqlite-vec with GRDB and add migration v12

**Files:**
- Modify: `LedgeIt/LedgeIt/Database/AppDatabase.swift:9-20`
- Modify: `LedgeIt/LedgeIt/Database/DatabaseMigrations.swift:223-248`
- Modify: `LedgeIt/LedgeIt/Models/Transaction.swift:4-47`

**Step 1: Load sqlite-vec extension in AppDatabase**

In `AppDatabase.swift`, after creating the DatabaseQueue, register the sqlite-vec extension using the raw SQLite C API:

```swift
import Foundation
import GRDB
import Observation
import CSQLiteVec

@Observable
final class AppDatabase: Sendable {
    let db: DatabaseQueue

    init(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        db = try DatabaseQueue(path: path)

        // Register sqlite-vec extension
        try db.write { db in
            let code = db.withMutableSQLiteConnection { conn in
                sqlite3_vec_init(conn, nil, nil)
            }
            if code != SQLITE_OK {
                throw DatabaseError(message: "Failed to load sqlite-vec extension")
            }
        }

        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(&migrator)
        try migrator.migrate(db)
    }
    // ... rest unchanged
}
```

> **Note:** `db.withMutableSQLiteConnection` provides raw `OpaquePointer` access. If GRDB doesn't expose this directly, use `Database.sqliteConnection` inside a write block. The exact API depends on GRDB version — check `Database` for `sqliteConnection` property.

**Step 2: Add migration v12 — vec0 table + embedding_version column**

Append to `DatabaseMigrations.swift` after v11:

```swift
// MARK: - v12: RAG embedding support
migrator.registerMigration("v12") { db in
    // Add embedding version tracking to transactions
    try db.alter(table: "transactions") { t in
        t.add(column: "embedding_version", .integer).defaults(to: 0)
    }

    // Create vec0 virtual table for transaction embeddings
    // Note: sqlite-vec must be loaded before this migration runs
    try db.execute(sql: """
        CREATE VIRTUAL TABLE transaction_embeddings USING vec0(
            embedding float[512]
        )
    """)
}
```

**Step 3: Add embeddingVersion to Transaction model**

In `Transaction.swift`, add the new field:

```swift
// Add property (after isDuplicateOf):
var embeddingVersion: Int = 0

// Add to Columns enum:
static let embeddingVersion = Column(CodingKeys.embeddingVersion)

// Add to CodingKeys enum:
case embeddingVersion = "embedding_version"
```

**Step 4: Verify migration runs**

Run: `cd LedgeIt && swift build && swift run`
Expected: App starts without migration errors. Check console for no sqlite-vec errors.

**Step 5: Commit**

```bash
git add LedgeIt/LedgeIt/Database/ LedgeIt/LedgeIt/Models/Transaction.swift
git commit -m "feat: register sqlite-vec extension and add v12 migration for embeddings"
```

---

### Task 3: Create EmbeddingService

**Files:**
- Create: `LedgeIt/LedgeIt/Services/EmbeddingService.swift`

**Step 1: Create EmbeddingService**

```swift
import Foundation
import NaturalLanguage
import Accelerate
import GRDB

actor EmbeddingService {
    private let database: AppDatabase

    static let currentEmbeddingVersion = 1
    private static let defaultSearchLimit = 10

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Embedding Generation

    func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }
        guard let vector = embedding.vector(for: text) else {
            return nil
        }
        return vector.map { Float($0) }
    }

    func transactionText(_ transaction: Transaction) -> String {
        let parts = [
            transaction.merchant,
            transaction.category,
            transaction.description,
            transaction.amount.description,
            transaction.currency,
            transaction.transactionDate
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    // MARK: - Store Embedding

    func embedTransaction(_ transaction: Transaction) async throws {
        guard let id = transaction.id else { return }
        let text = transactionText(transaction)
        guard let vector = generateEmbedding(for: text) else { return }

        try await database.db.write { db in
            // Insert into vec0 virtual table
            let vectorData = vector.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
            try db.execute(
                sql: "INSERT INTO transaction_embeddings(rowid, embedding) VALUES (?, ?)",
                arguments: [id, vectorData]
            )

            // Update embedding version
            try db.execute(
                sql: "UPDATE transactions SET embedding_version = ? WHERE id = ?",
                arguments: [EmbeddingService.currentEmbeddingVersion, id]
            )
        }
    }

    // MARK: - Semantic Search

    struct SearchResult: Sendable {
        let transactionId: Int64
        let distance: Float
    }

    func search(query: String, limit: Int = defaultSearchLimit) async throws -> [SearchResult] {
        guard let queryVector = generateEmbedding(for: query) else {
            return []
        }

        let vectorData = queryVector.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        return try await database.db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT rowid, distance
                FROM transaction_embeddings
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
            """, arguments: [vectorData, limit])

            return rows.map { row in
                SearchResult(
                    transactionId: row["rowid"],
                    distance: row["distance"]
                )
            }
        }
    }

    // MARK: - Batch Indexing

    func indexUnembeddedTransactions(
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws {
        let transactions = try await database.db.read { db in
            try Transaction
                .filter(Transaction.Columns.deletedAt == nil)
                .filter(Transaction.Columns.embeddingVersion < EmbeddingService.currentEmbeddingVersion)
                .fetchAll(db)
        }

        let total = transactions.count
        guard total > 0 else { return }

        for (index, transaction) in transactions.enumerated() {
            try await embedTransaction(transaction)
            progress(index + 1, total)
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/EmbeddingService.swift
git commit -m "feat: add EmbeddingService with NLEmbedding and sqlite-vec KNN search"
```

---

### Task 4: Add getTransactions(ids:) to FinancialQueryService

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/FinancialQueryService.swift:13-44`

**Step 1: Add fetch-by-IDs method**

Add this method to `FinancialQueryService`, after the existing `getTransactions(filter:)` method:

```swift
func getTransactions(ids: [Int64]) async throws -> [Transaction] {
    guard !ids.isEmpty else { return [] }
    return try await database.db.read { db in
        try Transaction
            .filter(ids.contains(Transaction.Columns.id))
            .filter(Transaction.Columns.deletedAt == nil)
            .fetchAll(db)
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/FinancialQueryService.swift
git commit -m "feat: add getTransactions(ids:) to FinancialQueryService"
```

---

### Task 5: Add semantic_search tool to ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift:3-13` (add embeddingService property)
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift:211-308` (add tool definition)
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift:312-391` (add tool execution)
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift:172-206` (update system prompt)

**Step 1: Add EmbeddingService dependency to ChatEngine**

At the top of `ChatEngine`, add the embedding service:

```swift
actor ChatEngine {
    private let queryService: FinancialQueryService
    private let embeddingService: EmbeddingService
    private var openRouter: OpenRouterService?
    private var conversationHistory: [OpenRouterService.Message] = []

    private let model = "anthropic/claude-sonnet-4.5"
    private let maxToolIterations = 5

    init(
        queryService: FinancialQueryService = FinancialQueryService(),
        embeddingService: EmbeddingService = EmbeddingService()
    ) {
        self.queryService = queryService
        self.embeddingService = embeddingService
    }
```

**Step 2: Add semantic_search tool definition**

Add to the `toolDefinitions` array (after the `get_account_overview` tool at line ~306):

```swift
OpenRouterService.ToolDefinition(
    name: "semantic_search",
    description: "Search transactions by meaning using semantic similarity. Use when user asks vague or conceptual questions about spending patterns, categories, or merchants in natural language. For specific filters (date, amount, exact merchant), use get_transactions instead.",
    parameters: [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Natural language search query describing what to find"],
            "limit": ["type": "integer", "description": "Max results to return (default 10)"]
        ] as [String: Any],
        "required": ["query"] as [String]
    ] as [String: Any]
)
```

**Step 3: Add semantic_search tool execution**

Add a new case in the `executeTool` switch statement (before the `default` case):

```swift
case "semantic_search":
    guard let query = args["query"] as? String else {
        return "Error: query parameter is required"
    }
    let limit: Int
    if let intVal = args["limit"] as? Int {
        limit = intVal
    } else if let doubleVal = args["limit"] as? Double {
        limit = Int(doubleVal)
    } else {
        limit = 10
    }
    let results = try await embeddingService.search(query: query, limit: limit)
    if results.isEmpty {
        return "No semantically similar transactions found for: \(query)"
    }
    let ids = results.map { $0.transactionId }
    let transactions = try await queryService.getTransactions(ids: ids)
    return formatTransactions(transactions)
```

**Step 4: Update system prompt with semantic_search guidance**

In `buildSystemPrompt()`, add to the interaction guidelines section (around line 196):

```swift
// Add after "## Formatting" section:
## Tool Selection
- Use `semantic_search` when the user asks vague or conceptual questions (e.g., "where did I spend on entertainment?", "any unusual purchases?", "food-related expenses")
- Use `get_transactions` or `search_transactions` when the user specifies exact filters (date range, merchant name, amount)
- You can combine both: use semantic_search first to discover relevant transactions, then get_transactions for precise filtering
```

**Step 5: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "feat: add semantic_search tool to ChatEngine"
```

---

### Task 6: Integrate embedding into ExtractionPipeline

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift:58-63`

**Step 1: Add EmbeddingService to ExtractionPipeline**

Add the embedding service as a dependency and call it after transaction insertion. Find the transaction insertion block at lines 58-63:

```swift
// Current code:
try await database.db.write { [deduped] db in
    for txn in deduped {
        try txn.insert(db)
    }
}

// Replace with:
var savedTransactions: [Transaction] = []
try await database.db.write { [deduped] db in
    for var txn in deduped {
        try txn.insert(db)
        savedTransactions.append(txn)
    }
}

// Embed each transaction (non-blocking, errors logged not thrown)
for transaction in savedTransactions {
    do {
        try await embeddingService.embedTransaction(transaction)
    } catch {
        print("[EmbeddingService] Failed to embed transaction \(transaction.id ?? -1): \(error)")
    }
}
```

Also add the `embeddingService` property to ExtractionPipeline's init. Check how ExtractionPipeline is initialized and add:

```swift
private let embeddingService: EmbeddingService

// In init:
self.embeddingService = EmbeddingService()
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift
git commit -m "feat: embed transactions at import time in ExtractionPipeline"
```

---

### Task 7: Add batch indexing on app launch

**Files:**
- Modify: `LedgeIt/LedgeIt/LedgeItApp.swift`

**Step 1: Add background indexing task**

In the app's main view or `.onAppear` / `.task` modifier, add a background embedding task. Find the main app entry point and add:

```swift
.task {
    let embeddingService = EmbeddingService()
    do {
        try await embeddingService.indexUnembeddedTransactions { current, total in
            print("[EmbeddingService] Indexing \(current)/\(total) transactions...")
        }
    } catch {
        print("[EmbeddingService] Batch indexing failed: \(error)")
    }
}
```

This runs once on app launch. It's non-blocking since it runs in a `.task` modifier. Chat works immediately — semantic search just returns partial results until indexing completes.

**Step 2: Verify it compiles and runs**

Run: `cd LedgeIt && swift build && swift run`
Expected: App starts, console shows indexing progress if un-embedded transactions exist

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/LedgeItApp.swift
git commit -m "feat: batch index existing transactions on app launch"
```

---

### Task 8: End-to-end verification

**Step 1: Build and run the app**

Run: `cd LedgeIt && swift build && swift run`
Expected: App builds and launches without errors

**Step 2: Verify embedding indexing**

Check console output for indexing progress messages. If existing transactions exist, you should see:
```
[EmbeddingService] Indexing 1/N transactions...
[EmbeddingService] Indexing 2/N transactions...
```

**Step 3: Test semantic search in chat**

Open the chat tab and try queries like:
- "What did I spend on food recently?"
- "Any entertainment expenses?"
- "Show me my transportation costs"

Verify the LLM calls `semantic_search` and returns relevant transactions.

**Step 4: Test structured + semantic together**

Try a query like: "How much did I spend on dining in February?"
The LLM should use `semantic_search` for "dining" concepts and/or `get_transactions` with date filters.

**Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: complete local RAG integration for financial advisory chat"
```

---

## Task Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Bundle sqlite-vec as SPM C target | Package.swift, Sources/CSQLiteVec/ |
| 2 | Register extension + migration v12 | AppDatabase.swift, DatabaseMigrations.swift, Transaction.swift |
| 3 | Create EmbeddingService | Services/EmbeddingService.swift |
| 4 | Add getTransactions(ids:) | FinancialQueryService.swift |
| 5 | Add semantic_search tool to chat | ChatEngine.swift |
| 6 | Embed at import time | ExtractionPipeline.swift |
| 7 | Batch index on app launch | LedgeItApp.swift |
| 8 | End-to-end verification | All files |
