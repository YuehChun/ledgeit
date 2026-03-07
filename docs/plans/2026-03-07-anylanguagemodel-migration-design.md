# AnyLanguageModel Migration Design

## Overview

Migrate LedgeIt's multi-provider AI architecture from custom `LLMSession` implementations to [AnyLanguageModel](https://github.com/mattt/AnyLanguageModel) (Option C: full adoption including Tool protocol). This eliminates ~1,133 lines of hand-rolled provider code, gains Gemini tool calling support, and standardizes the tool definition pattern.

## Decision Context

### Problem

- **Code duplication**: SSE streaming setup, tool call aggregation, and message serialization duplicated across 3 provider sessions (~950 lines)
- **Missing features**: GoogleSession lacks tool calling — ChatEngine tool workflows silently break with Gemini
- **Extensibility**: Adding a new provider requires changes in 6+ locations
- **No plugin/dynamic tool support**: Tools are hardcoded JSON Schema dicts in ChatEngine

### Alternatives Considered

| Option | Description | Verdict |
|--------|-------------|---------|
| A: AnyLanguageModel provider layer + custom tool layer | Use AnyLanguageModel only for HTTP/streaming, handle tools ourselves | **Rejected** — AnyLanguageModel's session layer doesn't expose raw tool definition APIs; provider and tool layers are tightly coupled |
| B: Self-refactor with shared utilities | Extract SSEStreamParser, ToolCallAggregator, etc. | **Rejected** — reinvents the wheel; still requires maintaining 3 provider adapters |
| **C: Full AnyLanguageModel adoption** | Replace all sessions + adopt Tool protocol | **Selected** — eliminates provider maintenance, gains type-safe tools, auto tool loop |
| Apple FoundationModels | Apple's on-device AI framework | **Not applicable** — only supports Apple on-device models, no cloud providers |
| SwiftAgent | Autonomous agent SDK | **Not applicable** — requires macOS 26+, only 2 providers, WIP status |

### Key Findings

- AnyLanguageModel supports custom `baseURL` for OpenAI-compatible endpoints (critical for OpenRouter/Ollama/custom endpoints)
- 9 ChatEngine tools are all statically defined — can be converted to `Tool` + `@Generable`
- Conditional tools: define at compile time, filter at runtime — no issue
- MCP Server: independent architecture, doesn't use LLM session layer — unaffected
- Plugin system: `DynamicTool` wrapper using `DynamicGenerationSchema` + `DynamicArguments` — feasible but needs PoC validation

## Architecture

### Before

```
SessionFactory
  ├── OpenAICompatibleSession (326 lines)  ──┐
  ├── AnthropicSession (348 lines)           ├── Hand-rolled, heavy duplication
  └── GoogleSession (279 lines)              ──┘
        │
        ▼
LLMSession protocol (complete / streamComplete)
        │
        ▼
ChatEngine ←── LLMToolDefinition (JSON Schema, dynamic)
LLMProcessor / PDFExtractor / GoalPlanner / ...
```

### After

```
SessionFactory (simplified)
  ├── OpenAILanguageModel(baseURL, apiKey, model)    ──┐
  ├── AnthropicLanguageModel(apiKey, model)            ├── AnyLanguageModel
  └── GoogleLanguageModel(apiKey, model)               ──┘
        │
        ▼
LanguageModelSession (AnyLanguageModel)
  ├── tools: [any Tool]
  │     ├── GetTransactionsTool              ──┐
  │     ├── GetSpendingSummaryTool            │
  │     ├── ... (9 static tools)              ├── Tool + @Generable
  │     ├── DynamicTool (runtime)            ──┘  ← plugin system
  │     └── conditional filtering
  │
  ├── respond(to:) → String
  └── streamResponse(to:) → ResponseStream
        │
        ▼
ChatEngine (simplified — no manual tool loop)
LLMProcessor / PDFExtractor / GoalPlanner / ...
```

### What Changes

| Item | Removed | Added |
|------|---------|-------|
| Provider sessions | `OpenAICompatibleSession`, `AnthropicSession`, `GoogleSession` (~950 lines) | — |
| Shared types | `LLMTypes.swift` (`LLMMessage`, `LLMToolDefinition`, `LLMStreamEvent`) | AnyLanguageModel types |
| Tool definitions | `toolDefinitions: [LLMToolDefinition]` (JSON Schema) | 9 `Tool` structs + `DynamicTool` wrapper |
| Session protocol | `LLMSession` protocol | Direct `LanguageModelSession` usage |
| Tool loop | ChatEngine manual management | AnyLanguageModel automatic handling |

### What Stays

- `AIProviderConfigStore` — config persistence unchanged
- `AIProviderConfiguration` / `ModelAssignment` — config models unchanged
- `MCPServer` — fully independent, unaffected
- `FinancialQueryService` — query layer unchanged

## Provider Layer Migration

### SessionFactory

```swift
import AnyLanguageModel

static func makeSession(
    assignment: ModelAssignment,
    config: AIProviderConfiguration,
    instructions: String = "",
    tools: [any Tool] = []
) throws -> LanguageModelSession {
    let model = try makeModel(assignment: assignment, config: config)
    return LanguageModelSession(model: model, instructions: instructions, tools: tools)
}

private static func makeModel(
    assignment: ModelAssignment,
    config: AIProviderConfiguration
) throws -> any LanguageModel {
    switch assignment.provider {
    case .openAICompatible:
        guard let endpointId = assignment.endpointId,
              let endpoint = config.endpoints.first(where: { $0.id == endpointId })
        else { throw SessionError.endpointNotFound }
        let apiKey = endpoint.requiresAPIKey
            ? try KeychainService.loadAPIKey(for: endpoint.id)
            : nil
        return OpenAILanguageModel(
            baseURL: URL(string: endpoint.baseURL)!,
            apiKey: apiKey ?? "",
            model: assignment.model,
            apiVariant: .chatCompletions
        )
    case .anthropic:
        let apiKey = try KeychainService.loadAPIKey(for: .anthropicAPIKey)
        return AnthropicLanguageModel(apiKey: apiKey, model: assignment.model)
    case .google:
        let apiKey = try KeychainService.loadAPIKey(for: .googleAIAPIKey)
        return GoogleLanguageModel(apiKey: apiKey, model: assignment.model)
    }
}
```

### Call Site Migration Pattern

**Non-tool call sites** (LLMProcessor, PDFExtractor, GoalPlanner, etc.):

```swift
// Before
let session = try SessionFactory.makeSession(assignment: ..., config: config, instructions: "")
let result = try await session.complete(messages: [.system(systemPrompt), .user(userPrompt)], temperature: 0.1)

// After
let session = try SessionFactory.makeSession(assignment: ..., config: config, instructions: systemPrompt)
let result = try await session.respond(to: userPrompt, generating: String.self)
```

**Image input** (LLMProcessor vision):

```swift
// Before
let message = LLMMessage.userWithImage(text: prompt, imageBase64: data, mimeType: "image/png")
let result = try await session.complete(messages: [.system(systemPrompt), message])

// After
let session = try SessionFactory.makeSession(assignment: ..., config: config, instructions: systemPrompt)
let result = try await session.respond(to: prompt, images: [.init(data: imageData)])
```

**ChatEngine** (with tools):

```swift
// Before
let session = try SessionFactory.makeSession(assignment: chatAssignment, config: config)
// Manual tool loop: send → receive tool calls → execute → send results → repeat

// After
let session = try SessionFactory.makeSession(
    assignment: chatAssignment, config: config,
    instructions: systemPrompt, tools: activeTools
)
let stream = session.streamResponse(to: userMessage, generating: String.self)
// AnyLanguageModel handles tool loop automatically
```

## Tool Layer

### Static Tools (9 ChatEngine tools)

Each tool becomes a self-contained struct with type-safe arguments:

```swift
struct GetTransactionsTool: Tool {
    let queryService: FinancialQueryService
    var description: String { "Get a list of transactions with optional filters" }

    @Generable
    struct Arguments {
        @Guide(description: "Start date (yyyy-MM-dd)") var start_date: String?
        @Guide(description: "End date (yyyy-MM-dd)") var end_date: String?
        @Guide(description: "Filter by category") var category: String?
        @Guide(description: "Filter by merchant name") var merchant: String?
        @Guide(description: "Minimum transaction amount") var min_amount: Double?
        @Guide(description: "Maximum transaction amount") var max_amount: Double?
        @Guide(description: "Transaction type: debit, credit, or transfer") var type: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let transactions = try await queryService.getTransactions(
            startDate: arguments.start_date, endDate: arguments.end_date,
            category: arguments.category, merchant: arguments.merchant
        )
        return formatAsJSON(transactions)
    }
}
```

### File Structure

```
Services/Tools/
  ├── GetTransactionsTool.swift
  ├── GetSpendingSummaryTool.swift
  ├── GetCategoryBreakdownTool.swift
  ├── GetTopMerchantsTool.swift
  ├── GetUpcomingPaymentsTool.swift
  ├── GetGoalsTool.swift
  ├── SearchTransactionsTool.swift
  ├── GetAccountOverviewTool.swift
  ├── SemanticSearchTool.swift
  └── DynamicTool.swift
```

### DynamicTool (plugin system)

```swift
struct DynamicTool: Tool {
    typealias Arguments = DynamicArguments
    typealias Output = String

    let name: String
    let description: String
    private let schema: GenerationSchema
    let handler: @Sendable (DynamicArguments) async throws -> String

    var parameters: GenerationSchema { schema }

    init(name: String, description: String, schema: DynamicGenerationSchema,
         handler: @Sendable @escaping (DynamicArguments) async throws -> String) {
        self.name = name
        self.description = description
        self.schema = schema.toGenerationSchema()
        self.handler = handler
    }

    func call(arguments: DynamicArguments) async throws -> String {
        try await handler(arguments)
    }
}

struct DynamicArguments: ConvertibleFromGeneratedContent {
    private let content: GeneratedContent

    init(from content: GeneratedContent) { self.content = content }

    func string(for key: String) -> String? { try? content.value(String.self, forProperty: key) }
    func double(for key: String) -> Double? { try? content.value(Double.self, forProperty: key) }
    func int(for key: String) -> Int? { try? content.value(Int.self, forProperty: key) }
    func bool(for key: String) -> Bool? { try? content.value(Bool.self, forProperty: key) }
}
```

### Conditional Tool Filtering

```swift
private func activeTools(for context: UserContext) -> [any Tool] {
    var tools: [any Tool] = [
        GetTransactionsTool(queryService: queryService),
        GetSpendingSummaryTool(queryService: queryService),
        GetCategoryBreakdownTool(queryService: queryService),
        GetTopMerchantsTool(queryService: queryService),
        SearchTransactionsTool(queryService: queryService),
        GetAccountOverviewTool(queryService: queryService),
    ]
    if context.hasGoals { tools.append(GetGoalsTool(queryService: queryService)) }
    if context.hasCreditCards { tools.append(GetUpcomingPaymentsTool(queryService: queryService)) }
    if context.semanticSearchEnabled { tools.append(SemanticSearchTool(queryService: queryService)) }
    tools.append(contentsOf: pluginRegistry.activeTools)
    return tools
}
```

## Migration Strategy

### Phases

```
Phase 0: PoC Validation (blocking)
    │
    ▼
Phase 1: Add AnyLanguageModel dependency + static tools
    │
    ▼
Phase 2: Migrate ChatEngine (tool calling loop)
    │
    ▼
Phase 3: Migrate non-tool call sites (LLMProcessor, PDFExtractor, etc.)
    │
    ▼
Phase 4: Cleanup old code + DynamicTool
```

### Phase 0: PoC Validation

| # | Validation | Blocking Level |
|---|-----------|----------------|
| P0-1 | OpenAI-compatible custom baseURL works | RED — abort Option C on failure |
| P0-2 | Tool protocol auto-executes and returns results | RED — abort Option C on failure |
| P0-3 | Multi-round tool calling (tool→result→tool→result) works | RED — abort Option C on failure |
| P0-4 | DynamicTool wrapper works | YELLOW — only affects plugin system |

### Decision Tree

```
P0-1 pass?
  ├─ no → Abort Option C, execute Option B
  └─ yes → P0-2 pass?
              ├─ no → Abort Option C, execute Option B
              └─ yes → P0-3 pass?
                          ├─ no → Abort Option C, execute Option B
                          └─ yes → P0-4 pass?
                                      ├─ no → Execute Option C without plugin tools (plugin stays custom)
                                      └─ yes → Full Option C ✅
```

### Phase 1: Add Dependency + Build Tools

- Add `AnyLanguageModel` to `Package.swift`
- Create `Services/Tools/` directory with 9 static tool structs
- Create `DynamicTool.swift`
- No changes to existing sessions — both systems coexist

### Phase 2: Migrate ChatEngine

- Replace `any LLMSession` with `LanguageModelSession`
- Remove manual tool call loop (`handleToolCall` switch-case)
- Remove `toolDefinitions: [LLMToolDefinition]` computed property
- Switch streaming to `session.streamResponse(to:generating:)`

### Phase 3: Migrate Non-Tool Call Sites

All 11 non-ChatEngine call sites follow the same pattern:

| Call Site | Change |
|-----------|--------|
| `LLMProcessor` (5 sites) | `session.complete()` → `session.respond(to:generating:String.self)` |
| `PDFExtractor` (3 sites) | Same |
| `DeduplicationService` | Same |
| `GoalPlanner` | Same |
| `FinancialAdvisor` | Same |
| `PromptOptimizer` | Same |

### Phase 4: Cleanup

| File | Lines Removed |
|------|---------------|
| `OpenAICompatibleSession.swift` | 326 |
| `AnthropicSession.swift` | 348 |
| `GoogleSession.swift` | 279 |
| `LLMSession.swift` (protocol) | ~30 |
| `LLMTypes.swift` (shared types) | 150 |
| **Total** | **~1,133** |

## Risk Mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| PoC validates DynamicTool fails | Medium | Proceed without plugin tools; plugin layer stays custom |
| AnyLanguageModel streaming API doesn't expose intermediate text deltas | Low | ResponseStream has Snapshot — should provide partial results |
| AnyLanguageModel v0.7 breaking API changes | Medium | Pin version; SessionFactory isolates — update in one place |
| Multi-round tool calling not supported | Low | Validate in PoC; Transcript docs show multi-round support |
| LLMProcessor multi-message format incompatible | Low | All sites use system+user pattern → maps to instructions + respond(to:) |
