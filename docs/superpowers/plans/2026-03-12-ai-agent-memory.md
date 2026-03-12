# AI Agent Memory & Identity System Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the LedgeIt AI financial advisor persistent memory and personality by storing identity and memory as Markdown files, injecting them into system prompts, and letting the AI read/write memory via tool calling.

**Architecture:** Two new files (`AgentFileManager.swift`, `AgentPromptBuilder.swift`) in `Services/Agent/`, plus modifications to `ChatEngine.swift` to wire in the prompt builder and 3 new memory tools. Memory stored as `.md` files in `~/Library/Application Support/LedgeIt/agent/`.

**Tech Stack:** Swift 6.2, Foundation (FileManager), existing LLMToolDefinition/ChatEngine patterns.

**Spec:** `docs/superpowers/specs/2026-03-12-ai-agent-memory-design.md`

---

## Chunk 1: AgentFileManager + AgentPromptBuilder

### Task 1: AgentFileManager — File I/O and Directory Management

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Agent/AgentFileManager.swift`

- [ ] **Step 1: Create AgentFileManager with directory setup and default PERSONA.md**

Create `LedgeIt/LedgeIt/Services/Agent/AgentFileManager.swift`:

```swift
import Foundation
import os.log

private let agentLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentFileManager")

final class AgentFileManager: Sendable {

    // MARK: - File Identifiers

    enum AgentFile: String, Sendable {
        case persona       // PERSONA.md
        case userProfile   // USER.md
        case longTerm      // memory/MEMORY.md
        case activeContext  // memory/active-context.md
        case daily         // memory/YYYY-MM-DD.md (resolved dynamically)
    }

    enum WriteMode: String, Sendable {
        case append
        case replace
    }

    // MARK: - Paths

    private let baseDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.baseDir = appSupport.appendingPathComponent("LedgeIt/agent", isDirectory: true)
    }

    /// For testing with custom directory
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

        // Write default PERSONA.md if missing
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

    /// Files for today and yesterday daily logs (used by prompt builder)
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
                // Daily files match YYYY-MM-DD.md pattern, exclude MEMORY.md and active-context.md
                files = contents.filter { url in
                    let name = url.lastPathComponent
                    return name.hasSuffix(".md") && name.count == 13 // "2026-03-12.md"
                }
            }
        case "long_term":
            files = [filePath(for: .longTerm)]
        default: // "all"
            files = [filePath(for: .persona), filePath(for: .userProfile), filePath(for: .longTerm), filePath(for: .activeContext)]
            let memoryDir = baseDir.appendingPathComponent("memory", isDirectory: true)
            if let contents = try? fm.contentsOfDirectory(at: memoryDir, includingPropertiesForKeys: nil) {
                files += contents.filter { $0.pathExtension == "md" && !files.contains($0) }
            }
        }

        return files.filter { fm.fileExists(atPath: $0.path) }
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
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Agent/AgentFileManager.swift
git commit -m "feat(agent): add AgentFileManager for memory file I/O"
```

---

### Task 2: AgentPromptBuilder — System Prompt Assembly

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Agent/AgentPromptBuilder.swift`

- [ ] **Step 1: Create AgentPromptBuilder**

Create `LedgeIt/LedgeIt/Services/Agent/AgentPromptBuilder.swift`:

```swift
import Foundation
import os.log

private let promptLogger = Logger(subsystem: "com.ledgeit.app", category: "AgentPromptBuilder")

enum AgentPromptBuilder {

    private static let perFileCap = 15_000
    private static let totalCap = 50_000

    /// Build the full system prompt from identity files, memory, and financial snapshot.
    static func build(
        fileManager: AgentFileManager,
        financialSnapshot: String
    ) -> String {
        fileManager.ensureSetup()

        // Collect sections in priority order (highest first)
        var sections: [(label: String, content: String, priority: Int)] = []

        // Priority 1: PERSONA.md (never omitted)
        if let persona = fileManager.read(file: .persona) {
            sections.append(("PERSONA", truncate(persona), 1))
        }

        // Priority 2: USER.md
        if let user = fileManager.read(file: .userProfile) {
            sections.append(("USER PROFILE", truncate(user), 2))
        }

        // Priority 3: active-context.md
        if let ctx = fileManager.read(file: .activeContext) {
            sections.append(("ACTIVE CONTEXT", truncate(ctx), 3))
        }

        // Priority 4: Recent daily logs (today + yesterday)
        let dailyLogs = fileManager.recentDailyFiles()
        for (date, content) in dailyLogs {
            sections.append(("DAILY LOG (\(date))", truncate(content), 4))
        }

        // Priority 5: MEMORY.md (first 200 lines)
        if let memory = fileManager.read(file: .longTerm) {
            let lines = memory.components(separatedBy: .newlines)
            let trimmed = lines.prefix(200).joined(separator: "\n")
            sections.append(("LONG-TERM MEMORY", truncate(trimmed), 5))
        }

        // Priority 6: Financial snapshot (existing ChatEngine data)
        sections.append(("FINANCIAL SNAPSHOT", financialSnapshot, 6))

        // Assemble within total cap, removing lowest priority first
        var result = ""
        var remaining = totalCap

        // Sort by priority (highest = 1 first)
        let sorted = sections.sorted { $0.priority < $1.priority }

        // First pass: calculate total
        let totalNeeded = sorted.reduce(0) { $0 + $1.content.count + $1.label.count + 20 }

        if totalNeeded <= totalCap {
            // Everything fits
            for section in sorted {
                result += "## \(section.label)\n\n\(section.content)\n\n"
            }
        } else {
            // Remove from lowest priority until it fits
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
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Agent/AgentPromptBuilder.swift
git commit -m "feat(agent): add AgentPromptBuilder for system prompt assembly"
```

---

## Chunk 2: ChatEngine Integration

### Task 3: Wire AgentPromptBuilder into ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

- [ ] **Step 1: Add AgentFileManager property and update init**

In `ChatEngine.swift`, add the `agentFileManager` property alongside existing ones:

```swift
// Add after line 8 (private let embeddingService):
private let agentFileManager = AgentFileManager()
```

- [ ] **Step 2: Replace buildSystemPrompt() to use AgentPromptBuilder**

Replace the entire `buildSystemPrompt()` method (lines 151-196) with:

```swift
private func buildSystemPrompt() async throws -> String {
    let overview = try await queryService.getAccountOverview()

    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    let today = fmt.string(from: Date())

    let categoryList = overview.topCategories
        .map { "\($0.category): \(String(format: "%.2f", $0.totalAmount)) (\(String(format: "%.1f", $0.percentage))%)" }
        .joined(separator: ", ")

    let financialSnapshot = """
        Today is \(today).

        Current financial snapshot:
        - This month's income: \(String(format: "%.2f", overview.totalIncome))
        - This month's expenses: \(String(format: "%.2f", overview.totalExpenses))
        - Transaction count: \(overview.transactionCount)
        - Upcoming payments: \(overview.upcomingPayments)
        - Active goals: \(overview.activeGoals)
        - Top spending categories: \(categoryList.isEmpty ? "None" : categoryList)

        ## Interaction Guidelines
        1. **Understand intent first**: When the user asks a question, briefly confirm your understanding of what they want before diving into data.
        2. **Rephrase when ambiguous**: If the user's request is vague, rephrase their intent and ask for confirmation.
        3. **Summarize findings**: After retrieving data, provide a clear summary with key insights, not just raw numbers.
        4. **Proactive suggestions**: When you notice patterns (overspending, upcoming bills, goal progress), mention them.
        5. **Remember important things**: When you learn something new about the user (preferences, goals, habits), save it to memory using memory_save.

        ## Formatting
        - Use the available tools to query detailed data when needed.
        - Be concise and helpful.
        - Format currency amounts with 2 decimal places.
        - Respond in the same language the user uses.

        ## Tool Selection
        - Use `semantic_search` when the user asks about specific merchants, brands, products, or conceptual spending categories.
        - CRITICAL: Transaction data is stored in BOTH English and Chinese. When searching, ALWAYS provide BOTH the original term AND its translation in the `queries` array.
        - Use `get_transactions` or `search_transactions` when the user specifies exact filters.
        - Use `memory_save` when you learn something important about the user.
        - Use `memory_search` when you need to recall past conversations or user preferences.
        - Use `memory_get` to read full content of a specific memory file.
        """

    return AgentPromptBuilder.build(
        fileManager: agentFileManager,
        financialSnapshot: financialSnapshot
    )
}
```

- [ ] **Step 3: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "feat(agent): wire AgentPromptBuilder into ChatEngine"
```

---

### Task 4: Add Memory Tool Definitions to ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

- [ ] **Step 1: Add 3 memory tool definitions**

In the `toolDefinitions` computed property, append these 3 tools after the `semantic_search` definition (before the closing `]` on line 312):

```swift
LLMToolDefinition(
    name: "memory_save",
    description: "Save information to the agent's memory. Use when you learn something important about the user (preferences, goals, habits) or need to record a decision or observation.",
    parameters: [
        "type": "object",
        "properties": [
            "file": [
                "type": "string",
                "enum": ["user_profile", "long_term", "daily", "active_context"],
                "description": "Target file: user_profile (preferences), long_term (patterns/facts), daily (today's log), active_context (in-progress work)"
            ] as [String: Any],
            "content": ["type": "string", "description": "The text content to save"],
            "mode": [
                "type": "string",
                "enum": ["append", "replace"],
                "description": "Write mode: append (add to file) or replace (overwrite). Default: append"
            ] as [String: Any]
        ] as [String: Any],
        "required": ["file", "content"] as [String]
    ] as [String: Any]
),
LLMToolDefinition(
    name: "memory_search",
    description: "Search through the agent's memory files by keyword. Use when you need to recall past conversations, user preferences, or previous decisions.",
    parameters: [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Search keywords"],
            "scope": [
                "type": "string",
                "enum": ["all", "daily", "long_term"],
                "description": "Search scope: all (default), daily (only daily logs), long_term (only MEMORY.md)"
            ] as [String: Any]
        ] as [String: Any],
        "required": ["query"] as [String]
    ] as [String: Any]
),
LLMToolDefinition(
    name: "memory_get",
    description: "Read the full content of a specific memory file. Use when memory_search found relevant results and you need the complete context.",
    parameters: [
        "type": "object",
        "properties": [
            "file": [
                "type": "string",
                "description": "File to read: user_profile, long_term, active_context, persona, or daily:YYYY-MM-DD (e.g. daily:2026-03-12)"
            ] as [String: Any]
        ] as [String: Any],
        "required": ["file"] as [String]
    ] as [String: Any]
)
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "feat(agent): add memory_save, memory_search, memory_get tool definitions"
```

---

### Task 5: Add Memory Tool Execution to ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

- [ ] **Step 1: Add 3 tool execution cases**

In the `executeTool()` method, add these cases before the `default:` case:

```swift
case "memory_save":
    let fileStr = args["file"] as? String ?? "daily"
    let content = args["content"] as? String ?? ""
    let modeStr = args["mode"] as? String ?? "append"

    guard !content.isEmpty else {
        return "Error: content parameter is required"
    }

    let file: AgentFileManager.AgentFile
    switch fileStr {
    case "user_profile": file = .userProfile
    case "long_term": file = .longTerm
    case "active_context": file = .activeContext
    default: file = .daily
    }

    let mode: AgentFileManager.WriteMode = modeStr == "replace" ? .replace : .append

    // For daily logs, prepend timestamp
    let finalContent: String
    if file == .daily {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        finalContent = "[\(timeFmt.string(from: Date()))] \(content)"
    } else {
        finalContent = content
    }

    let result = try agentFileManager.write(file: file, content: finalContent, mode: mode)
    return "Saved to \(result.path) (\(result.count) characters)"

case "memory_search":
    let query = args["query"] as? String ?? ""
    let scope = args["scope"] as? String ?? "all"
    guard !query.isEmpty else {
        return "Error: query parameter is required"
    }
    let results = agentFileManager.search(query: query, scope: scope)
    if results.isEmpty {
        return "No memory entries found for: \(query)"
    }
    return results.map { "[\($0.fileName):\($0.lineNumber)] \($0.content)" }.joined(separator: "\n\n")

case "memory_get":
    let fileStr = args["file"] as? String ?? ""
    let file: AgentFileManager.AgentFile
    var date: String? = nil

    if fileStr.hasPrefix("daily:") {
        file = .daily
        date = String(fileStr.dropFirst("daily:".count))
    } else {
        switch fileStr {
        case "user_profile": file = .userProfile
        case "long_term": file = .longTerm
        case "active_context": file = .activeContext
        case "persona": file = .persona
        default:
            return "Error: unknown file '\(fileStr)'. Use: user_profile, long_term, active_context, persona, or daily:YYYY-MM-DD"
        }
    }

    guard let content = agentFileManager.read(file: file, date: date) else {
        return "File not found or empty: \(fileStr)"
    }
    if content.count > 10_000 {
        return String(content.prefix(10_000)) + "\n\n[truncated at 10,000 characters]"
    }
    return content
```

- [ ] **Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | grep -E "error:|Build complete"`
Expected: `Build complete!`

- [ ] **Step 3: Build release and install**

Run: `cd LedgeIt && bash build.sh && cp -R .build/LedgeIt.app /Applications/LedgeIt.app`

- [ ] **Step 4: Manual verification**

1. Launch LedgeIt
2. Open Chat
3. Tell the AI: "My name is [your name], please remember that"
4. Verify the AI calls `memory_save` tool (visible in chat as tool call indicator)
5. Check file exists: `ls ~/Library/Application\ Support/LedgeIt/agent/USER.md`
6. Start a new chat session, ask "What's my name?" — the AI should know from the system prompt

- [ ] **Step 5: Commit**

```bash
git add LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "feat(agent): add memory tool execution to ChatEngine"
```

---

## Summary of All Changes

| Action | File | Purpose |
|--------|------|---------|
| Create | `Services/Agent/AgentFileManager.swift` | Memory file I/O, directory management, keyword search |
| Create | `Services/Agent/AgentPromptBuilder.swift` | System prompt assembly from identity + memory files |
| Modify | `Services/ChatEngine.swift` | Wire prompt builder, add 3 memory tools (definitions + execution) |

**Total: 2 new files, 1 modified file.**
