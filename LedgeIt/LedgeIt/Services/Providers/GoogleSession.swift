import Foundation

/// An adapter for the Google Gemini (generative AI) API.
///
/// Translates the shared `LLMMessage` types into the Gemini request/response
/// format and handles both non-streaming and streaming completions.
///
/// Usage:
/// ```swift
/// let session = GoogleSession(
///     apiKey: "AIza...",
///     model: "gemini-2.0-flash",
///     instructions: "You are a helpful assistant."
/// )
/// let reply = try await session.complete(messages: [.user("Hello")])
/// ```
actor GoogleSession: LLMSession {

    // MARK: - Type Aliases (backed by top-level LLM types in LLMTypes.swift)

    typealias Message = LLMMessage
    typealias ToolDefinition = LLMToolDefinition
    typealias ToolCall = LLMToolCall
    typealias StreamEvent = LLMStreamEvent
    typealias ProviderError = LLMProviderError

    // MARK: - Constants

    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    // MARK: - Properties

    let apiKey: String
    let model: String
    let instructions: String
    let session: URLSession

    // MARK: - Init

    /// Creates a new session targeting the Google Gemini API.
    ///
    /// - Parameters:
    ///   - apiKey: The Gemini API key (passed as a query parameter).
    ///   - model: The model identifier (e.g. `gemini-2.0-flash`).
    ///   - instructions: Optional system instructions prepended to every request.
    init(
        apiKey: String,
        model: String,
        instructions: String = ""
    ) {
        self.apiKey = apiKey
        self.model = model
        self.instructions = instructions
        self.session = URLSession.shared
    }

    // MARK: - Non-Streaming API

    /// Sends a generate-content request and returns the full response text.
    func complete(
        messages: [Message],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        let endpoint = "\(Self.baseURL)/models/\(model):generateContent"

        guard let url = URL(string: endpoint) else {
            throw ProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 180

        let body = buildRequestBody(messages: messages, temperature: temperature, maxTokens: maxTokens)
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
            print("[GoogleSession] Failed to parse API response as JSON")
            throw ProviderError.invalidResponse
        }

        guard let dict = json as? [String: Any],
              let candidates = dict["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            if let dict = json as? [String: Any], let errorObj = dict["error"] as? [String: Any] {
                let msg = errorObj["message"] as? String ?? "Unknown API error"
                print("[GoogleSession] API error: \(msg)")
                throw ProviderError.requestFailed(-1)
            }
            print("[GoogleSession] Unexpected response structure")
            throw ProviderError.invalidResponse
        }

        return text
    }

    // MARK: - Streaming API

    /// Sends a streaming generate-content request and returns an async stream of events.
    func streamComplete(
        messages: [Message],
        tools: [ToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<StreamEvent> {
        // TODO: Add tool calling support for Gemini native function calling format
        let body = buildRequestBody(messages: messages, temperature: temperature, maxTokens: maxTokens)
        let endpoint = "\(Self.baseURL)/models/\(model):streamGenerateContent?alt=sse"
        let urlSession = self.session

        guard let url = URL(string: endpoint) else {
            return AsyncStream { $0.yield(.error("Invalid URL")); $0.finish() }
        }

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            return AsyncStream { $0.yield(.error("Failed to serialize request")); $0.finish() }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 120
        request.httpBody = httpBody

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

                for try await line in bytes.lines {
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))

                    // Gemini SSE does not use a [DONE] sentinel; the stream simply ends.
                    // However, handle it defensively in case the API adds one.
                    if payload == "[DONE]" {
                        break
                    }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
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

                    for part in parts {
                        if let text = part["text"] as? String {
                            continuation.yield(.text(text))
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

    /// Builds the Gemini request body from OpenAI-style messages.
    private func buildRequestBody(
        messages: [Message],
        temperature: Double,
        maxTokens: Int?
    ) -> [String: Any] {
        let (contents, systemInstruction) = convertMessages(messages)

        var body: [String: Any] = [
            "contents": contents
        ]

        if let systemInstruction {
            body["systemInstruction"] = systemInstruction
        }

        var generationConfig: [String: Any] = [
            "temperature": temperature
        ]
        if let maxTokens {
            generationConfig["maxOutputTokens"] = maxTokens
        }
        body["generationConfig"] = generationConfig

        return body
    }

    /// Converts OpenAI-style messages to the Gemini contents/systemInstruction format.
    ///
    /// - System messages are extracted into `systemInstruction`.
    /// - User and assistant messages are mapped to `"user"` and `"model"` roles respectively.
    private func convertMessages(
        _ messages: [Message]
    ) -> (contents: [[String: Any]], systemInstruction: [String: Any]?) {
        var contents: [[String: Any]] = []
        var systemParts: [String] = []

        for message in messages {
            let text = Self.extractText(from: message)

            switch message.role {
            case "system":
                if let text {
                    systemParts.append(text)
                }
            case "user":
                contents.append(["role": "user", "parts": [["text": text ?? ""]]])
            case "assistant":
                contents.append(["role": "model", "parts": [["text": text ?? ""]]])
            default:
                break
            }
        }

        // Prepend global instructions if set
        if !instructions.isEmpty {
            systemParts.insert(instructions, at: 0)
        }

        let systemInstruction: [String: Any]?
        if !systemParts.isEmpty {
            let combined = systemParts.joined(separator: "\n\n")
            systemInstruction = ["parts": [["text": combined]]]
        } else {
            systemInstruction = nil
        }

        return (contents, systemInstruction)
    }

    /// Extracts the plain-text content from a message, ignoring image parts.
    private static func extractText(from message: Message) -> String? {
        switch message.content {
        case .text(let string):
            return string
        case .parts(let parts):
            return parts.compactMap(\.text).joined(separator: "\n")
        }
    }
}
