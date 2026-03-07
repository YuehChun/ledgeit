import Foundation
import AnyLanguageModel
import os.log

private let toolLogger = Logger(subsystem: "com.ledgeit.app", category: "SemanticSearchTool")

struct SemanticSearchTool: Tool {
    let queryService: FinancialQueryService
    let embeddingService: EmbeddingService
    let name = "semanticSearch"
    let description = "Search transactions using hybrid search (semantic + keyword). IMPORTANT: Always provide BOTH the original term AND its English/Chinese translation in the queries array for cross-language matching."

    @Generable
    struct Arguments {
        @Guide(description: "Search queries - include both original and translated terms (e.g., multiple related search terms)")
        var queries: [String]
        @Guide(description: "Max results to return (default 10)")
        var limit: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let queries = arguments.queries
        let limit = arguments.limit ?? 10

        guard !queries.isEmpty else {
            return "Error: queries parameter is required"
        }

        toolLogger.debug("semantic_search queries=\(queries) limit=\(limit)")

        var bestScores: [Int64: Float] = [:]
        for q in queries {
            let results = try await embeddingService.hybridSearch(query: q, limit: limit)
            toolLogger.debug("  query '\(q)': \(results.count) results")
            for r in results {
                if let existing = bestScores[r.transactionId] {
                    bestScores[r.transactionId] = min(existing, r.distance)
                } else {
                    bestScores[r.transactionId] = r.distance
                }
            }
        }

        let sorted = bestScores.sorted { $0.value < $1.value }
        let topIds = sorted.prefix(limit).map { $0.key }
        toolLogger.debug("merged \(bestScores.count) unique results, top \(topIds.count)")

        if topIds.isEmpty {
            return "No transactions found for: \(queries.joined(separator: ", "))"
        }
        let transactions = try await queryService.getTransactions(ids: Array(topIds))
        return ToolFormatters.formatTransactions(transactions)
    }
}
