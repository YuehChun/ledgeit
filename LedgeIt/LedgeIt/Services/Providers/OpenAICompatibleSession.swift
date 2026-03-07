import Foundation

/// A generalized adapter for any OpenAI-compatible API endpoint.
///
/// Supports providers such as OpenAI, OpenRouter, Ollama, Groq, and any other
/// service that implements the OpenAI chat completions API contract.
///
/// Usage:
/// ```swift
/// let session = OpenAICompatibleSession(
///     baseURL: "https://api.openai.com/v1",
///     apiKey: "sk-...",
///     model: "gpt-4o",
///     instructions: "You are a helpful assistant."
/// )
/// let reply = try await session.complete(messages: [.user("Hello")])
/// ```
actor OpenAICompatibleSession: LLMSession {

    // MARK: - Properties

    let baseURL: String
    let apiKey: String?
    let model: String
    let instructions: String
    let session: URLSession

    /// The full endpoint URL for chat completions, derived from `baseURL`.
    var completionsURL: String {
        baseURL.hasSuffix("/")
            ? baseURL + "chat/completions"
            : baseURL + "/chat/completions"
    }

    // MARK: - Init

    /// Creates a new session targeting an OpenAI-compatible API.
    ///
    /// - Parameters:
    ///   - baseURL: The provider's base URL (e.g. `https://api.openai.com/v1`).
    ///   - apiKey: Bearer token for authentication. Pass `nil` for providers
    ///             that do not require one (e.g. local Ollama).
    ///   - model: The model identifier to use for completions.
    ///   - instructions: Optional system instructions prepended to every request.
    init(
        baseURL: String,
        apiKey: String?,
        model: String,
        instructions: String = ""
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.instructions = instructions
        self.session = URLSession.shared
    }

    // MARK: - Non-Streaming API

    /// Sends a chat completion request and returns the full response text.
    func complete(
        messages: [LLMMessage],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard let url = URL(string: completionsURL) else {
            throw LLMProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 180

        // Prepend system instructions if provided
        var allMessages = messages
        if !instructions.isEmpty {
            allMessages.insert(.system(instructions), at: 0)
        }

        var body: [String: Any] = [
            "model": model,
            "messages": Self.serializeMessages(allMessages),
            "temperature": temperature
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMProviderError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw LLMProviderError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMProviderError.requestFailed(httpResponse.statusCode)
        }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMProviderError.invalidResponse
        }

        guard let dict = json as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            if let dict = json as? [String: Any], let errorObj = dict["error"] as? [String: Any] {
                let msg = errorObj["message"] as? String ?? "Unknown API error"
                throw LLMProviderError.apiError(msg)
            }
            throw LLMProviderError.invalidResponse
        }

        return content
    }

    // MARK: - Streaming API

    /// Sends a streaming chat completion request and returns an async stream of events.
    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<LLMStreamEvent> {
        // Prepend system instructions if provided (consistent with complete())
        var allMessages = messages
        if !instructions.isEmpty {
            allMessages.insert(.system(instructions), at: 0)
        }
        let rawMessages = Self.serializeMessages(allMessages)
        return Self.performStreamComplete(
            completionsURL: completionsURL,
            model: model,
            rawMessages: rawMessages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            apiKey: self.apiKey,
            session: self.session
        )
    }

    // MARK: - Static Stream Implementation

    nonisolated static func performStreamComplete(
        completionsURL: String,
        model: String,
        rawMessages: [[String: Any]],
        tools: [LLMToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil,
        apiKey: String?,
        session: URLSession
    ) -> AsyncStream<LLMStreamEvent> {
        guard let url = URL(string: completionsURL) else {
            return AsyncStream { $0.yield(.error("Invalid URL")); $0.finish() }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": rawMessages,
            "temperature": temperature,
            "stream": true
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        if !tools.isEmpty {
            body["tools"] = tools.map { $0.toDict() }
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return AsyncStream { $0.yield(.error("Failed to serialize request")); $0.finish() }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120
        request.httpBody = httpBody

        let (stream, continuation) = AsyncStream.makeStream(of: LLMStreamEvent.self)

        Task.detached {
            do {
                let (bytes, urlResponse) = try await session.bytes(for: request)

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

                var toolCalls: [Int: (id: String, name: String, arguments: String)] = [:]

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    if payload == "[DONE]" {
                        for (_, tc) in toolCalls.sorted(by: { $0.key < $1.key }) {
                            if !tc.name.isEmpty {
                                continuation.yield(.toolCall(LLMToolCall(
                                    id: tc.id,
                                    name: tc.name,
                                    arguments: tc.arguments
                                )))
                            }
                        }
                        continuation.yield(.done)
                        continuation.finish()
                        return
                    }

                    guard let data = payload.data(using: .utf8) else { continue }

                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }

                    // Check for error response before assuming normal structure
                    if let error = json["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? "Unknown API error"
                        continuation.yield(.error("Provider error: \(message)"))
                        continuation.finish()
                        return
                    }

                    guard let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else {
                        continue
                    }

                    if let content = delta["content"] as? String {
                        continuation.yield(.text(content))
                    }

                    if let tcs = delta["tool_calls"] as? [[String: Any]] {
                        for tc in tcs {
                            let index = tc["index"] as? Int ?? 0
                            var existing = toolCalls[index] ?? (id: "", name: "", arguments: "")
                            if let id = tc["id"] as? String { existing.id = id }
                            if let fn = tc["function"] as? [String: Any] {
                                if let name = fn["name"] as? String { existing.name = name }
                                if let args = fn["arguments"] as? String { existing.arguments += args }
                            }
                            toolCalls[index] = existing
                        }
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

    // MARK: - Helpers

    /// Converts an array of `LLMMessage` values into raw dictionaries for JSON serialization.
    private static func serializeMessages(_ messages: [LLMMessage]) -> [[String: Any]] {
        messages.map { msg -> [String: Any] in
            let contentValue: Any
            switch msg.content {
            case .text(let str):
                contentValue = str
            case .parts(let parts):
                contentValue = parts.map { part -> [String: Any] in
                    var dict: [String: Any] = ["type": part.type]
                    if let text = part.text { dict["text"] = text }
                    if let imageUrl = part.imageUrl { dict["image_url"] = ["url": imageUrl.url] }
                    return dict
                }
            }
            var dict: [String: Any] = ["role": msg.role.rawValue, "content": contentValue]

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
}
