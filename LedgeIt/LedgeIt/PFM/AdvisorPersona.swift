import Foundation
import GRDB

struct AdvisorPersona: Codable, Sendable, Identifiable {
    let id: String
    let savingsTarget: Double
    let riskLevel: String
    let spendingPhilosophy: String
    let categoryBudgetHints: [String: Double]

    static let conservative = AdvisorPersona(
        id: "conservative",
        savingsTarget: 0.30,
        riskLevel: "low",
        spendingPhilosophy: """
        You are a CONSERVATIVE financial planner. Your philosophy: \
        Minimize all discretionary spending. Maximize emergency fund (6+ months expenses). \
        Avoid all debt. Prioritize capital preservation over growth. \
        Flag ANY non-essential spending as a concern. Recommend the most frugal path.
        """,
        categoryBudgetHints: [
            "FOOD_AND_DRINK": 0.08, "GROCERIES": 0.12, "ENTERTAINMENT": 0.03,
            "TRAVEL": 0.02, "SHOPPING": 0.05, "TRANSPORT": 0.08,
            "PERSONAL_CARE": 0.03, "EDUCATION": 0.05,
        ]
    )

    static let moderate = AdvisorPersona(
        id: "moderate",
        savingsTarget: 0.20,
        riskLevel: "medium",
        spendingPhilosophy: """
        You are a MODERATE financial planner. Your philosophy: \
        Balance lifestyle enjoyment with steady savings. Target 20% savings rate. \
        Diversified approach to investments. Moderate risk tolerance. \
        Allow reasonable discretionary spending but flag significant overages.
        """,
        categoryBudgetHints: [
            "FOOD_AND_DRINK": 0.12, "GROCERIES": 0.15, "ENTERTAINMENT": 0.08,
            "TRAVEL": 0.05, "SHOPPING": 0.10, "TRANSPORT": 0.10,
            "PERSONAL_CARE": 0.05, "EDUCATION": 0.08,
        ]
    )

    static let aggressive = AdvisorPersona(
        id: "aggressive",
        savingsTarget: 0.10,
        riskLevel: "high",
        spendingPhilosophy: """
        You are an AGGRESSIVE growth-focused financial planner. Your philosophy: \
        Maximize ROI and wealth growth. Invest heavily. Tolerate higher spending \
        if it generates income or career growth. Leverage debt strategically. \
        Focus on income growth opportunities over spending cuts.
        """,
        categoryBudgetHints: [
            "FOOD_AND_DRINK": 0.15, "GROCERIES": 0.15, "ENTERTAINMENT": 0.12,
            "TRAVEL": 0.10, "SHOPPING": 0.15, "TRANSPORT": 0.12,
            "PERSONAL_CARE": 0.08, "EDUCATION": 0.15,
        ]
    )

    static let allPresets: [AdvisorPersona] = [conservative, moderate, aggressive]

    static func custom(savingsTarget: Double, riskLevel: String) -> AdvisorPersona {
        let riskDescription: String
        switch riskLevel {
        case "low": riskDescription = "conservative risk tolerance, prioritize safety"
        case "high": riskDescription = "high risk tolerance, prioritize growth"
        default: riskDescription = "moderate risk tolerance, balanced approach"
        }

        let spendingMultiplier = (1.0 - savingsTarget) / 0.8
        let moderateHints = AdvisorPersona.moderate.categoryBudgetHints
        let scaledHints = moderateHints.mapValues { $0 * spendingMultiplier }

        return AdvisorPersona(
            id: "custom",
            savingsTarget: savingsTarget,
            riskLevel: riskLevel,
            spendingPhilosophy: """
            You are a CUSTOM financial planner configured by the user. \
            Target savings rate: \(Int(savingsTarget * 100))%. \
            Risk profile: \(riskDescription). \
            Evaluate all spending against the \(Int(savingsTarget * 100))% savings target. \
            Adjust advice severity based on how far actual spending deviates from this target.
            """,
            categoryBudgetHints: scaledHints
        )
    }

    static func resolve(id: String, customSavingsTarget: Double, customRiskLevel: String) -> AdvisorPersona {
        switch id {
        case "conservative": return .conservative
        case "aggressive": return .aggressive
        case "custom": return .custom(savingsTarget: customSavingsTarget, riskLevel: customRiskLevel)
        default: return .moderate
        }
    }

    /// Resolve persona checking for an active versioned prompt first, falling back to presets.
    static func resolveWithVersions(id: String, customSavingsTarget: Double, customRiskLevel: String) -> AdvisorPersona {
        if let active = try? AppDatabase.shared.db.read({ db in
            try PromptVersion
                .filter(Column("is_active") == 1)
                .fetchOne(db)
        }) {
            return active.toPersona()
        }
        return resolve(id: id, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }
}
