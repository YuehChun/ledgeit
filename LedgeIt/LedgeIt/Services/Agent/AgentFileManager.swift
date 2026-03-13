import Foundation
import os.log

private let agentLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentFileManager")

final class AgentFileManager: Sendable {

    // MARK: - File Identifiers

    enum AgentFile: String, Sendable {
        case persona
        case userProfile
        case longTerm
        case activeContext
        case daily
    }

    enum WriteMode: String, Sendable {
        case append
        case replace
    }

    // MARK: - Paths

    let baseDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDir = appSupport.appendingPathComponent("LedgeIt/agent", isDirectory: true)
    }

    init(baseDir: URL) {
        self.baseDir = baseDir
    }

    // MARK: - Directory Setup

    func ensureSetup() {
        let fm = FileManager.default
        let memoryDir = baseDir.appendingPathComponent("memory", isDirectory: true)

        if !fm.fileExists(atPath: baseDir.path) {
            do {
                try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
                try fm.createDirectory(at: memoryDir, withIntermediateDirectories: true)
                agentLogger.info("Created agent directory at \(self.baseDir.path)")
            } catch {
                agentLogger.error("Failed to create agent directory: \(error.localizedDescription)")
            }
        }

        if !fm.fileExists(atPath: memoryDir.path) {
            do {
                try fm.createDirectory(at: memoryDir, withIntermediateDirectories: true)
            } catch {
                agentLogger.error("Failed to create memory directory: \(error.localizedDescription)")
            }
        }

        let personaPath = filePath(for: .persona)
        if !fm.fileExists(atPath: personaPath.path) {
            do {
                try Self.defaultPersona.write(to: personaPath, atomically: true, encoding: .utf8)
                agentLogger.info("Created default PERSONA.md")
            } catch {
                agentLogger.error("Failed to write default PERSONA.md: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Read

    func read(file: AgentFile, date: String? = nil) -> String? {
        let path = filePath(for: file, date: date)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try? String(contentsOf: path, encoding: .utf8)
    }

    // MARK: - Write

    func write(file: AgentFile, content: String, mode: WriteMode, date: String? = nil) throws -> (path: String, count: Int) {
        ensureSetup()
        let path = filePath(for: file, date: date)

        switch mode {
        case .replace:
            try content.write(to: path, atomically: true, encoding: .utf8)
        case .append:
            if FileManager.default.fileExists(atPath: path.path) {
                let handle = try FileHandle(forWritingTo: path)
                handle.seekToEndOfFile()
                if let data = ("\n" + content).data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try content.write(to: path, atomically: true, encoding: .utf8)
            }
        }

        let finalContent = try String(contentsOf: path, encoding: .utf8)
        return (path.lastPathComponent, finalContent.count)
    }

    // MARK: - Search

    struct SearchResult: Sendable {
        let fileName: String
        let lineNumber: Int
        let content: String
    }

    func search(query: String, scope: String = "all") -> [SearchResult] {
        let keywords = query.lowercased().split(separator: " ").map(String.init)
        guard !keywords.isEmpty else { return [] }

        var results: [SearchResult] = []
        let files = searchableFiles(scope: scope)

        for fileURL in files {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            let fileName = fileURL.lastPathComponent

            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                if keywords.allSatisfy({ lower.contains($0) }) {
                    let snippet = String(line.prefix(500))
                    results.append(SearchResult(fileName: fileName, lineNumber: index + 1, content: snippet))
                    if results.count >= 10 { return results }
                }
            }
        }

        return results
    }

    // MARK: - Path Resolution

    func filePath(for file: AgentFile, date: String? = nil) -> URL {
        switch file {
        case .persona:
            return baseDir.appendingPathComponent("PERSONA.md")
        case .userProfile:
            return baseDir.appendingPathComponent("USER.md")
        case .longTerm:
            return baseDir.appendingPathComponent("memory/MEMORY.md")
        case .activeContext:
            return baseDir.appendingPathComponent("memory/active-context.md")
        case .daily:
            let dateStr = date ?? todayString()
            return baseDir.appendingPathComponent("memory/\(dateStr).md")
        }
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private func yesterdayString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    }

    func recentDailyFiles() -> [(date: String, content: String)] {
        var results: [(String, String)] = []
        let today = todayString()
        let yesterday = yesterdayString()

        for dateStr in [today, yesterday] {
            if let content = read(file: .daily, date: dateStr) {
                results.append((dateStr, content))
            }
        }
        return results
    }

    private func searchableFiles(scope: String) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []

        switch scope {
        case "daily":
            let memoryDir = baseDir.appendingPathComponent("memory", isDirectory: true)
            if let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) {
                files = contents.filter { url in
                    let name = url.lastPathComponent
                    return name.hasSuffix(".md") && name.count == 13
                }
            }
        case "long_term":
            files = [filePath(for: .longTerm)]
        default:
            files = [filePath(for: .persona), filePath(for: .userProfile), filePath(for: .longTerm), filePath(for: .activeContext)]
            let memoryDir = baseDir.appendingPathComponent("memory", isDirectory: true)
            if let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) {
                files += contents.filter { $0.pathExtension == "md" && !files.contains($0) }
            }
        }

        return files.filter { fm.fileExists(atPath: $0.path) }
    }

    // MARK: - File Listing

    struct MemoryFileInfo: Sendable {
        let url: URL
        let fileName: String
        let fileSize: Int64
        let modifiedDate: Date
    }

    func listAllFiles() -> [MemoryFileInfo] {
        ensureSetup()
        let fm = FileManager.default
        var results: [MemoryFileInfo] = []

        func addFiles(in directory: URL) {
            guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
            for url in contents {
                // Skip hidden files and embedding cache
                if url.lastPathComponent.hasPrefix(".") { continue }

                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        addFiles(in: url)
                    } else {
                        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                        results.append(MemoryFileInfo(
                            url: url,
                            fileName: url.lastPathComponent,
                            fileSize: Int64(values?.fileSize ?? 0),
                            modifiedDate: values?.contentModificationDate ?? Date.distantPast
                        ))
                    }
                }
            }
        }

        addFiles(in: baseDir)
        return results.sorted { $0.fileName < $1.fileName }
    }

    // MARK: - Default Content

    static let defaultPersona = """
    # LedgeIt Financial Advisor

    ## Identity
    - Name: LedgeIt Advisor
    - Role: Professional financial advisor integrated into the LedgeIt personal finance app
    - Tone: Professional but approachable, data-driven, encouraging

    ## Boundary Rules
    - NEVER provide specific legal, tax, or investment advice — suggest consulting a professional
    - NEVER expose raw database IDs or internal system details to the user
    - Always confirm before suggesting significant financial changes
    - Protect user privacy — do not reference sensitive data outside of direct queries

    ## Response Style
    - Use bullet points for lists and comparisons
    - Format all currency with 2 decimal places
    - Respond in the same language the user uses
    - Be concise — lead with the insight, then supporting data
    - When noticing concerning patterns, mention them proactively but tactfully

    ## Memory Tool Usage
    When you learn something important about the user, save it using your memory tools:
    - **User expresses a preference or corrects you** → `memory_save` to `user_profile` (replace with updated profile)
    - **You discover an important financial pattern or long-term fact** → `memory_save` to `long_term` (append)
    - **You're working on a multi-step task or tracking something** → `memory_save` to `active_context` (replace with current state)
    - **Noteworthy interaction or decision made today** → `memory_save` to `daily` (append)
    - **Need to recall past conversations** → `memory_search` first, then `memory_get` for full content

    ## What to Remember
    - User's financial goals and priorities
    - Spending habits and patterns the user has confirmed
    - Preferred budget categories or thresholds
    - Communication preferences (language, detail level)
    - Important dates (bill due dates, salary day, etc.)
    - Corrections the user has made to your understanding
    """
}
