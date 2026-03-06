import Foundation

// MARK: - Shared LLM Types
//
// These types are used by all provider session adapters (OpenAICompatibleSession,
// GoogleSession, etc.) and are defined at top level to avoid Swift's restriction
// on accessing nested types of actors from outside the actor.

// MARK: - Message

struct LLMMessage: Codable, Sendable {
    let role: String
    let content: LLMMessageContent

    enum LLMMessageContent: Codable, Sendable {
        case text(String)
        case parts([LLMContentPart])

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
                self = .parts(try container.decode([LLMContentPart].self))
            }
        }
    }

    static func system(_ text: String) -> LLMMessage {
        LLMMessage(role: "system", content: .text(text))
    }

    static func user(_ text: String) -> LLMMessage {
        LLMMessage(role: "user", content: .text(text))
    }

    static func userWithImage(text: String, imageBase64: String, mimeType: String = "image/png") -> LLMMessage {
        LLMMessage(role: "user", content: .parts([
            LLMContentPart(type: "text", text: text, imageUrl: nil),
            LLMContentPart(type: "image_url", text: nil, imageUrl: .init(url: "data:\(mimeType);base64,\(imageBase64)"))
        ]))
    }

    static func assistant(_ text: String) -> LLMMessage {
        LLMMessage(role: "assistant", content: .text(text))
    }
}

// MARK: - Content Part

struct LLMContentPart: Codable, Sendable {
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

// MARK: - Tool Calling Types

struct LLMToolDefinition: @unchecked Sendable {
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

struct LLMToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String
}

// MARK: - Stream Event

enum LLMStreamEvent: Sendable {
    case text(String)
    case toolCall(LLMToolCall)
    case done
    case error(String)
}

// MARK: - Provider Error

enum LLMProviderError: LocalizedError {
    case missingAPIKey
    case requestFailed(Int)
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key is required but was not provided"
        case .requestFailed(let code):
            return "Request failed with status \(code)"
        case .invalidResponse:
            return "Invalid response from provider"
        case .rateLimited:
            return "Rate limit exceeded"
        }
    }
}
