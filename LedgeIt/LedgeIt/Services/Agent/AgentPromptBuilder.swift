import Foundation
import os.log

private let promptLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentPromptBuilder")

enum AgentPromptBuilder {

    private static let perFileCap = 15_000
    private static let totalCap = 50_000

    static func build(
        fileManager: AgentFileManager,
        financialSnapshot: String
    ) -> String {
        fileManager.ensureSetup()

        var sections: [(label: String, content: String, priority: Int)] = []

        if let persona = fileManager.read(file: .persona) {
            sections.append(("PERSONA", truncate(persona), 1))
        }

        if let user = fileManager.read(file: .userProfile) {
            sections.append(("USER PROFILE", truncate(user), 2))
        }

        if let ctx = fileManager.read(file: .activeContext) {
            sections.append(("ACTIVE CONTEXT", truncate(ctx), 3))
        }

        let dailyLogs = fileManager.recentDailyFiles()
        for (date, content) in dailyLogs {
            sections.append(("DAILY LOG (\(date))", truncate(content), 4))
        }

        if let memory = fileManager.read(file: .longTerm) {
            let lines = memory.components(separatedBy: .newlines)
            let trimmed = lines.prefix(200).joined(separator: "\n")
            sections.append(("LONG-TERM MEMORY", truncate(trimmed), 5))
        }

        sections.append(("FINANCIAL SNAPSHOT", financialSnapshot, 6))

        let sorted = sections.sorted { $0.priority < $1.priority }
        let totalNeeded = sorted.reduce(0) { $0 + $1.content.count + $1.label.count + 20 }

        var result = ""

        if totalNeeded <= totalCap {
            for section in sorted {
                result += "## \(section.label)\n\n\(section.content)\n\n"
            }
        } else {
            var included = sorted
            var currentSize = totalNeeded
            while currentSize > totalCap && !included.isEmpty {
                let removed = included.removeLast()
                currentSize -= (removed.content.count + removed.label.count + 20)
                promptLogger.info("Prompt too large, removed section: \(removed.label)")
            }
            for section in included {
                result += "## \(section.label)\n\n\(section.content)\n\n"
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String) -> String {
        if text.count <= perFileCap { return text }
        let truncated = String(text.prefix(perFileCap))
        return truncated + "\n\n[truncated — use memory_search for full content]"
    }
}
