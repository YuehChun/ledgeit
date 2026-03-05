import Foundation
import GRDB

struct DedupLog: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var keptTransactionId: Int64
    var removedTransactionId: Int64
    var matchScore: Double
    var matchMethod: String
    var matchDetails: String?
    var createdAt: String

    static let databaseTableName = "dedup_log"

    enum CodingKeys: String, CodingKey {
        case id
        case keptTransactionId = "kept_transaction_id"
        case removedTransactionId = "removed_transaction_id"
        case matchScore = "match_score"
        case matchMethod = "match_method"
        case matchDetails = "match_details"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
