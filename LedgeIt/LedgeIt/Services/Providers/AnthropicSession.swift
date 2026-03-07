import Foundation

/// Adapter for the Anthropic Messages API (Claude models).
///
/// Translates the shared `LLMMessage` types into the Anthropic request/response
/// format and handles both non-streaming and streaming completions.
///
/// Usage:
/// ```swift
/// let session = AnthropicSession(
///     apiKey: "sk-ant-...",
///     model: "claude-sonnet-4-6-20250514",
///     instructions: "You are a helpful assistant."
/// )
/// let reply = try await session.complete(messages: [.user("Hello")])
/// ```
actor AnthropicSession: LLMSession {

    // MARK: - Constants

    private static let baseURL = "https://api.anthropic.com/v1/messages"

    // MARK: - Properties

    let apiKey: String
    let model: String
    let instructions: String
    let session: URLSession

    // MARK: - Init

    init(apiKey: String, model: String, instructions: String = "") {
        self.apiKey = apiKey
        self.model = model
        self.instructions = instructions
        self.session = URLSession.shared
    }

    // MARK: - Non-Streaming API

    func complete(
        messages: [LLMMessage],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        guard let url = URL(string: Self.baseURL) else {
            throw LLMProviderError.invalidResponse
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
              let content = dict["content"] as? [[String: Any]],
              let first = content.first(where: { $0["type"] as? String == "text" }),
              let text = first["text"] as? String else {
            if let dict = json as? [String: Any],
               let errorObj = dict["error"] as? [String: Any] {
                let msg = errorObj["message"] as? String ?? "Unknown API error"
                throw LLMProviderError.apiError(msg)
            }
            throw LLMProviderError.invalidResponse
        }

        return text
    }

    // MARK: - Streaming API

    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<LLMStreamEvent> {
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
        let (stream, continuation) = AsyncStream.makeStream(of: LLMStreamEvent.self)

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

                var currentToolId = ""
                var currentToolName = ""
                var currentToolArgs = ""
                var pendingToolCalls: [LLMToolCall] = []

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else {
                        continue
                    }

                    // Check for error event
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
                            pendingToolCalls.append(LLMToolCall(
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
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
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
        _ messages: [LLMMessage]
    ) -> (messages: [[String: Any]], system: String?) {
        var result: [[String: Any]] = []
        var systemParts: [String] = []

        // Prepend global instructions
        if !instructions.isEmpty {
            systemParts.append(instructions)
        }

        for msg in messages {
            switch msg.role {
            case .system:
                if case .text(let text) = msg.content {
                    systemParts.append(text)
                }

            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
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
                    let text = msg.text ?? ""
                    result.append(["role": "assistant", "content": text])
                }

            case .tool:
                let text = msg.text ?? ""
                let toolResultContent: [String: Any] = [
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": text,
                ]
                if let last = result.last,
                   last["role"] as? String == "user",
                   let existingContent = last["content"] as? [[String: Any]] {
                    var merged = existingContent
                    merged.append(toolResultContent)
                    result[result.count - 1] = ["role": "user", "content": merged]
                } else {
                    result.append(["role": "user", "content": [toolResultContent]])
                }

            case .user:
                let text = msg.text ?? ""
                result.append(["role": "user", "content": text])
            }
        }

        let systemText = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (result, systemText)
    }

}
