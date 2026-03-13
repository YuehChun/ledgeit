import Foundation
import os.log

private let consolidateLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentMemoryConsolidator")

actor AgentMemoryConsolidator {

    static let shared = AgentMemoryConsolidator()

    // MARK: - Auto-Archive Daily Logs

    func consolidateIfNeeded(fileManager: AgentFileManager) async throws -> Bool {
        // Check auto-archive setting
        guard UserDefaults.standard.bool(forKey: "heartbeatAutoArchive") == true ||
              !UserDefaults.standard.contains(key: "heartbeatAutoArchive") else {
            return false
        }

        let memoryDir = fileManager.baseDir.appendingPathComponent("memory", isDirectory: true)
        let fm = FileManager.default

        guard let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) else {
            return false
        }

        // Find daily log files (YYYY-MM-DD.md, exactly 13 chars)
        let dailyFiles = contents.filter { url in
            let name = url.lastPathComponent
            return name.hasSuffix(".md") && name.count == 13
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard dailyFiles.count > 30 else {
            consolidateLogger.info("Only \(dailyFiles.count) daily logs, no archival needed")
            return false
        }

        // Identify files older than 30 days
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let cutoffString = dateFmt.string(from: cutoffDate)

        let oldFiles = dailyFiles.filter { url in
            let dateStr = String(url.lastPathComponent.dropLast(3)) // Remove .md
            return dateStr < cutoffString
        }

        guard !oldFiles.isEmpty else { return false }

        // Read all old files
        var combinedContent = ""
        var dateRange = (first: "", last: "")
        for (idx, file) in oldFiles.enumerated() {
            let dateStr = String(file.lastPathComponent.dropLast(3))
            if idx == 0 { dateRange.first = dateStr }
            if idx == oldFiles.count - 1 { dateRange.last = dateStr }

            if let content = try? String(contentsOf: file, encoding: .utf8) {
                combinedContent += "### \(dateStr)\n\(content)\n\n"
            }
        }

        guard !combinedContent.isEmpty else { return false }

        // LLM summarization
        consolidateLogger.info("Archiving \(oldFiles.count) daily logs from \(dateRange.first) to \(dateRange.last)")

        let config = AIProviderConfigStore.load()
        let session = try SessionFactory.makeSession(
            assignment: config.advisor,
            config: config,
            instructions: "You are a memory consolidation assistant. Summarize daily interaction logs into concise long-term facts."
        )

        let prompt = """
        Summarize these daily logs into concise long-term facts. Preserve important financial patterns, \
        user preferences, and decisions. Remove transient information like greetings and routine queries. \
        Output as a bullet-point list. Respond in the same language as the logs.

        \(combinedContent)
        """

        let summary = try await session.complete(messages: [.user(prompt)], temperature: 0.3, maxTokens: nil)

        // Append to MEMORY.md
        let archiveHeader = "\n\n## Archived from \(dateRange.first) to \(dateRange.last)\n\n"
        let _ = try fileManager.write(
            file: .longTerm,
            content: archiveHeader + summary,
            mode: .append
        )

        // Delete original files
        for file in oldFiles {
            try? fm.removeItem(at: file)
        }

        consolidateLogger.info("Archived \(oldFiles.count) daily logs successfully")
        return true
    }

    // MARK: - Manual Reorganize MEMORY.md

    func reorganizeMemory(fileManager: AgentFileManager) async throws -> (before: String, after: String) {
        guard let currentContent = fileManager.read(file: .longTerm) else {
            throw ConsolidationError.noMemoryFile
        }

        // Backup
        let backupPath = fileManager.baseDir.appendingPathComponent("memory/MEMORY.backup.md")
        try currentContent.write(to: backupPath, atomically: true, encoding: .utf8)

        // LLM reorganization
        let config = AIProviderConfigStore.load()
        let session = try SessionFactory.makeSession(
            assignment: config.advisor,
            config: config,
            instructions: "You are a memory organization assistant."
        )

        let prompt = """
        Reorganize this memory file. Remove duplicates, merge related items, remove clearly outdated information, \
        and organize by topic. Preserve all important facts. Output the reorganized content only, no explanation. \
        Keep the same language as the original.

        \(currentContent)
        """

        let reorganized = try await session.complete(messages: [.user(prompt)], temperature: 0.3, maxTokens: nil)

        return (before: currentContent, after: reorganized)
    }

    nonisolated func applyReorganization(fileManager: AgentFileManager, content: String) throws {
        let _ = try fileManager.write(file: .longTerm, content: content, mode: .replace)
    }

    // MARK: - Errors

    enum ConsolidationError: LocalizedError {
        case noMemoryFile

        var errorDescription: String? {
            switch self {
            case .noMemoryFile: return "MEMORY.md does not exist"
            }
        }
    }
}

// MARK: - UserDefaults helper

private extension UserDefaults {
    func contains(key: String) -> Bool {
        object(forKey: key) != nil
    }
}
