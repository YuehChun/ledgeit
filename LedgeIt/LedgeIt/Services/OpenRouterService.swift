import Foundation

actor OpenRouterService {

    // MARK: - Types

    struct Message: Codable, Sendable {
        let role: String
        let content: MessageContent

        enum MessageContent: Codable, Sendable {
            case text(String)
            case parts([ContentPart])

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .text(let string):
                    try container.encode(string)
                case .parts(let parts):
                    try container.encode(parts)
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .text(string)
                } else {
                    self = .parts(try container.decode([ContentPart].self))
                }
            }
        }

        struct ContentPart: Codable, Sendable {
            let type: String
            let text: String?
            let imageUrl: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageUrl = "image_url"
            }

            struct ImageURL: Codable, Sendable {
                let url: String
            }
        }

        static func system(_ text: String) -> Message {
            Message(role: "system", content: .text(text))
        }

        static func user(_ text: String) -> Message {
            Message(role: "user", content: .text(text))
        }

        static func userWithImage(text: String, imageBase64: String, mimeType: String = "image/png") -> Message {
            Message(role: "user", content: .parts([
                ContentPart(type: "text", text: text, imageUrl: nil),
                ContentPart(type: "image_url", text: nil, imageUrl: .init(url: "data:\(mimeType);base64,\(imageBase64)"))
            ]))
        }

        static func assistant(_ text: String) -> Message {
            Message(role: "assistant", content: .text(text))
        }
    }

    // MARK: - Tool Calling Types

    struct ToolDefinition: @unchecked Sendable {
        let name: String
        let description: String
        let parameters: [String: Any]

        func toDict() -> [String: Any] {
            [
                "type": "function",
                "function": [
                    "name": name,
                    "description": description,
                    "parameters": parameters
                ] as [String: Any]
            ]
        }
    }

    struct ToolCall: Sendable {
        let id: String
        let name: String
        let arguments: String
    }

    enum StreamEvent: Sendable {
        case text(String)
        case toolCall(ToolCall)
        case done
        case error(String)
    }

    enum OpenRouterError: LocalizedError {
        case missingAPIKey
        case requestFailed(Int)
        case invalidResponse
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenRouter API key not found in Keychain"
            case .requestFailed(let code):
                return "OpenRouter request failed with status \(code)"
            case .invalidResponse:
                return "Invalid response from OpenRouter"
            case .rateLimited:
                return "OpenRouter rate limit exceeded"
            }
        }
    }

    // MARK: - Credits

    struct CreditInfo: Sendable {
        let totalCredits: Double
        let usage: Double
        let remaining: Double
        let isFreeTier: Bool
    }

    func fetchCredits() async throws -> CreditInfo {
        // Try /api/v1/credits first (returns account-level totals)
        if let accountInfo = try? await fetchAccountCredits() {
            return accountInfo
        }
        // Fall back to /api/v1/key (per-key limits)
        return try await fetchKeyCredits()
    }

    private func fetchAccountCredits() async throws -> CreditInfo {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenRouterError.requestFailed(0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw OpenRouterError.invalidResponse
        }

        let total = dataObj["total_credits"] as? Double ?? 0
        let used = dataObj["total_usage"] as? Double ?? 0

        return CreditInfo(
            totalCredits: total,
            usage: used,
            remaining: total - used,
            isFreeTier: total == 0
        )
    }

    private func fetchKeyCredits() async throws -> CreditInfo {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key") else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw OpenRouterError.requestFailed(0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw OpenRouterError.invalidResponse
        }

        let limit = dataObj["limit"] as? Double
        let limitRemaining = dataObj["limit_remaining"] as? Double
        let usage = dataObj["usage"] as? Double ?? 0
        let isFreeTier = dataObj["is_free_tier"] as? Bool ?? true

        let total = limit ?? (usage + (limitRemaining ?? 0))
        let remaining = limitRemaining ?? (total - usage)

        return CreditInfo(
            totalCredits: total,
            usage: usage,
            remaining: remaining,
            isFreeTier: isFreeTier
        )
    }

    // MARK: - Private

    private let apiKey: String
    private let session: URLSession
    private static let baseURL = "https://openrouter.ai/api/v1/chat/completions"

    // MARK: - Init

    init() throws {
        guard let key = KeychainService.load(key: .openRouterAPIKey), !key.isEmpty else {
            throw OpenRouterError.missingAPIKey
        }
        self.apiKey = key
        self.session = URLSession.shared
    }

    // MARK: - API

    func complete(
        model: String,
        messages: [Message],
        temperature: Double = 0.1,
        maxTokens: Int = 2000
    ) async throws -> String {
        guard let url = URL(string: Self.baseURL) else {
            throw OpenRouterError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://ledgeit.app", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LedgeIt", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { msg -> [String: Any] in
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
                return ["role": msg.role, "content": contentValue]
            },
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw OpenRouterError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenRouterError.requestFailed(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenRouterError.invalidResponse
        }

        return content
    }

    // MARK: - Streaming API

    func streamComplete(
        model: String,
        messages: [Message],
        tools: [ToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int = 4000
    ) -> AsyncStream<StreamEvent> {
        let rawMessages = messages.map { msg -> [String: Any] in
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
            return ["role": msg.role, "content": contentValue]
        }
        return streamComplete(model: model, rawMessages: rawMessages, tools: tools, temperature: temperature, maxTokens: maxTokens)
    }

    func streamComplete(
        model: String,
        rawMessages: [[String: Any]],
        tools: [ToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int = 4000
    ) -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task { [apiKey, session] in
                do {
                    guard let url = URL(string: Self.baseURL) else {
                        continuation.yield(.error("Invalid URL"))
                        continuation.finish()
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("https://ledgeit.app", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("LedgeIt", forHTTPHeaderField: "X-Title")
                    request.timeoutInterval = 120

                    var body: [String: Any] = [
                        "model": model,
                        "messages": rawMessages,
                        "temperature": temperature,
                        "max_tokens": maxTokens,
                        "stream": true
                    ]

                    if !tools.isEmpty {
                        body["tools"] = tools.map { $0.toDict() }
                    }

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        continuation.yield(.error("HTTP \(code)"))
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
                                    continuation.yield(.toolCall(ToolCall(
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

                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else {
                            continue
                        }

                        // Text content
                        if let content = delta["content"] as? String {
                            continuation.yield(.text(content))
                        }

                        // Tool calls (supports multiple parallel tool calls)
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

                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish()
                }
            }
        }
    }
}
