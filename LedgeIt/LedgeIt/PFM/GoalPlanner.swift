import Foundation
import AnyLanguageModel
import GRDB

struct GoalPlanner: Sendable {
    let providerConfig: AIProviderConfiguration
    let database: AppDatabase

    // MARK: - Result Types

    struct GoalSuggestions: Codable, Sendable {
        let shortTerm: [GoalSuggestion]
        let longTerm: [GoalSuggestion]

        enum CodingKeys: String, CodingKey {
            case shortTerm = "short_term"
            case longTerm = "long_term"
        }
    }

    struct GoalSuggestion: Codable, Sendable {
        let title: String
        let description: String
        let targetAmount: Double?
        let targetMonths: Int?
        let category: String        // savings, budget, investment, debt
        let reasoning: String

        enum CodingKeys: String, CodingKey {
            case title, description, category, reasoning
            case targetAmount = "target_amount"
            case targetMonths = "target_months"
        }
    }

    // MARK: - Suggest Goals

    func suggestGoals(
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice,
        language: String = "en",
        persona: AdvisorPersona = .moderate
    ) async throws -> GoalSuggestions {
        // Fetch existing active goals to avoid duplicates
        let existingGoals: [FinancialGoal] = try await database.db.read { db in
            try FinancialGoal
                .filter(FinancialGoal.Columns.status == "suggested" || FinancialGoal.Columns.status == "accepted")
                .fetchAll(db)
        }

        let existingText = existingGoals.isEmpty ? "None" : existingGoals.map {
            "[\($0.type)] \($0.title) - \($0.status)"
        }.joined(separator: "\n")

        let languageName: String
        let languageInstruction: String
        switch language {
        case "zh-Hant":
            languageName = "Traditional Chinese (繁體中文)"
            languageInstruction = "CRITICAL: You MUST write ALL text values (title, description, reasoning) in Traditional Chinese (繁體中文). Do NOT use English for any user-facing text. "
        default:
            languageName = "English"
            languageInstruction = ""
        }

        let personaPriority: String
        switch persona.id {
        case "conservative":
            personaPriority = "Prioritize: emergency fund first, then debt elimination, then insurance review. Avoid investment goals."
        case "aggressive":
            personaPriority = "Prioritize: investment goals first, then income growth, then strategic debt leverage. Focus on wealth building."
        default:
            personaPriority = "Prioritize: balanced savings and investment, moderate spending reduction, diversified goals."
        }

        let systemPrompt = """
        You are a \(persona.id) financial planner creating personalized financial goals. \
        Target savings rate: \(Int(persona.savingsTarget * 100))%. Risk tolerance: \(persona.riskLevel). \
        \(personaPriority) \
        Goals should be SMART (Specific, Measurable, Achievable, Relevant, Time-bound). \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Based on this financial analysis, suggest personalized financial goals.

        MONTHLY SPENDING: \(String(format: "%.0f", report.totalSpending))
        MONTHLY INCOME: \(String(format: "%.0f", report.totalIncome))
        SAVINGS RATE: \(String(format: "%.1f%%", report.savingsRate * 100))
        HEALTH SCORE: \(advice.healthScore)/100

        CONCERNS:
        \(advice.concerns.joined(separator: "\n"))

        ACTION ITEMS:
        \(advice.actionItems.joined(separator: "\n"))

        TOP SPENDING CATEGORIES:
        \(report.categoryBreakdown.prefix(5).map { "\($0.category): \(String(format: "%.0f", $0.amount)) (\(String(format: "%.1f", $0.percentage))%)" }.joined(separator: "\n"))

        EXISTING GOALS (avoid duplicates):
        \(existingText)

        Return JSON:
        {
          "short_term": [
            {
              "title": "Clear goal title",
              "description": "Detailed description with specific actions",
              "target_amount": 10000,
              "target_months": 3,
              "category": "budget",
              "reasoning": "Why this goal matters based on the data"
            }
          ],
          "long_term": [
            {
              "title": "Clear goal title",
              "description": "Detailed description",
              "target_amount": 100000,
              "target_months": 24,
              "category": "savings",
              "reasoning": "Why this goal matters"
            }
          ]
        }

        Rules:
        - short_term: 1-3 goals, achievable in 1-3 months
        - long_term: 1-2 goals, 1-3 year horizon
        - category must be one of: savings, budget, investment, debt
        - target_amount is optional (null for non-monetary goals like "track all expenses")
        - target_months: estimated time to achieve
        - Do NOT suggest goals that duplicate existing ones
        - Be specific: "Reduce dining spending to X/month" not "Spend less on food"
        - LANGUAGE: All user-facing text (title, description, reasoning) MUST be written in \(languageName)
        """

        let session = try SessionFactory.makeSession(
            assignment: providerConfig.extraction,
            config: providerConfig,
            instructions: systemPrompt
        )
        let response = try await session.respond(
            to: userPrompt,
            options: GenerationOptions(temperature: 0.3)
        )

        return try parseJSON(response.content)
    }

    // MARK: - Save Goals to DB

    func saveGoals(_ suggestions: GoalSuggestions) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let calendar = Calendar.current
        let today = Date()

        try await database.db.write { db in
            for goal in suggestions.shortTerm {
                let targetDate = goal.targetMonths.flatMap {
                    calendar.date(byAdding: .month, value: $0, to: today)
                }.map { ISO8601DateFormatter().string(from: $0).prefix(10) }

                let record = FinancialGoal(
                    id: UUID().uuidString,
                    type: "short_term",
                    title: goal.title,
                    description: goal.description,
                    targetAmount: goal.targetAmount,
                    targetDate: targetDate.map(String.init),
                    category: goal.category,
                    status: "suggested",
                    progress: 0,
                    createdAt: now
                )
                try record.insert(db)
            }

            for goal in suggestions.longTerm {
                let targetDate = goal.targetMonths.flatMap {
                    calendar.date(byAdding: .month, value: $0, to: today)
                }.map { ISO8601DateFormatter().string(from: $0).prefix(10) }

                let record = FinancialGoal(
                    id: UUID().uuidString,
                    type: "long_term",
                    title: goal.title,
                    description: goal.description,
                    targetAmount: goal.targetAmount,
                    targetDate: targetDate.map(String.init),
                    category: goal.category,
                    status: "suggested",
                    progress: 0,
                    createdAt: now
                )
                try record.insert(db)
            }
        }
    }

    private func parseJSON(_ raw: String) throws -> GoalSuggestions {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(GoalSuggestions.self, from: data)
            } catch { /* fall through */ }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(GoalSuggestions.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
