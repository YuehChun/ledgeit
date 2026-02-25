import Foundation
import GRDB

struct Attachment: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var emailId: String?
    var filename: String?
    var mimeType: String?
    var size: Int?
    var gmailAttachmentId: String?
    var extractedText: String?
    var isProcessed: Bool = false

    static let databaseTableName = "attachments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let emailId = Column(CodingKeys.emailId)
        static let filename = Column(CodingKeys.filename)
        static let mimeType = Column(CodingKeys.mimeType)
        static let size = Column(CodingKeys.size)
        static let gmailAttachmentId = Column(CodingKeys.gmailAttachmentId)
        static let extractedText = Column(CodingKeys.extractedText)
        static let isProcessed = Column(CodingKeys.isProcessed)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emailId = "email_id"
        case filename
        case mimeType = "mime_type"
        case size
        case gmailAttachmentId = "gmail_attachment_id"
        case extractedText = "extracted_text"
        case isProcessed = "is_processed"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
