import Foundation
import AnyLanguageModel

struct PromptOptimizer: Sendable {
    let providerConfig: AIProviderConfiguration

    struct OptimizedPrompt: Codable, Sendable {
        let spendingPhilosophy: String
        let savingsTarget: Double
        let riskLevel: String
        let categoryBudgetHints: [String: Double]
        let changesSummary: String

        enum CodingKeys: String, CodingKey {
            case spendingPhilosophy = "spending_philosophy"
            case savingsTarget = "savings_target"
            case riskLevel = "risk_level"
            case categoryBudgetHints = "category_budget_hints"
            case changesSummary = "changes_summary"
        }
    }

    func optimizePrompt(
        currentPersona: AdvisorPersona,
        feedback: String,
        language: String = "en"
    ) async throws -> OptimizedPrompt {
        let languageInstruction = language == "zh-Hant"
            ? "Write spending_philosophy and changes_summary in Traditional Chinese. "
            : ""

        let budgetJSON = (try? String(data: JSONEncoder().encode(currentPersona.categoryBudgetHints), encoding: .utf8)) ?? "{}"

        let systemPrompt = """
        You are an expert at calibrating financial advisor AI prompts. \
        The user has a financial advisor AI with specific parameters. \
        They are providing feedback on the advice quality. \
        Your job: adjust the advisor's system prompt and parameters to better match \
        the user's preferences while keeping the advice professional and sound. \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        CURRENT ADVISOR CONFIGURATION:
        - Persona: \(currentPersona.id)
        - Savings Target: \(Int(currentPersona.savingsTarget * 100))%
        - Risk Level: \(currentPersona.riskLevel)
        - Spending Philosophy:
        \(currentPersona.spendingPhilosophy)
        - Category Budget Hints:
        \(budgetJSON)

        USER FEEDBACK:
        \(feedback)

        Generate an improved advisor configuration that addresses the user's feedback.
        Make targeted adjustments, not wholesale rewrites.

        Return JSON:
        {
          "spending_philosophy": "Full updated system prompt for the financial advisor (2-4 sentences)",
          "savings_target": 0.20,
          "risk_level": "medium",
          "category_budget_hints": {
            "FOOD_AND_DRINK": 0.12, "GROCERIES": 0.15, "ENTERTAINMENT": 0.08,
            "TRAVEL": 0.05, "SHOPPING": 0.10, "TRANSPORT": 0.10,
            "PERSONAL_CARE": 0.05, "EDUCATION": 0.08
          },
          "changes_summary": "Brief 1-2 sentence summary of what was changed and why"
        }

        Rules:
        - savings_target: 0.05 to 0.50
        - risk_level: "low", "medium", or "high"
        - Keep all 8 budget categories, adjust percentages as needed
        - spending_philosophy must be a complete, self-contained prompt
        - If feedback mentions specific categories, adjust that category's budget hint
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

    private func parseJSON(_ raw: String) throws -> OptimizedPrompt {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do { return try JSONDecoder().decode(OptimizedPrompt.self, from: data) }
            catch { /* fall through */ }
        }

        if let start = cleaned.range(of: "{"),
           let end = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[start.lowerBound...end.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(OptimizedPrompt.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
