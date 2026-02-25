import Foundation
import GRDB

struct CalendarEvent: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var transactionId: Int64?
    var googleEventId: String?
    var title: String?
    var date: String?
    var amount: Double?
    var currency: String?
    var isSynced: Bool = false

    static let databaseTableName = "calendar_events"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let transactionId = Column(CodingKeys.transactionId)
        static let googleEventId = Column(CodingKeys.googleEventId)
        static let title = Column(CodingKeys.title)
        static let date = Column(CodingKeys.date)
        static let amount = Column(CodingKeys.amount)
        static let currency = Column(CodingKeys.currency)
        static let isSynced = Column(CodingKeys.isSynced)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case transactionId = "transaction_id"
        case googleEventId = "google_event_id"
        case title
        case date
        case amount
        case currency
        case isSynced = "is_synced"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
