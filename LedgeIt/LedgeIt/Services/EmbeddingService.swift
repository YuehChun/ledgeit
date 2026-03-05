import Foundation
import GRDB
import Embeddings

actor EmbeddingService {
    private let database: AppDatabase
    private var modelBundle: XLMRoberta.ModelBundle?

    // Bumped to 3: added "query:"/"passage:" prefixes required by E5 model
    static let currentEmbeddingVersion = 3
    private static let defaultSearchLimit = 10
    private static let modelName = "intfloat/multilingual-e5-small"

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    // MARK: - Model Loading

    private func getOrLoadModel() async throws -> XLMRoberta.ModelBundle {
        if let existing = modelBundle {
            return existing
        }
        NSLog("[EmbeddingService] Loading model: %@", Self.modelName)
        // Use HuggingFace cache directory to avoid re-downloading
        let cacheBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface")
        let bundle = try await XLMRoberta.loadModelBundle(
            from: Self.modelName,
            downloadBase: cacheBase
        )
        NSLog("[EmbeddingService] Model loaded successfully.")
        modelBundle = bundle
        return bundle
    }

    // MARK: - Embedding Generation

    /// E5 models require "query: " prefix for search queries and "passage: " prefix for documents.
    /// See: https://huggingface.co/intfloat/multilingual-e5-small
    func generateEmbedding(for text: String, isQuery: Bool) async throws -> [Float]? {
        let prefixed = isQuery ? "query: \(text)" : "passage: \(text)"
        let model = try await getOrLoadModel()
        let encoded = try model.encode(prefixed)
        let result = await encoded.cast(to: Float.self).shapedArray(of: Float.self).scalars
        return Array(result)
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
        guard let vector = try await generateEmbedding(for: text, isQuery: false) else { return }

        try await database.db.write { db in
            let vectorData = vector.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
            try db.execute(
                sql: "INSERT OR REPLACE INTO transaction_embeddings(rowid, embedding) VALUES (?, ?)",
                arguments: [id, vectorData]
            )
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
        guard let queryVector = try await generateEmbedding(for: query, isQuery: true) else {
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

    // MARK: - FTS5 Keyword Search

    func ftsSearch(query: String, limit: Int = defaultSearchLimit) async throws -> [SearchResult] {
        try await database.db.read { db in
            // FTS5 MATCH with rank scoring
            let rows = try Row.fetchAll(db, sql: """
                SELECT rowid, rank
                FROM transactions_fts
                WHERE transactions_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [query, limit])

            return rows.map { row in
                SearchResult(
                    transactionId: row["rowid"],
                    distance: row["rank"]  // FTS5 rank (lower = better match)
                )
            }
        }
    }

    // MARK: - Hybrid Search (Vector + FTS5 with RRF)

    /// Combines vector similarity and FTS5 keyword search.
    /// FTS5 matches are prioritized (keyword matches are precise), then vector-only matches fill remaining slots.
    func hybridSearch(query: String, limit: Int = defaultSearchLimit) async throws -> [SearchResult] {
        // Run both searches
        async let vecResults = search(query: query, limit: limit * 3)
        async let ftsResults = ftsSearch(query: query, limit: limit * 3)

        let vec = try await vecResults
        let fts = try await ftsResults

        let ftsIds = Set(fts.map { $0.transactionId })

        // Priority 1: FTS5 matches (keyword exact matches) — these are highly precise
        var result: [SearchResult] = fts.map { r in
            SearchResult(transactionId: r.transactionId, distance: r.distance)
        }

        // Priority 2: Vector-only matches (semantic similarity) — fill remaining slots
        for r in vec where !ftsIds.contains(r.transactionId) {
            result.append(r)
        }

        return Array(result.prefix(limit))
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
