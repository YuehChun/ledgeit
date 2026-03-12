import Foundation
import GRDB

struct HeartbeatInsight: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let date: String
    var content: String
    var status: String
    var isRead: Bool
    let createdAt: String

    static let databaseTableName = "heartbeat_insights"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let content = Column(CodingKeys.content)
        static let status = Column(CodingKeys.status)
        static let isRead = Column(CodingKeys.isRead)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case content
        case status
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    static func pending(date: String) -> HeartbeatInsight {
        HeartbeatInsight(
            id: UUID(),
            date: date,
            content: "",
            status: "pending",
            isRead: false,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
