import Foundation
import GRDB

struct Transaction: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: Int64?
    var emailId: String?
    var attachmentId: Int64?
    var amount: Double
    var currency: String = "USD"
    var merchant: String?
    var category: String?
    var subcategory: String?
    var transactionDate: String?
    var description: String?
    var type: String?
    var transferType: String?
    var transferMetadata: String?
    var confidence: Double?
    var rawExtraction: String?
    var createdAt: String?
    var isReviewed: Bool = false
    var deletedAt: String?
    var isDuplicateOf: Int64?
    var embeddingVersion: Int = 0
    var userCorrectedType: String?
    var userCorrectedCategory: String?
    var extractionConfidence: Double?

    static let databaseTableName = "transactions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let emailId = Column(CodingKeys.emailId)
        static let attachmentId = Column(CodingKeys.attachmentId)
        static let amount = Column(CodingKeys.amount)
        static let currency = Column(CodingKeys.currency)
        static let merchant = Column(CodingKeys.merchant)
        static let category = Column(CodingKeys.category)
        static let subcategory = Column(CodingKeys.subcategory)
        static let transactionDate = Column(CodingKeys.transactionDate)
        static let description = Column(CodingKeys.description)
        static let type = Column(CodingKeys.type)
        static let transferType = Column(CodingKeys.transferType)
        static let transferMetadata = Column(CodingKeys.transferMetadata)
        static let confidence = Column(CodingKeys.confidence)
        static let rawExtraction = Column(CodingKeys.rawExtraction)
        static let createdAt = Column(CodingKeys.createdAt)
        static let isReviewed = Column(CodingKeys.isReviewed)
        static let deletedAt = Column(CodingKeys.deletedAt)
        static let isDuplicateOf = Column(CodingKeys.isDuplicateOf)
        static let embeddingVersion = Column(CodingKeys.embeddingVersion)
        static let userCorrectedType = Column(CodingKeys.userCorrectedType)
        static let userCorrectedCategory = Column(CodingKeys.userCorrectedCategory)
        static let extractionConfidence = Column(CodingKeys.extractionConfidence)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emailId = "email_id"
        case attachmentId = "attachment_id"
        case amount
        case currency
        case merchant
        case category
        case subcategory
        case transactionDate = "transaction_date"
        case description
        case type
        case transferType = "transfer_type"
        case transferMetadata = "transfer_metadata"
        case confidence
        case rawExtraction = "raw_extraction"
        case createdAt = "created_at"
        case isReviewed = "is_reviewed"
        case deletedAt = "deleted_at"
        case isDuplicateOf = "is_duplicate_of"
        case embeddingVersion = "embedding_version"
        case userCorrectedType = "user_corrected_type"
        case userCorrectedCategory = "user_corrected_category"
        case extractionConfidence = "extraction_confidence"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
