import Foundation
import GRDB

struct FinancialReport: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: String
    var reportType: String          // monthly, quarterly, yearly
    var periodStart: String
    var periodEnd: String
    var summaryJSON: String
    var adviceJSON: String
    var goalsJSON: String
    var createdAt: String?

    static let databaseTableName = "financial_reports"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let reportType = Column(CodingKeys.reportType)
        static let periodStart = Column(CodingKeys.periodStart)
        static let periodEnd = Column(CodingKeys.periodEnd)
        static let summaryJSON = Column(CodingKeys.summaryJSON)
        static let adviceJSON = Column(CodingKeys.adviceJSON)
        static let goalsJSON = Column(CodingKeys.goalsJSON)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case reportType = "report_type"
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case summaryJSON = "summary_json"
        case adviceJSON = "advice_json"
        case goalsJSON = "goals_json"
        case createdAt = "created_at"
    }
}
