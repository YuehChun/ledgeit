import Foundation
import GRDB

struct FinancialGoal: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    var id: String
    var type: String                // short_term, long_term
    var title: String
    var description: String
    var targetAmount: Double?
    var targetDate: String?
    var category: String?           // savings, budget, investment, debt
    var status: String = "suggested" // suggested, accepted, completed, dismissed
    var progress: Double = 0
    var createdAt: String?

    static let databaseTableName = "financial_goals"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let title = Column(CodingKeys.title)
        static let description = Column(CodingKeys.description)
        static let targetAmount = Column(CodingKeys.targetAmount)
        static let targetDate = Column(CodingKeys.targetDate)
        static let category = Column(CodingKeys.category)
        static let status = Column(CodingKeys.status)
        static let progress = Column(CodingKeys.progress)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case targetAmount = "target_amount"
        case targetDate = "target_date"
        case category
        case status
        case progress
        case createdAt = "created_at"
    }
}
