import Foundation
import GRDB

struct SyncState: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64 = 1
    var lastSyncDate: String?
    var lastHistoryId: String?
    var totalEmailsSynced: Int = 0
    var totalEmailsProcessed: Int = 0

    static let databaseTableName = "sync_state"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let lastSyncDate = Column(CodingKeys.lastSyncDate)
        static let lastHistoryId = Column(CodingKeys.lastHistoryId)
        static let totalEmailsSynced = Column(CodingKeys.totalEmailsSynced)
        static let totalEmailsProcessed = Column(CodingKeys.totalEmailsProcessed)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case lastSyncDate = "last_sync_date"
        case lastHistoryId = "last_history_id"
        case totalEmailsSynced = "total_emails_synced"
        case totalEmailsProcessed = "total_emails_processed"
    }
}
