import Foundation
import GRDB

struct CreditCardBill: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: Int64?
    var emailId: String?
    var bankName: String
    var dueDate: String
    var amountDue: Double
    var currency: String = "TWD"
    var statementPeriod: String?
    var isPaid: Bool = false
    var createdAt: String?
    var reconciliationStatus: String?
    var reconciledAmount: Double?

    static let databaseTableName = "credit_card_bills"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let emailId = Column(CodingKeys.emailId)
        static let bankName = Column(CodingKeys.bankName)
        static let dueDate = Column(CodingKeys.dueDate)
        static let amountDue = Column(CodingKeys.amountDue)
        static let currency = Column(CodingKeys.currency)
        static let statementPeriod = Column(CodingKeys.statementPeriod)
        static let isPaid = Column(CodingKeys.isPaid)
        static let createdAt = Column(CodingKeys.createdAt)
        static let reconciliationStatus = Column(CodingKeys.reconciliationStatus)
        static let reconciledAmount = Column(CodingKeys.reconciledAmount)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case emailId = "email_id"
        case bankName = "bank_name"
        case dueDate = "due_date"
        case amountDue = "amount_due"
        case currency
        case statementPeriod = "statement_period"
        case isPaid = "is_paid"
        case createdAt = "created_at"
        case reconciliationStatus = "reconciliation_status"
        case reconciledAmount = "reconciled_amount"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
