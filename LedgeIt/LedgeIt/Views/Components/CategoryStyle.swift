import SwiftUI

enum CategoryGroup: String {
    case lifestyle
    case financial
    case commerce
    case income
}

struct CategoryStyle {
    let displayName: String
    let icon: String
    let color: Color
    let group: CategoryGroup
    let isFinancialObligation: Bool

    static func style(for category: AutoCategorizer.LeanCategory) -> CategoryStyle {
        switch category {
        case .foodAndDrink:
            return CategoryStyle(displayName: "Food & Drink", icon: "fork.knife",
                                 color: Color(red: 0.96, green: 0.52, blue: 0.13), group: .lifestyle, isFinancialObligation: false)
        case .groceries:
            return CategoryStyle(displayName: "Groceries", icon: "cart.fill",
                                 color: Color(red: 0.30, green: 0.75, blue: 0.30), group: .lifestyle, isFinancialObligation: false)
        case .entertainment:
            return CategoryStyle(displayName: "Entertainment", icon: "film.fill",
                                 color: Color(red: 0.91, green: 0.30, blue: 0.60), group: .lifestyle, isFinancialObligation: false)
        case .travel:
            return CategoryStyle(displayName: "Travel", icon: "airplane",
                                 color: Color(red: 0.00, green: 0.72, blue: 0.84), group: .lifestyle, isFinancialObligation: false)
        case .healthcare:
            return CategoryStyle(displayName: "Healthcare", icon: "cross.case.fill",
                                 color: Color(red: 0.90, green: 0.24, blue: 0.24), group: .lifestyle, isFinancialObligation: false)
        case .personalCare:
            return CategoryStyle(displayName: "Personal Care", icon: "sparkles",
                                 color: Color(red: 0.68, green: 0.44, blue: 0.85), group: .lifestyle, isFinancialObligation: false)
        case .education:
            return CategoryStyle(displayName: "Education", icon: "graduationcap.fill",
                                 color: Color(red: 0.35, green: 0.34, blue: 0.84), group: .lifestyle, isFinancialObligation: false)
        case .charity:
            return CategoryStyle(displayName: "Charity", icon: "heart.fill",
                                 color: Color(red: 0.80, green: 0.40, blue: 0.72), group: .lifestyle, isFinancialObligation: false)
        case .bankFeesAndCharges:
            return CategoryStyle(displayName: "Bank Fees", icon: "building.columns.fill",
                                 color: Color(red: 0.78, green: 0.18, blue: 0.18), group: .financial, isFinancialObligation: true)
        case .utilities:
            return CategoryStyle(displayName: "Utilities", icon: "bolt.fill",
                                 color: Color(red: 0.20, green: 0.60, blue: 0.72), group: .financial, isFinancialObligation: true)
        case .insurance:
            return CategoryStyle(displayName: "Insurance", icon: "shield.checkered",
                                 color: Color(red: 0.44, green: 0.55, blue: 0.68), group: .financial, isFinancialObligation: true)
        case .investments:
            return CategoryStyle(displayName: "Investments", icon: "chart.line.uptrend.xyaxis",
                                 color: Color(red: 0.85, green: 0.68, blue: 0.00), group: .financial, isFinancialObligation: false)
        case .shopping:
            return CategoryStyle(displayName: "Shopping", icon: "bag.fill",
                                 color: Color(red: 0.60, green: 0.30, blue: 0.85), group: .commerce, isFinancialObligation: false)
        case .transport:
            return CategoryStyle(displayName: "Transport", icon: "car.fill",
                                 color: Color(red: 0.20, green: 0.50, blue: 0.90), group: .commerce, isFinancialObligation: false)
        case .salaryAndWages:
            return CategoryStyle(displayName: "Salary & Wages", icon: "banknote.fill",
                                 color: Color(red: 0.20, green: 0.78, blue: 0.35), group: .income, isFinancialObligation: false)
        case .freelanceIncome:
            return CategoryStyle(displayName: "Freelance Income", icon: "briefcase.fill",
                                 color: Color(red: 0.25, green: 0.72, blue: 0.48), group: .income, isFinancialObligation: false)
        case .investmentReturns:
            return CategoryStyle(displayName: "Investment Returns", icon: "chart.line.uptrend.xyaxis",
                                 color: Color(red: 0.90, green: 0.72, blue: 0.10), group: .income, isFinancialObligation: false)
        case .refund:
            return CategoryStyle(displayName: "Refund", icon: "arrow.uturn.backward.circle.fill",
                                 color: Color(red: 0.40, green: 0.70, blue: 0.90), group: .income, isFinancialObligation: false)
        case .general:
            return CategoryStyle(displayName: "General", icon: "square.grid.2x2.fill",
                                 color: Color(red: 0.55, green: 0.55, blue: 0.58), group: .commerce, isFinancialObligation: false)
        }
    }

    static func style(forRawCategory raw: String) -> CategoryStyle {
        let normalized = raw
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "&", with: "AND")
            .uppercased()
        if let lean = AutoCategorizer.LeanCategory(rawValue: normalized) {
            return style(for: lean)
        }
        let lower = raw.lowercased().replacingOccurrences(of: "_", with: " ")
        for cat in AutoCategorizer.LeanCategory.allCases {
            if style(for: cat).displayName.lowercased() == lower {
                return style(for: cat)
            }
        }
        return style(for: .general)
    }
}
