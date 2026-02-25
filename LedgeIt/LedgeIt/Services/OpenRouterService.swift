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
}
