import Foundation

struct FinancialAdvisor: Sendable {
    let openRouter: OpenRouterService

    // MARK: - Result Types

    struct SpendingAdvice: Codable, Sendable {
        let overallAssessment: String
        let healthScore: Int
        let positiveHabits: [String]
        let concerns: [String]
        let actionItems: [String]
        let categoryInsights: [CategoryInsight]

        enum CodingKeys: String, CodingKey {
            case overallAssessment = "overall_assessment"
            case healthScore = "health_score"
            case positiveHabits = "positive_habits"
            case concerns
            case actionItems = "action_items"
            case categoryInsights = "category_insights"
        }
    }

    struct CategoryInsight: Codable, Sendable {
        let category: String
        let assessment: String
        let suggestion: String?
    }

    // MARK: - Analyze Spending Habits

    func analyzeSpendingHabits(report: SpendingAnalyzer.MonthlyReport, trends: [SpendingAnalyzer.MonthTrend], language: String = "en", persona: AdvisorPersona = .moderate) async throws -> SpendingAdvice {
        let categoryText = report.categoryBreakdown.map { cat in
            var line = "\(cat.category): \(String(format: "%.0f", cat.amount)) (\(String(format: "%.1f", cat.percentage))%)"
            if let change = cat.changePercent {
                line += " [MoM: \(change > 0 ? "+" : "")\(String(format: "%.0f", change))%]"
            }
            return line
        }.joined(separator: "\n")

        let merchantText = report.topMerchants.prefix(8).map {
            "\($0.merchant): \(String(format: "%.0f", $0.amount)) (\($0.count) transactions)"
        }.joined(separator: "\n")

        let anomalyText = report.anomalies.isEmpty ? "None detected" : report.anomalies.map {
            "\($0.merchant): \(String(format: "%.0f", $0.amount)) \($0.currency) (\(String(format: "%.1f", $0.deviation))x above average)"
        }.joined(separator: "\n")

        let trendText = trends.map {
            "\($0.label): spending=\(String(format: "%.0f", $0.spending)), income=\(String(format: "%.0f", $0.income)), savings_rate=\(String(format: "%.1f%%", $0.savingsRate * 100))"
        }.joined(separator: "\n")

        let languageInstruction = language == "zh-Hant"
            ? "You MUST write ALL text values in Traditional Chinese (繁體中文). "
            : ""

        let systemPrompt = """
        \(persona.spendingPhilosophy) \
        Target savings rate for this client: \(Int(persona.savingsTarget * 100))%. \
        Risk tolerance: \(persona.riskLevel). \
        Evaluate spending against these standards. \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """

        let userPrompt = """
        Analyze this monthly spending data and provide professional financial advice.

        MONTHLY SUMMARY:
        - Total Spending: \(String(format: "%.0f", report.totalSpending))
        - Total Income: \(String(format: "%.0f", report.totalIncome))
        - Savings Rate: \(String(format: "%.1f%%", report.savingsRate * 100))
        - Transaction Count: \(report.transactionCount)

        CATEGORY BREAKDOWN:
        \(categoryText)

        TOP MERCHANTS:
        \(merchantText)

        ANOMALIES:
        \(anomalyText)

        MONTHLY TRENDS (last 6 months):
        \(trendText)

        Return JSON:
        {
          "overall_assessment": "2-3 sentence overall evaluation of financial health",
          "health_score": 75,
          "positive_habits": ["specific good habits observed"],
          "concerns": ["specific financial concerns"],
          "action_items": ["concrete, actionable steps to improve finances"],
          "category_insights": [
            {"category": "category_name", "assessment": "brief assessment", "suggestion": "specific suggestion or null"}
          ]
        }

        Rules:
        - health_score: 0-100 (0=critical, 50=needs improvement, 75=good, 90+=excellent)
        - Focus on actionable advice, not generic platitudes
        - If savings rate < \(Int(persona.savingsTarget * 100))%, flag it as a concern
        - Highlight any month-over-month spending increases > 30%
        - Provide max 3 action items, ordered by impact
        - Only include category_insights for categories with notable observations
        """

        let response = try await openRouter.complete(
            model: PFMConfig.extractionModel,
            messages: [
                .system(systemPrompt),
                .user(userPrompt)
            ],
            temperature: 0.3,
            maxTokens: 2000
        )

        return try parseJSON(response)
    }

    private func parseJSON(_ raw: String) throws -> SpendingAdvice {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8) {
            do {
                return try JSONDecoder().decode(SpendingAdvice.self, from: data)
            } catch { /* fall through */ }
        }

        if let startRange = cleaned.range(of: "{"),
           let endRange = cleaned.range(of: "}", options: .backwards) {
            var jsonStr = String(cleaned[startRange.lowerBound...endRange.upperBound])
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\}"#, with: "}", options: .regularExpression)
            jsonStr = jsonStr.replacingOccurrences(of: #",\s*\]"#, with: "]", options: .regularExpression)
            if let data = jsonStr.data(using: .utf8) {
                return try JSONDecoder().decode(SpendingAdvice.self, from: data)
            }
        }

        throw LLMProcessorError.jsonParsingFailed(raw.prefix(500).description)
    }
}
