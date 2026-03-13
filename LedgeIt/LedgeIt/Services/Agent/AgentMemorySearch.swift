import Foundation
import CryptoKit
import os.log

private let searchLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentMemorySearch")

struct AgentMemorySearch: Sendable {

    let embeddingService: EmbeddingService
    let agentFileManager: AgentFileManager

    // MARK: - Public API

    func search(query: String, scope: String = "all", topK: Int = 10) async -> [MemorySearchResult] {
        do {
            return try await semanticSearch(query: query, scope: scope, topK: topK)
        } catch {
            searchLogger.warning("Semantic search failed, falling back to keyword: \(error.localizedDescription)")
            return keywordFallback(query: query, scope: scope)
        }
    }

    // MARK: - Semantic Search

    private func semanticSearch(query: String, scope: String, topK: Int) async throws -> [MemorySearchResult] {
        // 1. Load and chunk memory files
        let chunks = loadChunks(scope: scope)
        guard !chunks.isEmpty else { return [] }

        // 2. Embed query
        guard let queryEmbedding = try await embeddingService.generateEmbedding(for: query, isQuery: true) else {
            throw SearchError.embeddingFailed
        }

        // 3. Embed chunks (with cache)
        var cache = EmbeddingCache.load(baseDir: agentFileManager.baseDir)
        var scoredChunks: [(chunk: MemoryChunk, score: Double)] = []

        for chunk in chunks {
            let embedding: [Float]
            let contentHash = chunk.content.sha256Hash

            if let cached = cache.get(hash: contentHash) {
                embedding = cached
            } else {
                guard let generated = try await embeddingService.generateEmbedding(for: chunk.content, isQuery: false) else {
                    continue
                }
                embedding = generated
                cache.set(hash: contentHash, embedding: embedding)
            }

            let similarity = Double(cosineSimilarity(queryEmbedding, embedding))
            let decayed = applyTemporalDecay(score: similarity, fileName: chunk.fileName)
            scoredChunks.append((chunk, decayed))
        }

        cache.save(baseDir: agentFileManager.baseDir)

        // 4. MMR re-ranking
        let reranked = mmrRerank(scoredChunks: scoredChunks, topK: topK)

        return reranked.map { item in
            MemorySearchResult(
                fileName: item.chunk.fileName,
                lineNumber: item.chunk.lineNumber,
                content: String(item.chunk.content.prefix(500)),
                score: item.score
            )
        }
    }

    // MARK: - Chunking

    private func loadChunks(scope: String) -> [MemoryChunk] {
        let files = collectFiles(scope: scope)
        var chunks: [MemoryChunk] = []

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let fileName = fileURL.lastPathComponent

            // Split by double newline (paragraph), fallback to lines
            let paragraphs = content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            if paragraphs.count > 1 {
                for (idx, para) in paragraphs.enumerated() {
                    chunks.append(MemoryChunk(fileName: fileName, lineNumber: idx + 1, content: para.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            } else {
                let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                for (idx, line) in lines.enumerated() {
                    chunks.append(MemoryChunk(fileName: fileName, lineNumber: idx + 1, content: line))
                }
            }
        }

        return chunks
    }

    private func collectFiles(scope: String) -> [URL] {
        let fm = FileManager.default
        let baseDir = agentFileManager.baseDir
        let memoryDir = baseDir.appendingPathComponent("memory", isDirectory: true)

        switch scope {
        case "daily":
            guard let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) else { return [] }
            return contents.filter { $0.lastPathComponent.hasSuffix(".md") && $0.lastPathComponent.count == 13 }
        case "long_term":
            return [baseDir.appendingPathComponent("memory/MEMORY.md")]
        default:
            var files = [
                baseDir.appendingPathComponent("PERSONA.md"),
                baseDir.appendingPathComponent("USER.md"),
                baseDir.appendingPathComponent("memory/MEMORY.md"),
                baseDir.appendingPathComponent("memory/active-context.md")
            ]
            if let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) {
                files += contents.filter { $0.pathExtension == "md" && !files.contains($0) }
            }
            return files.filter { fm.fileExists(atPath: $0.path) }
        }
    }

    // MARK: - Temporal Decay

    private func applyTemporalDecay(score: Double, fileName: String) -> Double {
        // Evergreen files: no decay
        let evergreen = ["PERSONA.md", "USER.md", "MEMORY.md"]
        if evergreen.contains(fileName) { return score }

        // active-context.md: always fresh
        if fileName == "active-context.md" { return score }

        // Daily logs: decay based on date in filename
        let decayRate = log(2.0) / 30.0 // half-life 30 days
        let age = ageInDays(fileName: fileName)
        return score * exp(-decayRate * Double(age))
    }

    private func ageInDays(fileName: String) -> Int {
        // Daily logs have format YYYY-MM-DD.md
        let name = fileName.replacingOccurrences(of: ".md", with: "")
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let fileDate = fmt.date(from: name) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: fileDate, to: Date()).day ?? 0)
    }

    // MARK: - MMR Re-ranking

    private func mmrRerank(scoredChunks: [(chunk: MemoryChunk, score: Double)], topK: Int) -> [(chunk: MemoryChunk, score: Double)] {
        guard !scoredChunks.isEmpty else { return [] }

        let mmrLambda = 0.7
        var candidates = scoredChunks.sorted { $0.score > $1.score }
        var selected: [(chunk: MemoryChunk, score: Double)] = []

        while selected.count < topK && !candidates.isEmpty {
            var bestIdx = 0
            var bestMMR = -Double.infinity

            for (idx, candidate) in candidates.enumerated() {
                let maxSim = selected.map { jaccardSimilarity(candidate.chunk.content, $0.chunk.content) }.max() ?? 0
                let mmr = mmrLambda * candidate.score - (1 - mmrLambda) * maxSim
                if mmr > bestMMR {
                    bestMMR = mmr
                    bestIdx = idx
                }
            }

            selected.append(candidates[bestIdx])
            candidates.remove(at: bestIdx)
        }

        return selected
    }

    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(separator: " ").map(String.init))
        let setB = Set(b.lowercased().split(separator: " ").map(String.init))
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    // MARK: - Keyword Fallback

    private func keywordFallback(query: String, scope: String) -> [MemorySearchResult] {
        agentFileManager.search(query: query, scope: scope).map {
            MemorySearchResult(fileName: $0.fileName, lineNumber: $0.lineNumber, content: $0.content, score: 1.0)
        }
    }

    // MARK: - Helpers

    enum SearchError: Error {
        case embeddingFailed
    }
}

// MARK: - Types

struct MemorySearchResult: Sendable {
    let fileName: String
    let lineNumber: Int
    let content: String
    let score: Double
}

struct MemoryChunk: Sendable {
    let fileName: String
    let lineNumber: Int
    let content: String
}

// MARK: - Cosine Similarity

func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0
    var normA: Float = 0
    var normB: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denom = sqrt(normA) * sqrt(normB)
    return denom > 0 ? dot / denom : 0
}

// MARK: - SHA256 Extension

extension String {
    var sha256Hash: String {
        let data = Data(self.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Embedding Cache

struct EmbeddingCache: Codable {
    var entries: [String: [Float]] = [:]

    static func load(baseDir: URL) -> EmbeddingCache {
        let path = baseDir.appendingPathComponent("memory/.embedding-cache.json")
        guard let data = try? Data(contentsOf: path) else { return EmbeddingCache() }
        return (try? JSONDecoder().decode(EmbeddingCache.self, from: data)) ?? EmbeddingCache()
    }

    func save(baseDir: URL) {
        let path = baseDir.appendingPathComponent("memory/.embedding-cache.json")
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: path, options: .atomic)
    }

    func get(hash: String) -> [Float]? {
        entries[hash]
    }

    mutating func set(hash: String, embedding: [Float]) {
        entries[hash] = embedding
    }
}
