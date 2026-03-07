# Multi-Provider AI Architecture Fixes

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all PR review issues, remove SwiftAgent dependency, write our own AnthropicSession adapter, define a unified LLMSession protocol, and refactor ChatEngine to work with any provider.

**Architecture:** Three provider-specific session actors (`OpenAICompatibleSession`, `AnthropicSession`, `GoogleSession`) all conform to a shared `LLMSession` protocol. `SessionFactory` returns `any LLMSession`. `LLMMessage` is extended to support tool call/result messages so ChatEngine can run its tool-calling loop provider-agnostically.

**Tech Stack:** Swift 6.0, SwiftUI, URLSession, macOS 15+

---

## Already Done (from current uncommitted changes)

- ✅ C3: `migrateFromLegacy()` called in `LedgeItApp.swift`
- ✅ C4: SSE error payload checking in `OpenAICompatibleSession`
- ✅ C5: `AIProviderConfigStore` proper error handling with logging
- ✅ I4: ChatEngine no longer passes `instructions` to session (avoids duplication)
- ✅ I8: `OpenAICompatibleSession.complete()` now prepends `instructions` as system message
- ✅ I9 (partial): `GoogleSession.complete()` uses `x-goog-api-key` header
- ✅ I10: `deleteRaw` removes from cache instead of setting empty string
- ✅ S2: Removed unused type aliases from `OpenAICompatibleSession`

---

### Task 1: Remove SwiftAgent dependency, keep macOS v15

**Files:**
- Modify: `LedgeIt/Package.swift`

**Step 1: Remove SwiftAgent from Package.swift**

The dependency brings in heavy transitive deps (swift-syntax, SwiftAnthropic, async-http-client, swift-nio) but is never imported. The macOS target was already reverted to `.v15` in uncommitted changes. Remove SwiftAgent lines.

```swift
// Remove from dependencies array:
.package(url: "https://github.com/SwiftedMind/SwiftAgent.git", branch: "main"),

// Remove from target dependencies:
.product(name: "OpenAISession", package: "SwiftAgent"),
.product(name: "AnthropicSession", package: "SwiftAgent"),
```

Keep `swift-tools-version: 6.2` (needed for latest Swift concurrency features) but macOS target stays `.v15`.

**Step 2: Verify resolution**

Run: `cd LedgeIt && swift package resolve`
Expected: resolves without SwiftAgent

**Step 3: Commit**

```
refactor: remove unused SwiftAgent dependency
```

---

### Task 2: Extend LLMTypes for tool calling messages

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/Providers/LLMTypes.swift`

**Step 1: Add tool call/result properties to LLMMessage**

ChatEngine's tool-calling loop needs to pass assistant messages with tool calls and tool result messages. Each provider serializes these differently, so we represent them generically.

Add these properties and factory methods to `LLMMessage`:

```swift
struct LLMMessage: Sendable {
    let role: String
    let content: LLMMessageContent
    let toolCalls: [LLMToolCall]?
    let toolCallId: String?

    // Existing factory methods keep working (toolCalls: nil, toolCallId: nil)
    static func system(_ text: String) -> LLMMessage {
        LLMMessage(role: "system", content: .text(text), toolCalls: nil, toolCallId: nil)
    }

    static func user(_ text: String) -> LLMMessage {
        LLMMessage(role: "user", content: .text(text), toolCalls: nil, toolCallId: nil)
    }

    static func userWithImage(text: String, imageBase64: String, mimeType: String = "image/png") -> LLMMessage {
        LLMMessage(role: "user", content: .parts([
            LLMContentPart(type: "text", text: text, imageUrl: nil),
            LLMContentPart(type: "image_url", text: nil, imageUrl: .init(url: "data:\(mimeType);base64,\(imageBase64)"))
        ]), toolCalls: nil, toolCallId: nil)
    }

    static func assistant(_ text: String) -> LLMMessage {
        LLMMessage(role: "assistant", content: .text(text), toolCalls: nil, toolCallId: nil)
    }

    /// Assistant message that includes tool calls (may also have text content)
    static func assistantWithToolCalls(_ text: String?, toolCalls: [LLMToolCall]) -> LLMMessage {
        LLMMessage(
            role: "assistant",
            content: .text(text ?? ""),
            toolCalls: toolCalls,
            toolCallId: nil
        )
    }

    /// Tool result message (response to a tool call)
    static func toolResult(callId: String, content: String) -> LLMMessage {
        LLMMessage(
            role: "tool",
            content: .text(content),
            toolCalls: nil,
            toolCallId: callId
        )
    }
}
```

Remove `Codable` conformance from `LLMMessage` since it's not used for persistence and adding `toolCalls`/`toolCallId` would complicate it. If `Codable` is needed elsewhere, check first.

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | head -30`
Expected: Build errors from callers using the old init (no `toolCalls`/`toolCallId` params). These will be fixed by updating callers to use factory methods (which they already do — `LLMMessage.user(...)`, `.system(...)`, etc.).

**Step 3: Commit**

```
feat: extend LLMMessage with tool call and tool result support
```

---

### Task 3: Define LLMSession protocol

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Providers/LLMSession.swift`

**Step 1: Write protocol**

```swift
import Foundation

/// Unified protocol for all LLM provider sessions.
///
/// Conforming types: `OpenAICompatibleSession`, `AnthropicSession`, `GoogleSession`.
/// All methods accept `LLMMessage` arrays and return provider-agnostic types.
protocol LLMSession: Actor, Sendable {

    /// Non-streaming completion. Returns the full response text.
    func complete(
        messages: [LLMMessage],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String

    /// Streaming completion with optional tool definitions.
    /// Returns an async stream of `LLMStreamEvent` (text deltas, tool calls, done, errors).
    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition],
        temperature: Double,
        maxTokens: Int?
    ) -> AsyncStream<LLMStreamEvent>
}

/// Default parameter values via extension.
extension LLMSession {
    func complete(
        messages: [LLMMessage],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        try await complete(messages: messages, temperature: temperature, maxTokens: maxTokens)
    }

    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<LLMStreamEvent> {
        streamComplete(messages: messages, tools: tools, temperature: temperature, maxTokens: maxTokens)
    }
}
```

**Step 2: Commit**

```
feat: add LLMSession protocol for unified provider interface
```

---

### Task 4: Write AnthropicSession adapter

**Files:**
- Create: `LedgeIt/LedgeIt/Services/Providers/AnthropicSession.swift`

**Step 1: Implement AnthropicSession**

Follows the same actor pattern as `OpenAICompatibleSession` and `GoogleSession`. Targets Anthropic's `/v1/messages` API with `x-api-key` header.

Key differences from OpenAI:
- Auth: `x-api-key` header (not `Authorization: Bearer`)
- Required header: `anthropic-version: 2023-06-01`
- Request: `messages` array + `system` as top-level field (not in messages)
- Response: `content[0].text` (not `choices[0].message.content`)
- Streaming: uses `event: content_block_delta` + `data:` lines
- Tool calls: `content` blocks with `type: "tool_use"` (not `tool_calls` in delta)
- Tool results: user message with `type: "tool_result"` content block (not `role: "tool"`)

```swift
import Foundation

/// Adapter for the Anthropic Messages API (Claude models).
actor AnthropicSession: LLMSession {

    typealias Message = LLMMessage
    typealias ToolDefinition = LLMToolDefinition
    typealias ToolCall = LLMToolCall
    typealias StreamEvent = LLMStreamEvent
    typealias ProviderError = LLMProviderError

    private static let baseURL = "https://api.anthropic.com/v1/messages"

    let apiKey: String
    let model: String
    let instructions: String
    let session: URLSession

    init(apiKey: String, model: String, instructions: String = "") {
        self.apiKey = apiKey
        self.model = model
        self.instructions = instructions
        self.session = URLSession.shared
    }

    // MARK: - Non-Streaming

    func complete(
        messages: [Message],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard let url = URL(string: Self.baseURL) else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 180

        let body = buildRequestBody(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens ?? 4096,
            stream: false
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse
        }
        if httpResponse.statusCode == 429 {
            throw ProviderError.rateLimited
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.requestFailed(httpResponse.statusCode)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            print("[AnthropicSession] Failed to parse API response as JSON")
            throw ProviderError.invalidResponse
        }

        guard let dict = json as? [String: Any],
              let content = dict["content"] as? [[String: Any]],
              let first = content.first(where: { $0["type"] as? String == "text" }),
              let text = first["text"] as? String else {
            if let dict = json as? [String: Any],
               let errorObj = dict["error"] as? [String: Any] {
                let msg = errorObj["message"] as? String ?? "Unknown API error"
                print("[AnthropicSession] API error: \(msg)")
                throw ProviderError.requestFailed(-1)
            }
            print("[AnthropicSession] Unexpected response structure")
            throw ProviderError.invalidResponse
        }

        return text
    }

    // MARK: - Streaming

    func streamComplete(
        messages: [Message],
        tools: [ToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<StreamEvent> {
        guard let url = URL(string: Self.baseURL) else {
            return AsyncStream { $0.yield(.error("Invalid URL")); $0.finish() }
        }

        let body = buildRequestBody(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens ?? 4096,
            stream: true
        )

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return AsyncStream { $0.yield(.error("Failed to serialize request")); $0.finish() }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120
        request.httpBody = httpBody

        let urlSession = self.session
        let (stream, continuation) = AsyncStream.makeStream(of: StreamEvent.self)

        Task.detached {
            do {
                let (bytes, urlResponse) = try await urlSession.bytes(for: request)

                guard let httpResponse = urlResponse as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let code = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
                    var errorBody = ""
                    for try await line in bytes.lines {
                        errorBody += line
                        if errorBody.count > 2000 { break }
                    }
                    continuation.yield(.error("HTTP \(code): \(errorBody)"))
                    continuation.finish()
                    return
                }

                // Anthropic streaming format:
                // event: message_start / content_block_start / content_block_delta /
                //        content_block_stop / message_delta / message_stop
                // data: { ... }

                var currentToolId = ""
                var currentToolName = ""
                var currentToolArgs = ""
                var pendingToolCalls: [ToolCall] = []

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }

                    // Check for error
                    if type == "error" {
                        if let error = json["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            continuation.yield(.error("Provider error: \(message)"))
                            continuation.finish()
                            return
                        }
                    }

                    switch type {
                    case "content_block_start":
                        if let contentBlock = json["content_block"] as? [String: Any],
                           contentBlock["type"] as? String == "tool_use" {
                            currentToolId = contentBlock["id"] as? String ?? ""
                            currentToolName = contentBlock["name"] as? String ?? ""
                            currentToolArgs = ""
                        }

                    case "content_block_delta":
                        if let delta = json["delta"] as? [String: Any] {
                            let deltaType = delta["type"] as? String ?? ""

                            if deltaType == "text_delta",
                               let text = delta["text"] as? String {
                                continuation.yield(.text(text))
                            } else if deltaType == "input_json_delta",
                                      let partial = delta["partial_json"] as? String {
                                currentToolArgs += partial
                            }
                        }

                    case "content_block_stop":
                        if !currentToolName.isEmpty {
                            pendingToolCalls.append(ToolCall(
                                id: currentToolId,
                                name: currentToolName,
                                arguments: currentToolArgs
                            ))
                            currentToolId = ""
                            currentToolName = ""
                            currentToolArgs = ""
                        }

                    case "message_stop":
                        for tc in pendingToolCalls {
                            continuation.yield(.toolCall(tc))
                        }
                        continuation.yield(.done)
                        continuation.finish()
                        return

                    default:
                        break
                    }
                }

                continuation.yield(.done)
                continuation.finish()
            } catch {
                continuation.yield(.error(error.localizedDescription))
                continuation.finish()
            }
        }

        return stream
    }

    // MARK: - Request Body Builder

    private func buildRequestBody(
        messages: [Message],
        tools: [ToolDefinition] = [],
        temperature: Double,
        maxTokens: Int,
        stream: Bool
    ) -> [String: Any] {
        let (anthropicMessages, systemText) = convertMessages(messages)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": anthropicMessages,
            "temperature": temperature,
            "stream": stream,
        ]

        if let systemText, !systemText.isEmpty {
            body["system"] = systemText
        }

        if !tools.isEmpty {
            body["tools"] = tools.map { tool -> [String: Any] in
                var toolDict: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                ]
                // Anthropic expects input_schema (JSON Schema), same as OpenAI parameters
                toolDict["input_schema"] = tool.parameters
                return toolDict
            }
        }

        return body
    }

    /// Convert LLMMessage array to Anthropic messages format.
    ///
    /// Differences from OpenAI:
    /// - System messages are extracted to top-level `system` field
    /// - Tool results are sent as user messages with `tool_result` content blocks
    /// - Assistant tool calls are sent as `tool_use` content blocks
    private func convertMessages(
        _ messages: [Message]
    ) -> (messages: [[String: Any]], system: String?) {
        var result: [[String: Any]] = []
        var systemParts: [String] = []

        // Prepend global instructions
        if !instructions.isEmpty {
            systemParts.append(instructions)
        }

        for msg in messages {
            switch msg.role {
            case "system":
                if case .text(let text) = msg.content {
                    systemParts.append(text)
                }

            case "assistant":
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    // Assistant message with tool calls
                    var content: [[String: Any]] = []
                    if case .text(let text) = msg.content, !text.isEmpty {
                        content.append(["type": "text", "text": text])
                    }
                    for tc in toolCalls {
                        var toolUse: [String: Any] = [
                            "type": "tool_use",
                            "id": tc.id,
                            "name": tc.name,
                        ]
                        // Parse arguments JSON string to dict
                        if let argsData = tc.arguments.data(using: .utf8),
                           let argsDict = try? JSONSerialization.jsonObject(with: argsData) {
                            toolUse["input"] = argsDict
                        } else {
                            toolUse["input"] = [String: Any]()
                        }
                        content.append(toolUse)
                    }
                    result.append(["role": "assistant", "content": content])
                } else {
                    // Regular assistant message
                    let text = Self.extractText(from: msg) ?? ""
                    result.append(["role": "assistant", "content": text])
                }

            case "tool":
                // Tool results in Anthropic are user messages with tool_result content
                let text = Self.extractText(from: msg) ?? ""
                let toolResultContent: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": text,
                ]
                // Merge with previous user message if it's also a tool_result,
                // or create new user message
                if let last = result.last,
                   last["role"] as? String == "user",
                   let existingContent = last["content"] as? [[String: Any]] {
                    var merged = existingContent
                    merged.append(toolResultContent)
                    result[result.count - 1] = ["role": "user", "content": merged]
                } else {
                    result.append(["role": "user", "content": [toolResultContent]])
                }

            case "user":
                let text = Self.extractText(from: msg) ?? ""
                result.append(["role": "user", "content": text])

            default:
                break
            }
        }

        let systemText = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (result, systemText)
    }

    private static func extractText(from message: Message) -> String? {
        switch message.content {
        case .text(let string): return string
        case .parts(let parts): return parts.compactMap(\.text).joined(separator: "\n")
        }
    }
}
```

**Step 2: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Compiles (AnthropicSession is not yet referenced)

**Step 3: Commit**

```
feat: add AnthropicSession adapter for direct Anthropic API access
```

---

### Task 5: Fix GoogleSession streaming API key

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift:131-145`

**Step 1: Move API key from URL query to header in streamComplete**

The `complete()` method was already fixed. Fix the streaming method too:

```swift
// Change line 131 from:
let endpoint = "\(Self.baseURL)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
// To:
let endpoint = "\(Self.baseURL)/models/\(model):streamGenerateContent?alt=sse"

// And after line 144 (request.setValue("application/json"...)), add:
request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
```

Also add SSE error payload checking (matching C4 fix done for OpenAICompatibleSession):

After the existing guard on line 177, add error checking:

```swift
guard let data = payload.data(using: .utf8) else { continue }

guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    continue
}

// Check for error response
if let error = json["error"] as? [String: Any] {
    let message = error["message"] as? String ?? "Unknown API error"
    continuation.yield(.error("Provider error: \(message)"))
    continuation.finish()
    return
}

guard let candidates = json["candidates"] as? [[String: Any]],
      let content = candidates.first?["content"] as? [String: Any],
      let parts = content["parts"] as? [[String: Any]] else {
    continue
}
```

**Step 2: Commit**

```
fix: move Google API key to header in streaming, add SSE error checking
```

---

### Task 6: Conform all sessions to LLMSession protocol

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/Providers/OpenAICompatibleSession.swift`
- Modify: `LedgeIt/LedgeIt/Services/Providers/GoogleSession.swift`
- (AnthropicSession already declares conformance in Task 4)

**Step 1: Add protocol conformance to OpenAICompatibleSession**

```swift
// Change line 18 from:
actor OpenAICompatibleSession {
// To:
actor OpenAICompatibleSession: LLMSession {
```

Update `serializeMessages()` to handle tool call/result messages:

```swift
private static func serializeMessages(_ messages: [Message]) -> [[String: Any]] {
    messages.map { msg -> [String: Any] in
        var dict: [String: Any] = ["role": msg.role]

        // Content
        switch msg.content {
        case .text(let str):
            dict["content"] = str
        case .parts(let parts):
            dict["content"] = parts.map { part -> [String: Any] in
                var d: [String: Any] = ["type": part.type]
                if let text = part.text { d["text"] = text }
                if let imageUrl = part.imageUrl { d["image_url"] = ["url": imageUrl.url] }
                return d
            }
        }

        // Tool calls (assistant messages)
        if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": ["name": tc.name, "arguments": tc.arguments]
                ] as [String: Any]
            }
        }

        // Tool call ID (tool result messages)
        if let toolCallId = msg.toolCallId {
            dict["tool_call_id"] = toolCallId
        }

        return dict
    }
}
```

**Step 2: Add protocol conformance to GoogleSession**

```swift
// Change line 17 from:
actor GoogleSession {
// To:
actor GoogleSession: LLMSession {
```

GoogleSession's `convertMessages()` also needs to handle tool call/result messages for future use. For now, it can ignore them (Google chat with tools is not yet supported). Add a comment noting this.

**Step 3: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`

**Step 4: Commit**

```
feat: conform all sessions to LLMSession protocol
```

---

### Task 7: Update SessionFactory to return protocol type

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/Providers/SessionFactory.swift`

**Step 1: Change return type and restore all three provider cases**

```swift
import Foundation

enum SessionFactory {

    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingAPIKey(provider: String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint configuration not found: \(id)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            }
        }
    }

    /// Create a session for completions based on the model assignment.
    ///
    /// Returns the appropriate session type for the configured provider:
    /// - `.openAICompatible` → `OpenAICompatibleSession` (OpenAI, OpenRouter, Ollama, Groq)
    /// - `.anthropic` → `AnthropicSession` (direct Anthropic API)
    /// - `.google` → `GoogleSession` (Google Gemini API)
    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        instructions: String = ""
    ) throws -> any LLMSession {
        switch assignment.provider {
        case .openAICompatible:
            guard let endpointId = assignment.endpointId,
                  let endpoint = config.endpoints.first(where: { $0.id == endpointId }) else {
                throw SessionError.endpointNotFound(assignment.endpointId ?? UUID())
            }
            let apiKey = endpoint.requiresAPIKey
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
            return AnthropicSession(
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )

        case .google:
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            return GoogleSession(
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )
        }
    }
}
```

**Step 2: Update all callers**

Callers currently expect `OpenAICompatibleSession` return type. They call `session.complete()` which is on the protocol, so they should work with `any LLMSession`. Check each caller:

- `LLMProcessor` — calls `session.complete(messages:temperature:maxTokens:)` ✅ protocol method
- `FinancialAdvisor` — calls `session.complete(messages:)` ✅
- `GoalPlanner` — calls `session.complete(messages:)` ✅
- `PromptOptimizer` — calls `session.complete(messages:)` ✅
- `ReportGenerator` — calls `session.complete(messages:)` ✅
- `GoalGenerationService` — calls `session.complete(messages:)` ✅
- `PDFExtractor` — calls `session.complete(messages:)` ✅
- `ChatEngine` — calls `OpenAICompatibleSession.performStreamComplete()` ❌ needs Task 8 fix

**Step 3: Commit**

```
refactor: SessionFactory returns any LLMSession, supports all three providers
```

---

### Task 8: Refactor ChatEngine to use LLMSession protocol

**Files:**
- Modify: `LedgeIt/LedgeIt/Services/ChatEngine.swift`

This is the largest change. ChatEngine currently:
1. Creates session via SessionFactory
2. Extracts internal properties (`completionsURL`, `apiKey`, etc.)
3. Calls `OpenAICompatibleSession.performStreamComplete()` directly with raw `[[String: Any]]`
4. Manually builds tool call/result messages as dicts

After refactor:
1. Creates session via SessionFactory → `any LLMSession`
2. Calls `session.streamComplete(messages:tools:)` through protocol
3. Uses `LLMMessage` for all messages including tool calls/results

**Step 1: Refactor processMessage()**

Replace the raw message building + static method call with protocol-based approach:

```swift
private func processMessage(
    _ message: String,
    messageId: UUID,
    continuation: AsyncStream<ChatStreamEvent>.Continuation
) async {
    do {
        chatLogger.debug("User: \(message)")
        conversationHistory.append(.user(message))

        let systemPrompt = try await buildSystemPrompt()
        let config = AIProviderConfigStore.load()
        let session = try SessionFactory.makeSession(
            assignment: config.chat,
            config: config
        )

        continuation.yield(.messageStarted(messageId))

        // Build messages: system + conversation history
        var messages: [LLMMessage] = [.system(systemPrompt)]
        messages.append(contentsOf: conversationHistory)

        var fullResponse = ""

        // Tool-calling loop
        for _ in 0..<maxToolIterations {
            var iterationText = ""
            var toolCall: LLMToolCall?

            let stream = await session.streamComplete(
                messages: messages,
                tools: toolDefinitions
            )

            for await event in stream {
                switch event {
                case .text(let text):
                    iterationText += text
                    continuation.yield(.textDelta(text))
                case .toolCall(let tc):
                    toolCall = tc
                case .done:
                    break
                case .error(let errorMsg):
                    continuation.yield(.error(errorMsg))
                    continuation.finish()
                    return
                }
            }

            fullResponse += iterationText

            guard let tc = toolCall else {
                chatLogger.debug("No tool call in this iteration, done.")
                break
            }
            chatLogger.debug("Tool call: \(tc.name)")

            continuation.yield(.toolCallStarted(tc.name))

            let toolResult: String
            do {
                toolResult = try await executeTool(name: tc.name, arguments: tc.arguments)
            } catch {
                toolResult = "Error executing tool \(tc.name): \(error.localizedDescription)"
            }

            // Append assistant message with tool call + tool result using LLMMessage
            messages.append(.assistantWithToolCalls(
                iterationText.isEmpty ? nil : iterationText,
                toolCalls: [tc]
            ))
            messages.append(.toolResult(callId: tc.id, content: toolResult))
        }

        if !fullResponse.isEmpty {
            conversationHistory.append(.assistant(fullResponse))
        }

        continuation.yield(.messageComplete)
        continuation.finish()
    } catch {
        continuation.yield(.error(error.localizedDescription))
        continuation.finish()
    }
}
```

**Step 2: Remove static performStreamComplete usage**

The old code at lines 89-107 that extracted session properties and called the static method is now replaced by the protocol call above. The static `performStreamComplete` method in `OpenAICompatibleSession` can remain (it's used by `streamComplete()` internally) but is no longer called externally.

**Step 3: Verify build**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`

**Step 4: Commit**

```
refactor: ChatEngine uses LLMSession protocol instead of hardcoded OpenAICompatibleSession
```

---

### Task 9: Fix AIProviderSettingsView issues

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Settings/AIProviderSettingsView.swift`
- Modify: `LedgeIt/LedgeIt/Views/SettingsView.swift`

**Step 1: Fix I6 — Add delete confirmation dialog, prevent deleting last endpoint**

Add `@State private var endpointToDelete: OpenAICompatibleEndpoint?` state var.

Replace the Delete button action:
```swift
Button("Delete", role: .destructive) {
    endpointToDelete = endpoint
}
```

Add confirmation dialog to `providerManagementSection`:
```swift
.confirmationDialog(
    "Delete endpoint?",
    isPresented: Binding(
        get: { endpointToDelete != nil },
        set: { if !$0 { endpointToDelete = nil } }
    ),
    presenting: endpointToDelete
) { endpoint in
    Button("Delete \(endpoint.name)", role: .destructive) {
        deleteEndpoint(endpoint)
        endpointToDelete = nil
    }
} message: { endpoint in
    Text("This will remove \"\(endpoint.name)\" and reset any model assignments using it.")
}
```

In `deleteEndpoint()`, add guard:
```swift
private func deleteEndpoint(_ endpoint: OpenAICompatibleEndpoint) {
    guard config.endpoints.count > 1 else { return }
    // ... existing logic
}
```

Disable the Delete button when only one endpoint remains:
```swift
Button("Delete", role: .destructive) {
    endpointToDelete = endpoint
}
.disabled(config.endpoints.count <= 1)
```

**Step 2: Fix I7 — Debounce model text field saves**

Replace `saveConfig()` in the model TextField binding with `.onSubmit`:

```swift
TextField("model-id", text: Binding(
    get: { config[keyPath: keyPath].model },
    set: { newModel in
        config[keyPath: keyPath].model = newModel
    }
))
.textFieldStyle(.roundedBorder)
.font(.callout)
.onSubmit { saveConfig() }
```

**Step 3: Fix S4 — Simplify boolean expression**

```swift
// Change line 156 from:
let hasKey = endpointAPIKeys[endpoint.id] != nil && !(endpointAPIKeys[endpoint.id]?.isEmpty ?? true)
// To:
let hasKey = endpointAPIKeys[endpoint.id].map { !$0.isEmpty } ?? false
```

**Step 4: Fix I3/S5 — Deduplicate SettingsSection**

In `SettingsView.swift`, change `SettingsSection` from `private` to `internal`:

```swift
// Change line 459 from:
private struct SettingsSection<Content: View>: View {
// To:
struct SettingsSection<Content: View>: View {
```

In `AIProviderSettingsView.swift`, remove the duplicate `AISettingsSection` struct (lines 442-462) and replace all `AISettingsSection` usage with `SettingsSection`.

**Step 5: Commit**

```
fix: add endpoint delete confirmation, debounce model saves, deduplicate SettingsSection
```

---

### Task 10: Update CLAUDE.md and build verification

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md**

Update the AI Provider Architecture section to reflect:
- SwiftAgent dependency removed
- AnthropicSession is our own adapter (not SwiftAgent built-in)
- All three providers are functional
- LLMSession protocol unifies sessions

**Step 2: Full build verification**

Run: `cd LedgeIt && swift build 2>&1`
Expected: Clean build with no errors

**Step 3: Commit all**

```
docs: update CLAUDE.md for finalized multi-provider architecture
```

---

## Summary of Changes by File

| File | Tasks | Changes |
|------|-------|---------|
| `Package.swift` | 1 | Remove SwiftAgent, keep swift-tools-version 6.2, macOS v15 |
| `LLMTypes.swift` | 2 | Add `toolCalls`, `toolCallId` to `LLMMessage`, add factory methods |
| `LLMSession.swift` | 3 | New file: unified protocol |
| `AnthropicSession.swift` | 4 | New file: Anthropic `/v1/messages` adapter |
| `GoogleSession.swift` | 5, 6 | Fix streaming API key, SSE error check, conform to protocol |
| `OpenAICompatibleSession.swift` | 6 | Conform to protocol, handle tool messages in serialization |
| `SessionFactory.swift` | 7 | Return `any LLMSession`, restore all three provider cases |
| `ChatEngine.swift` | 8 | Use protocol + LLMMessage instead of raw dicts |
| `AIProviderSettingsView.swift` | 9 | Delete confirmation, debounce, simplify, deduplicate |
| `SettingsView.swift` | 9 | Make `SettingsSection` internal |
| `CLAUDE.md` | 10 | Update architecture docs |
