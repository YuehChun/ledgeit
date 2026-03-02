import Foundation
import GRDB

struct StatementImport: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var filename: String
    var bankName: String?
    var statementPeriod: String?
    var transactionCount: Int = 0
    var importedAt: String?
    var status: String = "pending"
    var errorMessage: String?

    static let databaseTableName = "statement_imports"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let filename = Column(CodingKeys.filename)
        static let bankName = Column(CodingKeys.bankName)
        static let statementPeriod = Column(CodingKeys.statementPeriod)
        static let transactionCount = Column(CodingKeys.transactionCount)
        static let importedAt = Column(CodingKeys.importedAt)
        static let status = Column(CodingKeys.status)
        static let errorMessage = Column(CodingKeys.errorMessage)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case filename
        case bankName = "bank_name"
        case statementPeriod = "statement_period"
        case transactionCount = "transaction_count"
        case importedAt = "imported_at"
        case status
        case errorMessage = "error_message"
    }
}
