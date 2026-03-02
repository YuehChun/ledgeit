import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    var content: String
    let timestamp: Date

    enum ChatRole: String, Sendable {
        case user
        case assistant
        case system
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, timestamp: Date())
    }

    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, timestamp: Date())
    }

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .system, content: text, timestamp: Date())
    }
}

enum ChatStreamEvent: Sendable {
    case messageStarted(UUID)
    case textDelta(String)
    case toolCallStarted(String)
    case messageComplete
    case error(String)
}
