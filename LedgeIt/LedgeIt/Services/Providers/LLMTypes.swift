import Foundation

// MARK: - Shared LLM Types
//
// These types are used by all provider session adapters (OpenAICompatibleSession,
// GoogleSession, etc.) and are defined at top level to avoid Swift's restriction
// on accessing nested types of actors from outside the actor.

// MARK: - Message

struct LLMMessage: Sendable {
    let role: String
    let content: LLMMessageContent
    let toolCalls: [LLMToolCall]?
    let toolCallId: String?

    enum LLMMessageContent: Sendable {
        case text(String)
        case parts([LLMContentPart])
    }

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

// MARK: - Content Part

struct LLMContentPart: Sendable {
    let type: String
    let text: String?
    let imageUrl: ImageURL?

    struct ImageURL: Sendable {
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
