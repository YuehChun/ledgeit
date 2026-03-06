# Multi-Provider AI Architecture Design

**Date**: 2026-03-07
**Status**: Approved
**Target**: macOS 26+ (SwiftAgent adoption)

## Goals

1. **Multi-provider support** — Direct API calls to Anthropic, OpenAI, Google, and any OpenAI-compatible service
2. **Local model support** — Ollama for offline/privacy use cases
3. **Extensible workflows** — Foundation for future agent chains, RAG, and multi-step reasoning
4. **Backward compatibility** — Existing OpenRouter users migrate seamlessly

## Priority Order

1. Provider abstraction layer + direct API support (maximize user coverage)
2. Ollama local model support (differentiation, offline capability)
3. Advanced agent workflows (future phase, not in this design)

## Approach: Pure SwiftAgent

Adopt [SwiftAgent](https://github.com/SwiftedMind/SwiftAgent) as the unified AI session framework.
Requires bumping minimum deployment target from macOS 14 to macOS 26.

## Provider Architecture

### Supported Providers

| Provider | Adapter | Source |
|----------|---------|--------|
| **OpenAI Compatible** | Custom `OpenAICompatibleSession` | Refactored from existing `OpenRouterService` |
| **Anthropic** | SwiftAgent built-in `AnthropicSession` | Direct use |
| **Google** | Custom `GoogleSession` | New |

### OpenAI Compatible — One Adapter, Many Services

`OpenAICompatibleSession` supports any service that implements the OpenAI API format.
Users can add multiple endpoints, each with its own name, base URL, API key, and default model.

Built-in presets:
- OpenAI (`https://api.openai.com/v1`)
- OpenRouter (`https://openrouter.ai/api/v1`)
- Ollama (`http://localhost:11434/v1`, no API key required)

User-addable examples: Groq, Deepseek, Together AI, Azure OpenAI, Fireworks, Mistral, etc.

### Provider Enum

```swift
enum AIProvider: String, CaseIterable, Codable {
    case openAICompatible   // OpenAI, OpenRouter, Ollama, Groq, Deepseek...
    case anthropic
    case google
}
```

### OpenAI Compatible Config

```swift
struct OpenAICompatibleConfig: Codable {
    var id: UUID
    var name: String          // User-defined label, e.g. "OpenRouter", "Ollama"
    var baseURL: String       // Custom endpoint
    var apiKey: String?       // nil for Ollama
    var defaultModel: String  // Default model ID
}
```

### Session Factory

```swift
struct SessionFactory {
    static func makeSession(
        for provider: AIProvider,
        instructions: String,
        config: AIProviderConfig
    ) throws -> some Session {
        switch provider {
        case .openAICompatible:
            let endpoint = config.openAICompatibleConfig
            return OpenAICompatibleSession(
                instructions: instructions,
                baseURL: endpoint.baseURL,
                apiKey: endpoint.apiKey,
                model: endpoint.defaultModel
            )
        case .anthropic:
            return AnthropicSession(
                instructions: instructions,
                apiKey: try KeychainService.get(.anthropicAPIKey)
            )
        case .google:
            return GoogleSession(
                instructions: instructions,
                apiKey: try KeychainService.get(.googleAIAPIKey)
            )
        }
    }
}
```

### Custom Adapters Scope

- **OpenAICompatibleSession** (~300-400 lines): Refactored from existing `OpenRouterService`, implements SwiftAgent Session protocol. Supports streaming, tool calling, and configurable base URL.
- **GoogleSession** (~200-300 lines): Google Gemini API client implementing SwiftAgent Session protocol.

## Service Migration

### Non-Streaming Services (Simple Migration)

These services call `complete()` and parse JSON strings. Migrate to `session.respond()` + `StructuredOutput`.

| Service | Current | After |
|---------|---------|-------|
| **LLMProcessor** | `openRouter.complete()` + manual JSON parsing | `session.respond(to:, generating: T.self)` |
| **FinancialAdvisor** | `openRouter.complete()` + manual JSON parsing | `session.respond(to:, generating: T.self)` |
| **GoalPlanner** | `openRouter.complete()` + manual JSON parsing | `session.respond(to:, generating: T.self)` |
| **PromptOptimizer** | `openRouter.complete()` + plain text | `session.respond(to:)` |
| **ReportGenerator** | Aggregates Advisor + Planner | Follows upstream changes |
| **GoalGenerationService** | Aggregates Advisor + Planner | Follows upstream changes |

### Streaming + Tool Calling (Major Refactor)

**ChatEngine** is the biggest change and biggest payoff.

Current: ~400 lines of manual SSE parsing, JSON tool schema definition, switch-case tool dispatch, manual agentic loop (5 iterations).

After: `@SessionSchema` with typed tools + `session.stream()`.

```swift
@SessionSchema
struct ChatSchema {
    @Tool var getTransactions = GetTransactionsTool()
    @Tool var getSpendingSummary = GetSpendingSummaryTool()
    @Tool var getCategoryBreakdown = GetCategoryBreakdownTool()
    @Tool var getTopMerchants = GetTopMerchantsTool()
    @Tool var getUpcomingPayments = GetUpcomingPaymentsTool()
    @Tool var getGoals = GetGoalsTool()
    @Tool var searchTransactions = SearchTransactionsTool()
    @Tool var getAccountOverview = GetAccountOverviewTool()
}
```

Each tool is a standalone struct conforming to SwiftAgent's `Tool` protocol with `@Generable` Arguments/Output — eliminating manual JSON schema and parsing.

Estimated reduction: ~300 lines removed from ChatEngine.

### Dependency Injection

```swift
// Before: each service instantiates OpenRouterService directly
let openRouter = try OpenRouterService()
let processor = LLMProcessor(openRouter: openRouter)

// After: SessionFactory injects the right session
let session = try SessionFactory.makeSession(for: config.extractionProvider, ...)
let processor = LLMProcessor(session: session)
```

### Migration Order

1. `SessionFactory` + `OpenAICompatibleSession` — infrastructure
2. `LLMProcessor` (classification + extraction) — core, validates architecture
3. `FinancialAdvisor` + `GoalPlanner` — follows LLMProcessor pattern
4. `PromptOptimizer` — simplest
5. `ChatEngine` — most complex, done last
6. Remove `OpenRouterService` — cleanup

## Settings UI

### Structure

```
Settings
+-- AI Providers
|   +-- Enabled provider list
|   |   +-- OpenRouter  (API Key: ****)  [default]
|   |   +-- Anthropic   (API Key: ****)
|   |   +-- Ollama      (localhost:11434) [free]
|   |
|   +-- [+ Add OpenAI Compatible Endpoint]
|   |   -> Name, Base URL, API Key, Default Model
|   |
|   +-- Built-in presets (deletable):
|       - OpenAI, OpenRouter, Ollama
|
+-- Model Assignment
|   +-- Classification: [Provider v] [Model v]
|   +-- Extraction:     [Provider v] [Model v]
|   +-- Statement:      [Provider v] [Model v]
|   +-- Chat:           [Provider v] [Model v]
|
+-- Advisor Persona (unchanged)
+-- About (unchanged)
```

### Model List Sources

| Provider | Model List |
|----------|-----------|
| OpenAI Compatible | Dynamic via `GET {baseURL}/models` |
| Anthropic | Hardcoded common models + manual input |
| Google | Hardcoded common models + manual input |

### Data Persistence

- Provider configs: UserDefaults (JSON encoded)
- Per-use-case provider + model selection: UserDefaults
- API keys: macOS Keychain (Anthropic, Google)
- OpenAI Compatible endpoint keys: Keychain (per endpoint)

## Backward Compatibility

### Existing User Migration

On first launch of updated version:
1. Detect existing OpenRouter API key in Keychain
2. Auto-create an OpenAI Compatible endpoint config for OpenRouter
3. Map existing model selections (UserDefaults) to OpenRouter provider
4. Seamless — no user action required

### New User Onboarding

First launch without any API key:
1. Setup wizard with options:
   - "I have an OpenRouter API key"
   - "I have an Anthropic / OpenAI / Google key"
   - "I want to use local models" (auto-detect Ollama)
   - "Custom endpoint"
2. Auto-recommend model assignments per use case

### Error Handling

```swift
enum ProviderError: LocalizedError {
    case connectionFailed(provider: String)  // Ollama not running
    case invalidAPIKey(provider: String)     // Expired/wrong key
    case modelNotAvailable(model: String)    // Model doesn't exist
    case quotaExceeded(provider: String)     // Credits exhausted
}
```

UI shows clear error message + guides user to switch provider.

## Out of Scope

The following are unchanged in this design:
- `FinancialQueryService` (query layer, no LLM)
- `MCPServer` (uses FinancialQueryService, no direct LLM)
- `IntentClassifier` (rule-based, no LLM)
- `AutoCategorizer` (mapping table, no LLM)
- `DeduplicationService` (logic comparison, no LLM)
- Database schema
- Google OAuth / Gmail API / Calendar API
