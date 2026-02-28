import Foundation
import GRDB

struct PromptVersion: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    var id: Int64?
    var basePersonaId: String
    var spendingPhilosophy: String
    var savingsTarget: Double
    var riskLevel: String
    var categoryBudgetHints: String   // JSON-encoded [String: Double]
    var userFeedback: String?
    var isActive: Bool
    var createdAt: String?

    static let databaseTableName = "prompt_versions"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let basePersonaId = Column(CodingKeys.basePersonaId)
        static let spendingPhilosophy = Column(CodingKeys.spendingPhilosophy)
        static let savingsTarget = Column(CodingKeys.savingsTarget)
        static let riskLevel = Column(CodingKeys.riskLevel)
        static let categoryBudgetHints = Column(CodingKeys.categoryBudgetHints)
        static let userFeedback = Column(CodingKeys.userFeedback)
        static let isActive = Column(CodingKeys.isActive)
        static let createdAt = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case basePersonaId = "base_persona_id"
        case spendingPhilosophy = "spending_philosophy"
        case savingsTarget = "savings_target"
        case riskLevel = "risk_level"
        case categoryBudgetHints = "category_budget_hints"
        case userFeedback = "user_feedback"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    func toPersona() -> AdvisorPersona {
        let hints: [String: Double] = {
            guard let data = categoryBudgetHints.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
            else { return AdvisorPersona.moderate.categoryBudgetHints }
            return decoded
        }()
        return AdvisorPersona(
            id: basePersonaId,
            savingsTarget: savingsTarget,
            riskLevel: riskLevel,
            spendingPhilosophy: spendingPhilosophy,
            categoryBudgetHints: hints
        )
    }

    static func fromPersona(_ persona: AdvisorPersona, feedback: String?) -> PromptVersion {
        let hintsJSON = (try? String(data: JSONEncoder().encode(persona.categoryBudgetHints), encoding: .utf8)) ?? "{}"
        return PromptVersion(
            basePersonaId: persona.id,
            spendingPhilosophy: persona.spendingPhilosophy,
            savingsTarget: persona.savingsTarget,
            riskLevel: persona.riskLevel,
            categoryBudgetHints: hintsJSON,
            userFeedback: feedback,
            isActive: true,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
