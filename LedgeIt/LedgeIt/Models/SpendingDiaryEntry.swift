import Foundation
import GRDB

struct SpendingDiaryEntry: Identifiable, Sendable, Codable, FetchableRecord, PersistableRecord {
    let id: UUID
    let date: String
    var content: String
    var personaId: String
    var transactionCount: Int
    var totalSpending: Double
    var currency: String
    var status: String
    let createdAt: String

    static let databaseTableName = "spending_diary_entries"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let content = Column(CodingKeys.content)
        static let personaId = Column(CodingKeys.personaId)
        static let transactionCount = Column(CodingKeys.transactionCount)
        static let totalSpending = Column(CodingKeys.totalSpending)
        static let currency = Column(CodingKeys.currency)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case content
        case personaId = "persona_id"
        case transactionCount = "transaction_count"
        case totalSpending = "total_spending"
        case currency
        case status
        case createdAt = "created_at"
    }

    static func pending(date: String) -> SpendingDiaryEntry {
        SpendingDiaryEntry(
            id: UUID(),
            date: date,
            content: "",
            personaId: "",
            transactionCount: 0,
            totalSpending: 0,
            currency: "TWD",
            status: "pending",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
