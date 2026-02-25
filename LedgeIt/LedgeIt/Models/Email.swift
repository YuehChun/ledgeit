import Foundation
import GRDB

struct Email: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: String
    var threadId: String?
    var subject: String?
    var sender: String?
    var date: String?
    var snippet: String?
    var bodyText: String?
    var bodyHtml: String?
    var labels: String?
    var isFinancial: Bool = false
    var isProcessed: Bool = false
    var classificationResult: String?
    var createdAt: String?

    static let databaseTableName = "emails"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let threadId = Column(CodingKeys.threadId)
        static let subject = Column(CodingKeys.subject)
        static let sender = Column(CodingKeys.sender)
        static let date = Column(CodingKeys.date)
        static let snippet = Column(CodingKeys.snippet)
        static let bodyText = Column(CodingKeys.bodyText)
        static let bodyHtml = Column(CodingKeys.bodyHtml)
        static let labels = Column(CodingKeys.labels)
        static let isFinancial = Column(CodingKeys.isFinancial)
        static let isProcessed = Column(CodingKeys.isProcessed)
        static let classificationResult = Column(CodingKeys.classificationResult)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case threadId = "thread_id"
        case subject
        case sender
        case date
        case snippet
        case bodyText = "body_text"
        case bodyHtml = "body_html"
        case labels
        case isFinancial = "is_financial"
        case isProcessed = "is_processed"
        case classificationResult = "classification_result"
        case createdAt = "created_at"
    }
}
