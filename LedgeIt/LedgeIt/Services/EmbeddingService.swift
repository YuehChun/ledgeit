import Foundation
import GRDB
import Embeddings

actor EmbeddingService {
    private let database: AppDatabase
    private var modelBundle: XLMRoberta.ModelBundle?

    static let currentEmbeddingVersion = 2
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
        let bundle = try await XLMRoberta.loadModelBundle(from: Self.modelName)
        modelBundle = bundle
        return bundle
    }

    // MARK: - Embedding Generation

    func generateEmbedding(for text: String) async throws -> [Float]? {
        let model = try await getOrLoadModel()
        let encoded = try model.encode(text)
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
        guard let vector = try await generateEmbedding(for: text) else { return }

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
        guard let queryVector = try await generateEmbedding(for: query) else {
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
