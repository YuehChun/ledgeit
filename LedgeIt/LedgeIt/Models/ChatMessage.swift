import Foundation
import GRDB

struct ChatMessage: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let role: ChatRole
    var content: String
    let createdAt: String

    enum ChatRole: String, Sendable, Codable {
        case user
        case assistant
        case system
    }

    static let databaseTableName = "chat_messages"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let role = Column(CodingKeys.role)
        static let content = Column(CodingKeys.content)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
    }

    private static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func user(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .user, content: text, createdAt: now())
    }

    static func assistant(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .assistant, content: text, createdAt: now())
    }

    static func system(_ text: String) -> ChatMessage {
        ChatMessage(id: UUID(), role: .system, content: text, createdAt: now())
    }
}

enum ChatStreamEvent: Sendable {
    case messageStarted(UUID)
    case textDelta(String)
    case toolCallStarted(String)
    case messageComplete
    case error(String)
}
