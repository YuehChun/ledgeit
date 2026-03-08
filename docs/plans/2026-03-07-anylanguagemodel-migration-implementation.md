# AnyLanguageModel Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace hand-rolled LLM provider sessions with AnyLanguageModel, adopting its Tool protocol for type-safe tool definitions.

**Architecture:** AnyLanguageModel provides provider adapters (OpenAI, Anthropic, Google) and automatic tool-calling loops. We keep SessionFactory as a thin creation layer, convert 9 ChatEngine tools to `Tool` + `@Generable`, and build a `DynamicTool` wrapper for future plugin support.

**Tech Stack:** Swift 6.2, AnyLanguageModel (v0.7+), macOS 15+

**Design doc:** `docs/plans/2026-03-07-anylanguagemodel-migration-design.md`

---

## Phase 0: PoC Validation

### Task 1: Add AnyLanguageModel dependency to Package.swift

**Files:**
- Modify: `LedgeIt/Package.swift`

**Step 1: Add the package dependency**

In `LedgeIt/Package.swift`, add to `dependencies` array:

```swift
.package(url: "https://github.com/mattt/AnyLanguageModel", from: "0.7.0"),
```

And add to the `LedgeIt` executableTarget's `dependencies`:

```swift
.product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
```

Also add to the `LedgeItTests` testTarget's `dependencies`:

```swift
.product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
```

**Step 2: Resolve dependencies**

Run: `cd LedgeIt && swift package resolve`
Expected: Package resolves successfully, AnyLanguageModel downloaded

**Step 3: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds (existing code unaffected)

**Step 4: Commit**

```bash
git add LedgeIt/Package.swift LedgeIt/Package.resolved
git commit -m "chore: add AnyLanguageModel dependency"
```

---

### Task 2: PoC — P0-1 custom baseURL + P0-2 static tool calling

**Files:**
- Create: `LedgeIt/Tests/AnyLMPoCTests.swift`

**Step 1: Create the PoC test file**

```swift
import Testing
import AnyLanguageModel

// MARK: - P0-1: Custom baseURL with OpenAI-compatible endpoint

@Test func pocCustomBaseURL() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_KEY"] else {
        Issue.record("Set OPENROUTER_KEY env var to run this test")
        return
    }

    let model = OpenAILanguageModel(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: apiKey,
        model: "anthropic/claude-3.5-haiku",
        apiVariant: .chatCompletions
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "You are a test bot. Reply with ONLY the word 'PONG' and nothing else."
    )
    let result = try await session.respond(to: "PING", generating: String.self)
    #expect(result.lowercased().contains("pong"), "Expected 'PONG' but got: \(result)")
}

// MARK: - P0-2: Static tool calling

struct GreetTool: Tool {
    var description: String { "Greets a person by name" }

    @Generable
    struct Arguments {
        @Guide(description: "The name of the person to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Hello, \(arguments.name)! Welcome to LedgeIt."
    }
}

@Test func pocStaticToolCalling() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_KEY"] else {
        Issue.record("Set OPENROUTER_KEY env var to run this test")
        return
    }

    let model = OpenAILanguageModel(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: apiKey,
        model: "anthropic/claude-3.5-haiku",
        apiVariant: .chatCompletions
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "Use the greet tool when asked to greet someone.",
        tools: [GreetTool()]
    )
    let result = try await session.respond(to: "Please greet Eugene", generating: String.self)
    #expect(result.contains("Eugene"), "Expected response to contain 'Eugene' but got: \(result)")
}
```

**Step 2: Run the tests**

Run: `cd LedgeIt && OPENROUTER_KEY="<key>" swift test --filter pocCustomBaseURL 2>&1 | tail -10`
Expected: PASS — model responds with "PONG"

Run: `cd LedgeIt && OPENROUTER_KEY="<key>" swift test --filter pocStaticToolCalling 2>&1 | tail -10`
Expected: PASS — tool is called, response contains "Eugene"

**Step 3: Commit**

```bash
git add LedgeIt/Tests/AnyLMPoCTests.swift
git commit -m "test: add AnyLanguageModel PoC for custom baseURL and static tool calling"
```

---

### Task 3: PoC — P0-3 multi-round tool calling + P0-4 DynamicTool

**Files:**
- Modify: `LedgeIt/Tests/AnyLMPoCTests.swift`

**Step 1: Add multi-round tool test**

Append to `AnyLMPoCTests.swift`:

```swift
// MARK: - P0-3: Multi-round tool calling

struct LookupTool: Tool {
    var description: String { "Looks up a value by key from a database" }

    @Generable
    struct Arguments {
        @Guide(description: "The key to look up")
        var key: String
    }

    func call(arguments: Arguments) async throws -> String {
        // Simulated DB lookup
        let db = ["balance": "15000.50", "currency": "TWD", "account": "savings"]
        return db[arguments.key] ?? "not_found"
    }
}

struct FormatTool: Tool {
    var description: String { "Formats a currency amount with symbol" }

    @Generable
    struct Arguments {
        @Guide(description: "The numeric amount as string")
        var amount: String

        @Guide(description: "The currency code like TWD, USD")
        var currency: String
    }

    func call(arguments: Arguments) async throws -> String {
        "\(arguments.currency) \(arguments.amount)"
    }
}

@Test func pocMultiRoundToolCalling() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_KEY"] else {
        Issue.record("Set OPENROUTER_KEY env var to run this test")
        return
    }

    let model = OpenAILanguageModel(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: apiKey,
        model: "anthropic/claude-3.5-haiku",
        apiVariant: .chatCompletions
    )
    let session = LanguageModelSession(
        model: model,
        instructions: """
            You have access to a lookup tool and a format tool.
            To answer questions about account balances:
            1. First use lookup to get the balance amount
            2. Then use lookup to get the currency
            3. Then use format to format the result
            Always use the tools, never guess values.
            """,
        tools: [LookupTool(), FormatTool()]
    )
    let result = try await session.respond(
        to: "What is my account balance? Format it nicely.",
        generating: String.self
    )
    #expect(result.contains("15000") || result.contains("15,000"),
            "Expected formatted balance but got: \(result)")
}
```

**Step 2: Add DynamicTool test**

Append to `AnyLMPoCTests.swift`:

```swift
// MARK: - P0-4: DynamicTool wrapper

struct DynamicArguments: ConvertibleFromGeneratedContent {
    private let content: GeneratedContent

    init(from content: GeneratedContent) {
        self.content = content
    }

    func string(for key: String) -> String? {
        try? content.value(String.self, forProperty: key)
    }

    func double(for key: String) -> Double? {
        try? content.value(Double.self, forProperty: key)
    }

    func int(for key: String) -> Int? {
        try? content.value(Int.self, forProperty: key)
    }

    func bool(for key: String) -> Bool? {
        try? content.value(Bool.self, forProperty: key)
    }
}

struct DynamicTool: Tool {
    typealias Arguments = DynamicArguments
    typealias Output = String

    let name: String
    let description: String
    private let schema: GenerationSchema
    let handler: @Sendable (DynamicArguments) async throws -> String

    var parameters: GenerationSchema { schema }

    func call(arguments: DynamicArguments) async throws -> String {
        try await handler(arguments)
    }
}

@Test func pocDynamicTool() async throws {
    guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_KEY"] else {
        Issue.record("Set OPENROUTER_KEY env var to run this test")
        return
    }

    let schema = DynamicGenerationSchema(properties: [
        .init(name: "message", schema: .string, description: "The message to echo", isRequired: true)
    ])

    let tool = DynamicTool(
        name: "echo",
        description: "Echoes the input message back",
        schema: GenerationSchema(schema),  // NOTE: verify this conversion API
        handler: { args in
            "ECHO: \(args.string(for: "message") ?? "empty")"
        }
    )

    let model = OpenAILanguageModel(
        baseURL: URL(string: "https://openrouter.ai/api/v1")!,
        apiKey: apiKey,
        model: "anthropic/claude-3.5-haiku",
        apiVariant: .chatCompletions
    )
    let session = LanguageModelSession(
        model: model,
        instructions: "Use the echo tool when asked to echo something.",
        tools: [tool]
    )
    let result = try await session.respond(to: "Echo 'hello world'", generating: String.self)
    #expect(result.contains("hello world"), "Expected echoed message but got: \(result)")
}
```

> **NOTE:** The `GenerationSchema(schema)` initializer and `DynamicGenerationSchema` property API
> may differ from what's shown. The PoC's purpose is to discover the exact API. If compilation fails,
> adjust based on AnyLanguageModel's actual types. Check the source at:
> `Sources/AnyLanguageModel/DynamicGenerationSchema.swift` and `GenerationSchema.swift`

**Step 3: Run all PoC tests**

Run: `cd LedgeIt && OPENROUTER_KEY="<key>" swift test --filter poc 2>&1 | tail -20`

**Step 4: Evaluate results per decision tree**

- P0-1 fail → STOP, execute Option B instead
- P0-2 fail → STOP, execute Option B instead
- P0-3 fail → STOP, execute Option B instead
- P0-4 fail → Continue without DynamicTool (plugin system stays custom)
- All pass → Continue to Phase 1

**Step 5: Commit**

```bash
git add LedgeIt/Tests/AnyLMPoCTests.swift
git commit -m "test: add PoC for multi-round tool calling and DynamicTool wrapper"
```

---

## Phase 1: Build Static Tools

### Task 4: Create GetTransactionsTool

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Tools/GetTransactionsTool.swift`

**Step 1: Create the tool**

```swift
import Foundation
import AnyLanguageModel

struct GetTransactionsTool: Tool {
    let queryService: FinancialQueryService

    var description: String { "Get a list of transactions with optional filters" }

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)")
        var startDate: String?

        @Guide(description: "End date (yyyy-MM-dd)")
        var endDate: String?

        @Guide(description: "Filter by category")
        var category: String?

        @Guide(description: "Filter by merchant name")
        var merchant: String?

        @Guide(description: "Minimum transaction amount")
        var minAmount: Double?

        @Guide(description: "Maximum transaction amount")
        var maxAmount: Double?

        @Guide(description: "Transaction type: debit, credit, or transfer")
        var type: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let filter = TransactionFilter(
            startDate: arguments.startDate,
            endDate: arguments.endDate,
            category: arguments.category,
            merchant: arguments.merchant,
            minAmount: arguments.minAmount,
            maxAmount: arguments.maxAmount,
            type: arguments.type
        )
        let transactions = try await queryService.getTransactions(filter: filter)
        return ToolFormatters.formatTransactions(transactions)
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Tools/GetTransactionsTool.swift
git commit -m "feat: add GetTransactionsTool with Tool protocol"
```

---

### Task 5: Create remaining 8 static tools + ToolFormatters

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Tools/GetSpendingSummaryTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/GetCategoryBreakdownTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/GetTopMerchantsTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/GetUpcomingPaymentsTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/GetGoalsTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/SearchTransactionsTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/GetAccountOverviewTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/SemanticSearchTool.swift`
- Create: `LedgeIt/LedgeIt/Services/Tools/ToolFormatters.swift`

**Step 1: Create ToolFormatters**

Extract formatting helpers from `ChatEngine.swift:470-534` into a shared utility:

```swift
import Foundation

enum ToolFormatters {
    static func formatTransactions(_ transactions: [Transaction]) -> String {
        // Copy from ChatEngine.swift:470-492
    }

    static func formatBills(_ bills: [CreditCardBill]) -> String {
        // Copy from ChatEngine.swift:494-510
    }

    static func formatGoals(_ goals: [FinancialGoal]) -> String {
        // Copy from ChatEngine.swift:512-523
    }

    static func encodeToJSON<T: Encodable>(_ value: T) -> String {
        // Copy from ChatEngine.swift:526-534
    }
}
```

**Step 2: Create each tool struct**

Each tool follows the same pattern as `GetTransactionsTool`. Key details per tool:

| Tool | Arguments | Required | call() logic source |
|------|-----------|----------|---------------------|
| `GetSpendingSummaryTool` | startDate, endDate | both | `ChatEngine.swift:335-343` |
| `GetCategoryBreakdownTool` | startDate, endDate | both | `ChatEngine.swift:345-353` |
| `GetTopMerchantsTool` | startDate, endDate, limit(Int?) | startDate, endDate | `ChatEngine.swift:355-372` |
| `GetUpcomingPaymentsTool` | (none) | — | `ChatEngine.swift:374-376` |
| `GetGoalsTool` | status(String?) | — | `ChatEngine.swift:378-381` |
| `SearchTransactionsTool` | query | query | `ChatEngine.swift:383-388` |
| `GetAccountOverviewTool` | (none) | — | `ChatEngine.swift:390-392` |
| `SemanticSearchTool` | queries([String]), limit(Int?) | queries | `ChatEngine.swift:394-442` |

> **Note for SemanticSearchTool:** This tool needs `EmbeddingService` AND `FinancialQueryService`.
> Pass both via init. The `queries` field is an array — verify `@Generable` supports `[String]`.
> If not, use a comma-separated string and split in `call()`.

**Step 3: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Tools/
git commit -m "feat: add 8 static tools and ToolFormatters"
```

---

### Task 6: Create DynamicTool.swift (if P0-4 passed)

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Tools/DynamicTool.swift`

**Step 1: Create DynamicTool and DynamicArguments**

Use the validated code from the PoC test (Task 3). Move `DynamicTool` and `DynamicArguments` from the test file into the main target.

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Tools/DynamicTool.swift
git commit -m "feat: add DynamicTool wrapper for runtime tool definitions"
```

---

## Phase 2: Migrate ChatEngine

### Task 7: Rewrite SessionFactory

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift`

**Step 1: Rewrite SessionFactory to use AnyLanguageModel**

Replace the entire file content:

```swift
import Foundation
import AnyLanguageModel

enum SessionFactory {

    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingEndpointId(provider: AIProvider)
        case missingAPIKey(provider: String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint configuration not found: \(id)"
            case .missingEndpointId(let provider):
                return "Endpoint ID is required for provider: \(provider.rawValue)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            }
        }
    }

    /// Create a LanguageModelSession for the given model assignment.
    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        instructions: String = "",
        tools: [any Tool] = []
    ) throws -> LanguageModelSession {
        let model = try makeModel(assignment: assignment, config: config)
        return LanguageModelSession(model: model, instructions: instructions, tools: tools)
    }

    /// Create the provider-specific language model.
    private static func makeModel(
        assignment: ModelAssignment,
        config: AIProviderConfiguration
    ) throws -> any LanguageModel {
        switch assignment.provider {
        case .openAICompatible:
            guard let endpointId = assignment.endpointId else {
                throw SessionError.missingEndpointId(provider: assignment.provider)
            }
            guard let endpoint = config.endpoints.first(where: { $0.id == endpointId }) else {
                throw SessionError.endpointNotFound(endpointId)
            }
            let apiKey = endpoint.requiresAPIKey
                ? KeychainService.loadEndpointAPIKey(endpointId: endpoint.id)
                : nil
            if endpoint.requiresAPIKey && apiKey == nil {
                throw SessionError.missingAPIKey(provider: endpoint.name)
            }
            return OpenAILanguageModel(
                baseURL: URL(string: endpoint.baseURL)!,
                apiKey: apiKey ?? "",
                model: assignment.model,
                apiVariant: .chatCompletions
            )

        case .anthropic:
            guard let apiKey = KeychainService.load(key: .anthropicAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Anthropic")
            }
            return AnthropicLanguageModel(apiKey: apiKey, model: assignment.model)

        case .google:
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            return GoogleLanguageModel(apiKey: apiKey, model: assignment.model)
        }
    }
}
```

> **NOTE:** `OpenAILanguageModel`, `AnthropicLanguageModel`, `GoogleLanguageModel` are the
> expected type names from AnyLanguageModel. Verify against the library's actual exports.
> Check: `import AnyLanguageModel` then look for available model types in autocomplete or
> browse `Sources/AnyLanguageModel/Models/`.

**Step 2: This will cause compile errors — expected!**

All call sites still reference the old `LLMSession` protocol. We fix them in subsequent tasks.

**Step 3: Commit (on a WIP basis)**

```bash
git add LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift
git commit -m "refactor: rewrite SessionFactory to use AnyLanguageModel models"
```

---

### Task 8: Migrate ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

This is the most complex migration. Key changes:

1. Replace `LLMSession` usage with `LanguageModelSession`
2. Remove manual tool-calling loop (lines 86-134) — AnyLanguageModel handles this
3. Remove `toolDefinitions` computed property (lines 200-313)
4. Remove `executeTool` method (lines 317-447)
5. Remove `parseArguments` helper (lines 451-466)
6. Remove formatting methods (lines 470-534) — moved to `ToolFormatters`
7. Add tool construction with `activeTools` method

**Step 1: Rewrite ChatEngine**

Key structural changes:

```swift
import Foundation
import AnyLanguageModel
import os.log

private let chatLogger = Logger(subsystem: "com.ledgeit.app", category: "ChatEngine")

actor ChatEngine {
    private let queryService: FinancialQueryService
    private let embeddingService: EmbeddingService
    // NOTE: conversation history management changes —
    // LanguageModelSession maintains its own Transcript.
    // We may still need a separate history for UI restoration.
    private var uiHistory: [(role: String, content: String)] = []

    init(
        queryService: FinancialQueryService = FinancialQueryService(),
        embeddingService: EmbeddingService = EmbeddingService()
    ) {
        self.queryService = queryService
        self.embeddingService = embeddingService
    }

    // MARK: - Public API

    func send(message: String) -> AsyncStream<ChatStreamEvent> {
        let messageId = UUID()
        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.yield(.error("ChatEngine deallocated"))
                    continuation.finish()
                    return
                }
                await self.processMessage(message, messageId: messageId, continuation: continuation)
            }
        }
    }

    func clearHistory() {
        uiHistory.removeAll()
    }

    func restoreMessage(role: LLMMessage.Role, content: String) {
        // Keep for UI history restoration
        switch role {
        case .user:
            uiHistory.append((role: "user", content: content))
        case .assistant:
            uiHistory.append((role: "assistant", content: content))
        default:
            break
        }
    }

    // MARK: - Message Processing

    private func processMessage(
        _ message: String,
        messageId: UUID,
        continuation: AsyncStream<ChatStreamEvent>.Continuation
    ) async {
        do {
            chatLogger.debug("User: \(message)")
            uiHistory.append((role: "user", content: message))

            let systemPrompt = try await buildSystemPrompt()
            let config = AIProviderConfigStore.load()

            let tools = buildTools()
            let session = try SessionFactory.makeSession(
                assignment: config.chat,
                config: config,
                instructions: systemPrompt,
                tools: tools
            )

            // Restore conversation context
            // NOTE: check if LanguageModelSession supports multi-turn via
            // repeated respond() calls or if we need to pass history differently.
            // If Transcript auto-accumulates, we may need a persistent session.

            continuation.yield(.messageStarted(messageId))

            // Stream the response — AnyLanguageModel handles tool calling automatically
            let stream = session.streamResponse(to: message, generating: String.self)
            var fullResponse = ""

            for try await partial in stream {
                // NOTE: verify what `partial` type is — likely a Snapshot with text
                // Adjust based on actual ResponseStream API
                let delta = partial.text  // or partial.content — check actual API
                if !delta.isEmpty {
                    fullResponse = delta  // Snapshot contains cumulative text
                    continuation.yield(.textDelta(delta))
                }
            }

            uiHistory.append((role: "assistant", content: fullResponse))
            continuation.yield(.messageComplete)
            continuation.finish()
        } catch {
            continuation.yield(.error(error.localizedDescription))
            continuation.finish()
        }
    }

    // MARK: - Tool Construction

    private func buildTools() -> [any Tool] {
        [
            GetTransactionsTool(queryService: queryService),
            GetSpendingSummaryTool(queryService: queryService),
            GetCategoryBreakdownTool(queryService: queryService),
            GetTopMerchantsTool(queryService: queryService),
            GetUpcomingPaymentsTool(queryService: queryService),
            GetGoalsTool(queryService: queryService),
            SearchTransactionsTool(queryService: queryService),
            GetAccountOverviewTool(queryService: queryService),
            SemanticSearchTool(queryService: queryService, embeddingService: embeddingService),
        ]
    }

    // MARK: - System Prompt
    // buildSystemPrompt() stays exactly as-is (lines 151-196 of current file)
}
```

> **CRITICAL NOTES for implementer:**
>
> 1. **Streaming API**: `session.streamResponse(to:generating:)` returns a `ResponseStream<String>`.
>    Check how to iterate it. It may yield `ResponseStream.Snapshot` objects with a `.content` property.
>    The streaming delta logic may need adjustment based on actual API.
>
> 2. **Conversation history**: `LanguageModelSession` maintains its own `Transcript`.
>    If creating a new session per message (current pattern), history is lost.
>    Options: (a) keep a persistent session instance, or (b) replay history via multiple
>    `respond()` calls. Investigate which approach AnyLanguageModel supports.
>
> 3. **Tool call events**: The current ChatEngine emits `.toolCallStarted(name)` events.
>    Check if AnyLanguageModel's `ToolExecutionDelegate` can provide this — it allows
>    observing tool executions. If available, set it on the session.
>
> 4. **`restoreMessage` and `clearHistory`**: These are used by the UI to restore chat state.
>    Decide if they should replay into the `LanguageModelSession`'s transcript.

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | grep -i error | head -20`

Fix any compile errors based on actual AnyLanguageModel API.

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/ChatEngine.swift
git commit -m "refactor: migrate ChatEngine to AnyLanguageModel with Tool protocol"
```

---

## Phase 3: Migrate Non-Tool Call Sites

### Task 9: Migrate LLMProcessor

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/LLMProcessor.swift` (5 call sites)

**Step 1: Add import**

Add `import AnyLanguageModel` at top of file.

**Step 2: Migrate each call site**

All 5 sites follow the same pattern. For each site at lines 144-153, 224-233, 280-289, 359-368:

Before:
```swift
let session = try SessionFactory.makeSession(
    assignment: providerConfig.extraction,
    config: providerConfig
)
let response = try await session.complete(
    messages: [
        .system(systemPrompt),
        .user(userPrompt)
    ],
    temperature: PFMConfig.llmTemperature
)
```

After:
```swift
let session = try SessionFactory.makeSession(
    assignment: providerConfig.extraction,
    config: providerConfig,
    instructions: systemPrompt
)
let response = try await session.respond(to: userPrompt, generating: String.self)
```

**Step 3: Migrate image extraction** (line 376-396)

Before:
```swift
let message = LLMMessage.userWithImage(
    text: "Extract all financial transaction information...",
    imageBase64: base64
)
let session = try SessionFactory.makeSession(
    assignment: providerConfig.extraction,
    config: providerConfig
)
return try await session.complete(messages: [message], temperature: PFMConfig.llmTemperature)
```

After:
```swift
let session = try SessionFactory.makeSession(
    assignment: providerConfig.extraction,
    config: providerConfig,
    instructions: "Extract all financial transaction information from this image. Include amounts, currencies, merchant names, dates, and transaction types. Return the extracted text in a structured format."
)
return try await session.respond(to: "Please extract transactions from the attached image.", images: [.init(data: imageData)])
```

> **NOTE:** Check AnyLanguageModel's image API. It may use `.init(data:)` or `.init(url:)`.
> The current code passes base64 — AnyLanguageModel likely accepts `Data` directly.

**Step 4: Remove unused `LLMMessage` imports/references**

After migration, `LLMMessage` should no longer be referenced in this file.

**Step 5: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | grep -i error | head -20`

**Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/PFM/LLMProcessor.swift
git commit -m "refactor: migrate LLMProcessor to AnyLanguageModel"
```

---

### Task 10: Migrate PDFExtractor

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/PDFExtractor.swift` (3 call sites at lines 107, 158, 247)

**Step 1: Add import and migrate all 3 call sites**

Same pattern as LLMProcessor. Each site:
- `session.complete(messages: [.system(x), .user(y)])` → `session.respond(to: y, generating: String.self)` with `instructions: x`

**Step 2: Verify and commit**

```bash
git add LedgeIt/LedgeIt/PFM/PDFExtractor.swift
git commit -m "refactor: migrate PDFExtractor to AnyLanguageModel"
```

---

### Task 11: Migrate DeduplicationService, GoalPlanner, FinancialAdvisor, PromptOptimizer

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/DeduplicationService.swift` (line 256)
- Modify: `LedgeIt/LedgeIt/PFM/GoalPlanner.swift` (line 138)
- Modify: `LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift` (line 117)
- Modify: `LedgeIt/LedgeIt/PFM/PromptOptimizer.swift` (line 79)

**Step 1: Migrate each file**

Same pattern. Special case for `DeduplicationService.swift:269`:
- Current code passes `messages: [.user(prompt)]` with no system message
- After: `instructions: ""`, `respond(to: prompt, generating: String.self)`

**Step 2: Verify and commit**

```bash
git add LedgeIt/LedgeIt/PFM/DeduplicationService.swift \
       LedgeIt/LedgeIt/PFM/GoalPlanner.swift \
       LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift \
       LedgeIt/LedgeIt/PFM/PromptOptimizer.swift
git commit -m "refactor: migrate remaining LLM call sites to AnyLanguageModel"
```

---

## Phase 4: Cleanup

### Task 12: Delete old provider code

**Files:**
- Delete: `LedgeIt/LedgeIt/Services/Providers/OpenAICompatibleSession.swift` (326 lines)
- Delete: `LedgeIt/LedgeIt/Services/Providers/AnthropicSession.swift` (348 lines)
- Delete: `LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift` (279 lines)
- Delete: `LedgeIt/LedgeIt/Services/Providers/LLMSession.swift` (44 lines)
- Delete: `LedgeIt/LedgeIt/Services/Providers/LLMTypes.swift` (150 lines)

**Step 1: Verify no remaining references**

Run:
```bash
cd LedgeIt && grep -r "LLMSession\|LLMMessage\|LLMToolDefinition\|LLMToolCall\|LLMStreamEvent\|LLMProviderError\|OpenAICompatibleSession\|AnthropicSession\|GoogleSession" LedgeIt/ --include="*.swift" | grep -v "//.*LLM" | grep -v ".build/"
```

Expected: No matches (or only comments/docs)

**Step 2: Delete the files**

```bash
rm LedgeIt/LedgeIt/Services/Providers/OpenAICompatibleSession.swift \
   LedgeIt/LedgeIt/Services/Providers/AnthropicSession.swift \
   LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift \
   LedgeIt/LedgeIt/Services/Providers/LLMSession.swift \
   LedgeIt/LedgeIt/Services/Providers/LLMTypes.swift
```

**Step 3: Final build verification**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove old LLM provider sessions and shared types (~1,133 lines)"
```

---

### Task 13: Update CLAUDE.md and documentation

**Files:**
- Modify: `CLAUDE.md`
- Modify: `README.md` (if architecture diagram needs updating)

**Step 1: Update architecture section in CLAUDE.md**

Update the AI Provider Architecture section to reflect AnyLanguageModel usage:
- Remove references to `OpenAICompatibleSession`, `AnthropicSession`, `GoogleSession`
- Remove `LLMSession` protocol reference
- Remove `LLMTypes.swift` reference
- Add AnyLanguageModel dependency note
- Update `SessionFactory` description
- Add `Services/Tools/` directory description

**Step 2: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: update architecture docs for AnyLanguageModel migration"
```

---

## Summary

| Phase | Tasks | Lines removed | Lines added (est.) |
|-------|-------|---------------|-------------------|
| 0: PoC | 1-3 | 0 | ~200 (tests) |
| 1: Tools | 4-6 | 0 | ~400 (10 tool files) |
| 2: ChatEngine | 7-8 | ~400 | ~150 |
| 3: Call sites | 9-11 | ~60 | ~40 |
| 4: Cleanup | 12-13 | ~1,133 | ~20 (docs) |
| **Total** | 13 tasks | **~1,593** | **~810** |

**Net reduction: ~783 lines**, plus gaining Gemini tool calling, type-safe tools, auto tool loop, and 9-provider support.
