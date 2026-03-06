# Multi-Provider AI Architecture — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the monolithic `OpenRouterService` with a SwiftAgent-based multi-provider architecture supporting OpenAI-compatible endpoints, Anthropic, and Google.

**Architecture:** Adopt SwiftAgent as the unified session framework. Build a custom `OpenAICompatibleSession` adapter (refactored from existing `OpenRouterService`) and a `GoogleSession` adapter. Use `SessionFactory` to create the right session per provider. Migrate all 8 LLM-consuming services incrementally.

**Tech Stack:** Swift 6, SwiftAgent (OpenAISession, AnthropicSession), SwiftUI, GRDB, macOS 26+

**Design doc:** `docs/plans/2026-03-07-multi-provider-ai-design.md`

---

## Task 1: Add SwiftAgent Dependency and Bump macOS Target

**Files:**
- Modify: `LedgeIt/Package.swift`

**Step 1: Update Package.swift**

Add SwiftAgent dependency and bump platform to macOS 26:

```swift
// In platforms:
platforms: [.macOS(.v26)]

// In dependencies:
.package(url: "https://github.com/SwiftedMind/SwiftAgent.git", branch: "main"),

// In target "LedgeIt" dependencies:
.product(name: "OpenAISession", package: "SwiftAgent"),
.product(name: "AnthropicSession", package: "SwiftAgent"),
```

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeds (or warnings only, no errors)

**Step 3: Commit**

```bash
git add LedgeIt/Package.swift LedgeIt/Package.resolved
git commit -m "chore: add SwiftAgent dependency and bump macOS target to 26"
```

---

## Task 2: Create Provider Config Models

**Files:**
- Create: `LedgeIt/LedgeIt/Models/AIProviderConfig.swift`

**Step 1: Create the provider config models**

```swift
import Foundation

// MARK: - Provider Types

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAICompatible
    case anthropic
    case google
}

// MARK: - OpenAI Compatible Endpoint Config

struct OpenAICompatibleEndpoint: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var requiresAPIKey: Bool
    var defaultModel: String

    static let builtInPresets: [OpenAICompatibleEndpoint] = [
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            requiresAPIKey: true,
            defaultModel: "gpt-4.1"
        ),
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            requiresAPIKey: true,
            defaultModel: "anthropic/claude-sonnet-4-6"
        ),
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            requiresAPIKey: false,
            defaultModel: "llama3.2"
        ),
    ]
}

// MARK: - Per-Use-Case Model Assignment

struct ModelAssignment: Codable, Sendable {
    var provider: AIProvider
    var endpointId: UUID?  // Only for .openAICompatible
    var model: String
}

// MARK: - Full Provider Configuration

struct AIProviderConfiguration: Codable, Sendable {
    var endpoints: [OpenAICompatibleEndpoint]
    var classification: ModelAssignment
    var extraction: ModelAssignment
    var statement: ModelAssignment
    var chat: ModelAssignment

    static var `default`: AIProviderConfiguration {
        let openRouter = OpenAICompatibleEndpoint.builtInPresets[1] // OpenRouter
        let defaultAssignment = ModelAssignment(
            provider: .openAICompatible,
            endpointId: openRouter.id,
            model: "anthropic/claude-sonnet-4-6"
        )
        return AIProviderConfiguration(
            endpoints: OpenAICompatibleEndpoint.builtInPresets,
            classification: ModelAssignment(
                provider: .openAICompatible,
                endpointId: openRouter.id,
                model: "anthropic/claude-haiku-4-5"
            ),
            extraction: defaultAssignment,
            statement: ModelAssignment(
                provider: .openAICompatible,
                endpointId: openRouter.id,
                model: "google/gemini-2.5-pro"
            ),
            chat: defaultAssignment
        )
    }
}
```

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Models/AIProviderConfig.swift
git commit -m "feat: add AI provider configuration models"
```

---

## Task 3: Update KeychainService for Multiple Providers

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/KeychainService.swift:11-17` (Key enum)

**Step 1: Add new Keychain keys**

In the `Key` enum (line 11-17), add:

```swift
enum Key: String, Sendable, CaseIterable {
    case openRouterAPIKey       // existing
    case googleClientID         // existing
    case googleClientSecret     // existing
    case googleAccessToken      // existing
    case googleRefreshToken     // existing
    case anthropicAPIKey        // NEW
    case googleAIAPIKey         // NEW (for Gemini API, separate from OAuth)
}
```

**Step 2: Add endpoint-specific key storage**

Add methods for OpenAI Compatible endpoint API keys (stored per endpoint UUID):

```swift
// Store/retrieve API keys for OpenAI Compatible endpoints
static func saveEndpointAPIKey(endpointId: UUID, value: String) throws {
    try saveRaw(account: "endpoint_\(endpointId.uuidString)", value: value)
}

static func loadEndpointAPIKey(endpointId: UUID) -> String? {
    loadRaw(account: "endpoint_\(endpointId.uuidString)")
}

static func deleteEndpointAPIKey(endpointId: UUID) {
    deleteRaw(account: "endpoint_\(endpointId.uuidString)")
}
```

**Step 3: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Services/KeychainService.swift
git commit -m "feat: add Keychain keys for Anthropic, Google AI, and per-endpoint storage"
```

---

## Task 4: Build OpenAICompatibleSession Adapter

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Providers/OpenAICompatibleSession.swift`

This is the core adapter, refactored from the existing `OpenRouterService.swift` (455 lines). It implements the SwiftAgent Session protocol with a configurable base URL.

**Step 1: Create the adapter**

Refactor `OpenRouterService` into `OpenAICompatibleSession`:
- Keep the HTTP client logic (request building, SSE parsing, tool call handling)
- Replace hardcoded `https://openrouter.ai/api/v1` with configurable `baseURL`
- Make `apiKey` optional (nil for Ollama)
- Conform to SwiftAgent's Session protocol
- Preserve: `Message`, `ToolDefinition`, `ToolCall`, `StreamEvent` types
- Preserve: `complete()` and `streamComplete()` methods
- Add: `respond(to:)` and `respond(to:generating:)` for SwiftAgent compatibility
- Add: `stream(to:)` for SwiftAgent streaming compatibility

Key changes from `OpenRouterService`:
- `init(baseURL: String, apiKey: String?, model: String, instructions: String = "")`
- Remove `fetchCredits()` (OpenRouter-specific, move to separate utility)
- Authorization header: only include `Bearer {apiKey}` when apiKey is non-nil
- Remove hardcoded `HTTP-Referer` and `X-Title` headers (OpenRouter-specific)

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Providers/OpenAICompatibleSession.swift
git commit -m "feat: add OpenAICompatibleSession adapter for multi-provider support"
```

---

## Task 5: Build GoogleSession Adapter

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift`

Google Gemini API client conforming to the same session interface.

**Step 1: Create the adapter**

Google Gemini API specifics:
- Base URL: `https://generativelanguage.googleapis.com/v1beta`
- Auth: API key as query parameter `?key={apiKey}` (not Bearer token)
- Endpoint: `POST /models/{model}:generateContent`
- Streaming: `POST /models/{model}:streamGenerateContent?alt=sse`
- Request format differs from OpenAI (roles: "user"/"model", parts-based content)
- Response format: `candidates[0].content.parts[0].text`

Implement the same interface as `OpenAICompatibleSession`:
- `complete(model:messages:temperature:maxTokens:)` → String
- `streamComplete(model:messages:tools:temperature:maxTokens:)` → AsyncStream<StreamEvent>

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift
git commit -m "feat: add GoogleSession adapter for Gemini API"
```

---

## Task 6: Create SessionFactory

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift`

**Step 1: Create the factory**

```swift
import Foundation

enum SessionFactory {
    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingAPIKey(provider: String)
        case connectionFailed(provider: String)
        case invalidAPIKey(provider: String)
        case modelNotAvailable(model: String)
        case quotaExceeded(provider: String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint not found: \(id)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            case .connectionFailed(let provider):
                return "Cannot connect to \(provider)"
            case .invalidAPIKey(let provider):
                return "Invalid API key for \(provider)"
            case .modelNotAvailable(let model):
                return "Model not available: \(model)"
            case .quotaExceeded(let provider):
                return "Quota exceeded for \(provider)"
            }
        }
    }

    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        instructions: String = ""
    ) throws -> OpenAICompatibleSession {
        // For now, all providers route through OpenAICompatibleSession
        // Anthropic and Google will get their own sessions in future tasks
        switch assignment.provider {
        case .openAICompatible:
            guard let endpointId = assignment.endpointId,
                  let endpoint = config.endpoints.first(where: { $0.id == endpointId }) else {
                throw SessionError.endpointNotFound(assignment.endpointId ?? UUID())
            }
            let apiKey: String? = endpoint.requiresAPIKey
                ? KeychainService.loadEndpointAPIKey(endpointId: endpoint.id)
                : nil
            if endpoint.requiresAPIKey && apiKey == nil {
                throw SessionError.missingAPIKey(provider: endpoint.name)
            }
            return OpenAICompatibleSession(
                baseURL: endpoint.baseURL,
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )

        case .anthropic:
            guard let apiKey = KeychainService.load(key: .anthropicAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Anthropic")
            }
            // Route through OpenAI Compatible for now
            // TODO: Switch to SwiftAgent AnthropicSession when ready
            return OpenAICompatibleSession(
                baseURL: "https://openrouter.ai/api/v1",
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )

        case .google:
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            // Route through GoogleSession adapter
            // TODO: Replace with GoogleSession when implemented
            return OpenAICompatibleSession(
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )
        }
    }
}
```

Note: Initially all providers route through `OpenAICompatibleSession`. The Anthropic and Google cases will be updated to use their native adapters (Task 5 for Google, SwiftAgent's `AnthropicSession` for Anthropic) once those are validated.

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift
git commit -m "feat: add SessionFactory for multi-provider session creation"
```

---

## Task 7: Add Provider Config Persistence

**Files:**
- Create: `LedgeIt/LedgeIt/Services/AIProviderConfigStore.swift`

**Step 1: Create the config store**

A simple UserDefaults-backed store for `AIProviderConfiguration`:

```swift
import Foundation

enum AIProviderConfigStore {
    private static let key = "aiProviderConfiguration"

    static func load() -> AIProviderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(AIProviderConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    static func save(_ config: AIProviderConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Migrate from legacy OpenRouter-only config (PFMConfig + KeychainService)
    static func migrateFromLegacy() -> AIProviderConfiguration? {
        // Check if legacy OpenRouter key exists
        guard let openRouterKey = KeychainService.load(key: .openRouterAPIKey) else {
            return nil
        }

        // Check if already migrated
        if UserDefaults.standard.data(forKey: key) != nil {
            return nil
        }

        var config = AIProviderConfiguration.default
        let openRouterEndpoint = config.endpoints.first(where: { $0.name == "OpenRouter" })!

        // Save the OpenRouter API key to the endpoint keychain slot
        try? KeychainService.saveEndpointAPIKey(
            endpointId: openRouterEndpoint.id,
            value: openRouterKey
        )

        // Map existing model selections
        let classModel = UserDefaults.standard.string(forKey: "llmClassificationModel")
        let extractModel = UserDefaults.standard.string(forKey: "llmExtractionModel")
        let stmtModel = UserDefaults.standard.string(forKey: "llmStatementModel")
        let chatModel = UserDefaults.standard.string(forKey: "llmChatModel")

        if let m = classModel, !m.isEmpty {
            config.classification.model = m
        }
        if let m = extractModel, !m.isEmpty {
            config.extraction.model = m
        }
        if let m = stmtModel, !m.isEmpty {
            config.statement.model = m
        }
        if let m = chatModel, !m.isEmpty {
            config.chat.model = m
        }

        save(config)
        return config
    }
}
```

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Services/AIProviderConfigStore.swift
git commit -m "feat: add AIProviderConfigStore with legacy migration"
```

---

## Task 8: Migrate LLMProcessor

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/LLMProcessor.swift`

This is the first service migration — validates the whole architecture.

**Step 1: Update LLMProcessor to accept session instead of OpenRouterService**

Key changes:
- Replace `let openRouter: OpenRouterService` with a session-creation closure or direct session
- Since LLMProcessor uses different models for different tasks (classificationModel, extractionModel, visionModel), it needs to create sessions per call or accept a factory
- Change `init(openRouter: OpenRouterService)` to `init(config: AIProviderConfiguration)`
- Each method creates a session via `SessionFactory.makeSession(assignment:config:instructions:)`
- Keep the existing `parseJSON<T>()` helper (StructuredOutput migration is a future optimization)
- Keep all existing `Codable` result types unchanged

Methods to update (5 total):
1. `classifyEmail()` — line 144: replace `openRouter.complete(model: PFMConfig.classificationModel, ...)` with `session.complete(model: assignment.model, ...)`
2. `extractTransactions()` — line 221: same pattern
3. `extractCreditCardBill()` — line 274: same pattern
4. `analyzeSpending()` — line 350: same pattern
5. `extractFromImage()` — line 376: same pattern (vision model)

**Step 2: Update all callers of LLMProcessor**

Search for `LLMProcessor(openRouter:` and update to `LLMProcessor(config:`:
- `LedgeIt/LedgeIt/PFM/ExtractionPipeline.swift`
- `LedgeIt/LedgeIt/Services/StatementService.swift:92-93`
- Any other file that creates LLMProcessor

**Step 3: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 4: Manual test**

Run the app, trigger an email sync or statement import to verify extraction still works.

**Step 5: Commit**

```bash
git add -u
git commit -m "refactor: migrate LLMProcessor from OpenRouterService to SessionFactory"
```

---

## Task 9: Migrate FinancialAdvisor

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift`

**Step 1: Update init and complete() calls**

Same pattern as LLMProcessor:
- Replace `let openRouter: OpenRouterService` with `let config: AIProviderConfiguration`
- Line 117: replace `openRouter.complete(model: PFMConfig.extractionModel, ...)` with session-based call
- Keep `parseJSON()` and `SpendingAdvice`/`CategoryInsight` types unchanged

**Step 2: Update callers**

- `LedgeIt/LedgeIt/PFM/ReportGenerator.swift:15-20` (init)
- `LedgeIt/LedgeIt/Services/GoalGenerationService.swift:47`

**Step 3: Verify build and commit**

```bash
git add -u
git commit -m "refactor: migrate FinancialAdvisor from OpenRouterService to SessionFactory"
```

---

## Task 10: Migrate GoalPlanner

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/GoalPlanner.swift`

**Step 1: Update init and complete() calls**

- Replace `let openRouter: OpenRouterService` with `let config: AIProviderConfiguration`
- Line 138: replace `openRouter.complete(model: PFMConfig.extractionModel, ...)` with session-based call
- Keep `parseJSON()`, `GoalSuggestions`/`GoalSuggestion` types, and `saveGoals()` unchanged

**Step 2: Update callers**

- `LedgeIt/LedgeIt/PFM/ReportGenerator.swift:15-20`
- `LedgeIt/LedgeIt/Services/GoalGenerationService.swift:60`

**Step 3: Verify build and commit**

```bash
git add -u
git commit -m "refactor: migrate GoalPlanner from OpenRouterService to SessionFactory"
```

---

## Task 11: Migrate PromptOptimizer

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/PromptOptimizer.swift`

**Step 1: Update init and complete() calls**

- Replace `let openRouter: OpenRouterService` with `let config: AIProviderConfiguration`
- Line 79: replace `openRouter.complete(model: PFMConfig.extractionModel, ...)` with session-based call

**Step 2: Update caller**

- `LedgeIt/LedgeIt/Views/Analysis/AdvisorSettingsView.swift:313-314`

**Step 3: Verify build and commit**

```bash
git add -u
git commit -m "refactor: migrate PromptOptimizer from OpenRouterService to SessionFactory"
```

---

## Task 12: Migrate ReportGenerator and GoalGenerationService

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/ReportGenerator.swift`
- Modify: `LedgeIt/LedgeIt/Services/GoalGenerationService.swift`

**Step 1: Update ReportGenerator**

- Change `init(database: AppDatabase, openRouter: OpenRouterService)` to `init(database: AppDatabase, config: AIProviderConfiguration)`
- Pass `config` to `FinancialAdvisor` and `GoalPlanner` instead of `openRouter`

**Step 2: Update GoalGenerationService**

- Lines 45, 60: replace `let openRouter = try OpenRouterService()` with `let config = AIProviderConfigStore.load()`
- Pass `config` to `FinancialAdvisor` and `GoalPlanner`

**Step 3: Update callers of ReportGenerator**

Search for `ReportGenerator(database:openRouter:` and update.

**Step 4: Verify build and commit**

```bash
git add -u
git commit -m "refactor: migrate ReportGenerator and GoalGenerationService to provider config"
```

---

## Task 13: Migrate ChatEngine

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

This is the most complex migration. ChatEngine uses streaming + tool calling.

**Step 1: Update session creation**

- Replace `OpenRouterService` dependency with `AIProviderConfiguration`
- Use `SessionFactory.makeSession(assignment: config.chat, ...)` to create session
- The session's `streamComplete()` method replaces `OpenRouterService.performStreamComplete()`

**Step 2: Update tool definitions**

- Convert the 9 `ToolDefinition` structs (lines 232-345) to use `OpenAICompatibleSession`'s tool format
- Keep the same JSON schema structure — this is OpenAI-compatible format, works across all providers
- No need to change to SwiftAgent `@SessionSchema` yet (that's a future optimization)

**Step 3: Update streaming loop**

- Lines 93-99: replace `OpenRouterService.performStreamComplete(...)` with `session.streamComplete(...)`
- The `StreamEvent` enum should be compatible — same cases (`.text`, `.toolCall`, `.done`, `.error`)

**Step 4: Update tool execution**

- `executeTool()` (lines 349-479) stays the same — it's provider-agnostic
- Only the session creation and stream call change

**Step 5: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`

**Step 6: Manual test**

Run the app, open Chat, ask a financial question that triggers tool calling (e.g., "What did I spend last month?").

**Step 7: Commit**

```bash
git add -u
git commit -m "refactor: migrate ChatEngine from OpenRouterService to SessionFactory"
```

---

## Task 14: Update Settings UI — AI Providers Section

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/SettingsView.swift`
- Create: `LedgeIt/LedgeIt/Views/Settings/AIProviderSettingsView.swift`

**Step 1: Create AIProviderSettingsView**

New view for managing providers:
- List of OpenAI Compatible endpoints (add/edit/delete)
- API key input for Anthropic
- API key input for Google AI
- Per-endpoint: name, base URL, API key (SecureField), default model
- Built-in presets shown with a "Built-in" badge
- "Add Custom Endpoint" button

**Step 2: Update Model Assignment section in SettingsView**

Replace the current 4 `ModelPicker` instances (lines 140-166) with provider-aware pickers:
- Each picker shows: `[Provider ▼] [Model ▼]`
- Provider dropdown: lists all configured providers (Anthropic, Google, + each OpenAI Compatible endpoint by name)
- Model dropdown: dynamic list fetched from `GET {baseURL}/models` for OpenAI Compatible, or hardcoded for Anthropic/Google

**Step 3: Remove old model-only pickers and OpenRouter credit display**

- Remove `@AppStorage("llmClassificationModel")` etc. (lines 19-22)
- Replace with `@State private var config: AIProviderConfiguration`
- Remove or relocate the OpenRouter credit balance card (make it per-endpoint)

**Step 4: Verify build and manual test**

Run the app, open Settings, verify provider management works.

**Step 5: Commit**

```bash
git add -u LedgeIt/LedgeIt/Views/
git add LedgeIt/LedgeIt/Views/Settings/AIProviderSettingsView.swift
git commit -m "feat: add multi-provider Settings UI with endpoint management"
```

---

## Task 15: Backward Compatibility Migration

**Files:**
- Modify: `LedgeIt/LedgeIt/LedgeItApp.swift` (or wherever app initialization happens)

**Step 1: Add migration on app launch**

In the app's initialization (before any LLM service is used):

```swift
// Run once: migrate legacy OpenRouter config to new provider config
if AIProviderConfigStore.migrateFromLegacy() != nil {
    print("[Migration] Migrated legacy OpenRouter config to multi-provider format")
}
```

**Step 2: Verify migration**

Test scenario:
1. Build and run the old version (set an OpenRouter API key)
2. Build and run the new version
3. Verify: OpenRouter endpoint is auto-configured, models are preserved, no re-setup needed

**Step 3: Commit**

```bash
git add -u
git commit -m "feat: add backward-compatible migration from legacy OpenRouter config"
```

---

## Task 16: Remove OpenRouterService

**Files:**
- Delete: `LedgeIt/LedgeIt/Services/OpenRouterService.swift`
- Modify: Any remaining references

**Step 1: Search for remaining references**

Run: `grep -rn "OpenRouterService" LedgeIt/LedgeIt/`
Expected: No results (all migrated in Tasks 8-13)

If any remain, update them to use `SessionFactory`.

**Step 2: Move credit-fetching logic (if needed)**

If the credit display feature is kept for OpenRouter endpoints, extract `fetchCredits()` / `fetchAccountCredits()` / `fetchKeyCredits()` into a standalone utility:
- Create: `LedgeIt/LedgeIt/Services/Providers/OpenRouterCreditsService.swift`
- Only used by Settings UI for OpenRouter endpoints

**Step 3: Delete OpenRouterService.swift**

```bash
git rm LedgeIt/LedgeIt/Services/OpenRouterService.swift
```

**Step 4: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Clean build with no references to `OpenRouterService`

**Step 5: Commit**

```bash
git add -u
git commit -m "refactor: remove OpenRouterService, migration complete"
```

---

## Task 17: Update PFMConfig for Provider-Aware Defaults

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/PFMConfig.swift`

**Step 1: Simplify PFMConfig**

Remove model selection logic from PFMConfig (now handled by `AIProviderConfiguration`):
- Remove: `defaultClassificationModel`, `defaultExtractionModel`, etc. (lines 255-258)
- Remove: computed properties `classificationModel`, `extractionModel`, etc. (lines 260-278)
- Remove: `availableModels` array (lines 292-300)
- Remove: `migrateModelId()` (lines 281-287)
- Keep: `llmTemperature`, `llmMaxTokens`, and all non-LLM config

**Step 2: Update any remaining references to PFMConfig model properties**

Search: `grep -rn "PFMConfig.classificationModel\|PFMConfig.extractionModel\|PFMConfig.statementModel\|PFMConfig.chatModel\|PFMConfig.visionModel\|PFMConfig.availableModels" LedgeIt/LedgeIt/`

Update all references to use `AIProviderConfigStore.load()` instead.

**Step 3: Verify build and commit**

```bash
git add -u
git commit -m "refactor: remove model selection from PFMConfig, now in AIProviderConfiguration"
```

---

## Task 18: Final Verification

**Step 1: Full build**

```bash
cd LedgeIt && swift build 2>&1
```
Expected: Clean build, no warnings related to provider changes.

**Step 2: Search for orphaned references**

```bash
grep -rn "OpenRouterService\|OpenRouterError\|openRouter\b" LedgeIt/LedgeIt/ --include="*.swift"
grep -rn "PFMConfig.classificationModel\|PFMConfig.extractionModel" LedgeIt/LedgeIt/ --include="*.swift"
```
Expected: No results.

**Step 3: Manual integration test checklist**

- [ ] App launches without crash
- [ ] Legacy migration: existing OpenRouter key auto-detected
- [ ] Settings > AI Providers: can see OpenRouter endpoint
- [ ] Settings > AI Providers: can add a new endpoint (e.g., Ollama)
- [ ] Settings > Model Assignment: can select provider + model per use case
- [ ] Email sync: classification and extraction work
- [ ] Chat: streaming response works
- [ ] Chat: tool calling works (ask "What did I spend last month?")
- [ ] Statement import: PDF extraction works
- [ ] Analysis dashboard: spending analysis generates
- [ ] Goals: goal suggestions generate

**Step 4: Final commit**

```bash
git add -u
git commit -m "chore: final cleanup after multi-provider migration"
```

---

## Summary

| Task | Description | Estimated Complexity |
|------|-------------|---------------------|
| 1 | Add SwiftAgent dependency | Low |
| 2 | Create provider config models | Low |
| 3 | Update KeychainService | Low |
| 4 | Build OpenAICompatibleSession | High (core adapter) |
| 5 | Build GoogleSession | Medium |
| 6 | Create SessionFactory | Medium |
| 7 | Add config persistence + migration | Medium |
| 8 | Migrate LLMProcessor | Medium (first migration, sets pattern) |
| 9 | Migrate FinancialAdvisor | Low (follows pattern) |
| 10 | Migrate GoalPlanner | Low (follows pattern) |
| 11 | Migrate PromptOptimizer | Low (follows pattern) |
| 12 | Migrate ReportGenerator + GoalGenerationService | Low |
| 13 | Migrate ChatEngine | High (streaming + tools) |
| 14 | Update Settings UI | High (new views) |
| 15 | Backward compatibility migration | Low |
| 16 | Remove OpenRouterService | Low |
| 17 | Update PFMConfig | Low |
| 18 | Final verification | Medium |
