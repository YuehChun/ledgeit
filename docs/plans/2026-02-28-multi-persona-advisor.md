# Multi-Persona Financial Advisor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the single financial advisor with 3 preset personas (Conservative/Moderate/Aggressive) + 1 custom, affecting the full pipeline from AI advice to dashboard display, plus add inline transaction verification.

**Architecture:** An `AdvisorPersona` model defines each persona's savings target, risk level, spending philosophy, and category budget hints. The persona flows through `ReportGenerator` → `FinancialAdvisor` → `GoalPlanner` as a parameter, modifying LLM system prompts. A new sidebar view lets users pick their advisor. Transaction rows gain confidence badges and the detail view gains inline editing.

**Tech Stack:** SwiftUI, GRDB, Swift Charts, OpenRouter LLM API

---

### Task 1: AdvisorPersona Model & Presets

**Files:**
- Create: `LedgeIt/LedgeIt/PFM/AdvisorPersona.swift`

**Step 1: Create the AdvisorPersona model with 3 presets + custom builder**

Create `LedgeIt/LedgeIt/PFM/AdvisorPersona.swift`:

```swift
import Foundation

struct AdvisorPersona: Codable, Sendable, Identifiable {
    let id: String
    let savingsTarget: Double
    let riskLevel: String
    let spendingPhilosophy: String
    let categoryBudgetHints: [String: Double]

    // MARK: - Presets

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
            "FOOD_AND_DRINK": 0.08,
            "GROCERIES": 0.12,
            "ENTERTAINMENT": 0.03,
            "TRAVEL": 0.02,
            "SHOPPING": 0.05,
            "TRANSPORT": 0.08,
            "PERSONAL_CARE": 0.03,
            "EDUCATION": 0.05,
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
            "FOOD_AND_DRINK": 0.12,
            "GROCERIES": 0.15,
            "ENTERTAINMENT": 0.08,
            "TRAVEL": 0.05,
            "SHOPPING": 0.10,
            "TRANSPORT": 0.10,
            "PERSONAL_CARE": 0.05,
            "EDUCATION": 0.08,
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
            "FOOD_AND_DRINK": 0.15,
            "GROCERIES": 0.15,
            "ENTERTAINMENT": 0.12,
            "TRAVEL": 0.10,
            "SHOPPING": 0.15,
            "TRANSPORT": 0.12,
            "PERSONAL_CARE": 0.08,
            "EDUCATION": 0.15,
        ]
    )

    static let allPresets: [AdvisorPersona] = [conservative, moderate, aggressive]

    static func custom(savingsTarget: Double, riskLevel: String) -> AdvisorPersona {
        let riskDescription: String
        switch riskLevel {
        case "low":
            riskDescription = "conservative risk tolerance, prioritize safety"
        case "high":
            riskDescription = "high risk tolerance, prioritize growth"
        default:
            riskDescription = "moderate risk tolerance, balanced approach"
        }

        // Scale budget hints based on savings target (lower savings = more spending allowed)
        let spendingMultiplier = (1.0 - savingsTarget) / 0.8 // normalized to moderate baseline
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

    // MARK: - Resolve from AppStorage

    static func resolve(id: String, customSavingsTarget: Double, customRiskLevel: String) -> AdvisorPersona {
        switch id {
        case "conservative": return .conservative
        case "aggressive": return .aggressive
        case "custom": return .custom(savingsTarget: customSavingsTarget, riskLevel: customRiskLevel)
        default: return .moderate
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/PFM/AdvisorPersona.swift
git commit -m "feat: add AdvisorPersona model with conservative/moderate/aggressive presets"
```

---

### Task 2: Wire Persona Through Pipeline (FinancialAdvisor + GoalPlanner + ReportGenerator)

**Files:**
- Modify: `LedgeIt/LedgeIt/PFM/FinancialAdvisor.swift:34,55-63`
- Modify: `LedgeIt/LedgeIt/PFM/GoalPlanner.swift:37-40,52-60`
- Modify: `LedgeIt/LedgeIt/PFM/ReportGenerator.swift:33,47,51`

**Step 1: Update FinancialAdvisor to accept persona**

In `FinancialAdvisor.swift`, change the function signature on line 34:

```swift
func analyzeSpendingHabits(report: SpendingAnalyzer.MonthlyReport, trends: [SpendingAnalyzer.MonthTrend], language: String = "en") async throws -> SpendingAdvice {
```

To:

```swift
func analyzeSpendingHabits(report: SpendingAnalyzer.MonthlyReport, trends: [SpendingAnalyzer.MonthTrend], language: String = "en", persona: AdvisorPersona = .moderate) async throws -> SpendingAdvice {
```

Replace the `systemPrompt` block (lines 55-63, after the `languageInstruction` line):

```swift
        let systemPrompt = """
        You are a certified financial planner (CFP) providing personalized financial advice. \
        Analyze the user's spending data and provide professional, actionable advice. \
        Consider local cost of living standards and common financial planning principles. \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """
```

With:

```swift
        let systemPrompt = """
        \(persona.spendingPhilosophy) \
        Target savings rate for this client: \(Int(persona.savingsTarget * 100))%. \
        Risk tolerance: \(persona.riskLevel). \
        Evaluate spending against these standards. \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """
```

Also in the `userPrompt`, replace the rule on line 102:

```swift
        - If savings rate < 20%, flag it as a concern
```

With:

```swift
        - If savings rate < \(Int(persona.savingsTarget * 100))%, flag it as a concern
```

**Step 2: Update GoalPlanner to accept persona**

In `GoalPlanner.swift`, change the function signature (lines 37-41):

```swift
    func suggestGoals(
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice,
        language: String = "en"
    ) async throws -> GoalSuggestions {
```

To:

```swift
    func suggestGoals(
        report: SpendingAnalyzer.MonthlyReport,
        advice: FinancialAdvisor.SpendingAdvice,
        language: String = "en",
        persona: AdvisorPersona = .moderate
    ) async throws -> GoalSuggestions {
```

Replace the `systemPrompt` block (lines 57-60):

```swift
        let systemPrompt = """
        You are a certified financial planner creating personalized financial goals. \
        Goals should be SMART (Specific, Measurable, Achievable, Relevant, Time-bound). \
        \(languageInstruction)Return ONLY valid JSON with no markdown formatting.
        """
```

With:

```swift
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
```

**Step 3: Update ReportGenerator to pass persona through**

In `ReportGenerator.swift`, change line 33:

```swift
    func generateMonthlyReport(year: Int, month: Int, language: String = "en") async throws -> FullReport {
```

To:

```swift
    func generateMonthlyReport(year: Int, month: Int, language: String = "en", persona: AdvisorPersona = .moderate) async throws -> FullReport {
```

Change line 47:

```swift
        let advice = try await advisor.analyzeSpendingHabits(report: report, trends: trends, language: language)
```

To:

```swift
        let advice = try await advisor.analyzeSpendingHabits(report: report, trends: trends, language: language, persona: persona)
```

Change line 51:

```swift
        let goals = try await goalPlanner.suggestGoals(report: report, advice: advice, language: language)
```

To:

```swift
        let goals = try await goalPlanner.suggestGoals(report: report, advice: advice, language: language, persona: persona)
```

**Step 4: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 5: Commit**

```bash
git add LedgeIt/PFM/FinancialAdvisor.swift LedgeIt/PFM/GoalPlanner.swift LedgeIt/PFM/ReportGenerator.swift
git commit -m "feat: wire AdvisorPersona through financial advice and goal planning pipeline"
```

---

### Task 3: Add Localization Strings for Advisor + Transaction Verification

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift`

**Step 1: Add new localization strings**

After the `// MARK: - Goals` section (after line 104), add:

```swift
    // MARK: - AI Advisor

    var aiAdvisor: String { s("AI Advisor", "AI 理財顧問") }
    var aiAdvisorSubtitle: String { s("Choose your financial planning style", "選擇您的理財風格") }
    var conservative: String { s("Conservative", "保守型") }
    var moderate: String { s("Moderate", "穩健型") }
    var aggressive: String { s("Aggressive", "積極型") }
    var custom: String { s("Custom", "自訂") }
    var conservativeDesc: String { s("Maximize savings, minimize risk", "最大化儲蓄，最小化風險") }
    var moderateDesc: String { s("Balanced lifestyle and savings", "平衡生活與儲蓄") }
    var aggressiveDesc: String { s("Growth-focused, higher risk tolerance", "成長導向，較高風險承受度") }
    var customDesc: String { s("Set your own targets", "設定您自己的目標") }
    var savingsTargetLabel: String { s("Savings Target", "儲蓄目標") }
    var riskLevel: String { s("Risk Level", "風險等級") }
    var riskLow: String { s("Low", "低") }
    var riskMedium: String { s("Medium", "中") }
    var riskHigh: String { s("High", "高") }
    var applyAndRegenerate: String { s("Apply & Regenerate Report", "套用並重新產生報告") }
    var currentAdvisor: String { s("Current Advisor", "目前顧問") }
    var categoryBudgets: String { s("Category Budget Hints", "類別預算參考") }
    var ofIncome: String { s("of income", "收入占比") }

    // MARK: - Transaction Verification

    var editTransaction: String { s("Edit Transaction", "編輯交易") }
    var amount: String { s("Amount", "金額") }
    var merchant: String { s("Merchant", "商家") }
    var category: String { s("Category", "類別") }
    var date: String { s("Date", "日期") }
    var type: String { s("Type", "類型") }
    var flagIncorrect: String { s("Flag as Incorrect", "標記為不正確") }
    var save: String { s("Save", "儲存") }
    var cancel: String { s("Cancel", "取消") }
    var highConfidence: String { s("High confidence", "高信心度") }
    var mediumConfidence: String { s("Medium confidence", "中信心度") }
    var lowConfidence: String { s("Low confidence", "低信心度") }
```

**Step 2: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/Utilities/Localization.swift
git commit -m "feat: add localization strings for AI advisor and transaction verification"
```

---

### Task 4: AI Advisor Settings View (New Sidebar Item)

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Analysis/AdvisorSettingsView.swift`
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:4-26,38-62,82-96`

**Step 1: Add `advisor` case to SidebarItem**

In `ContentView.swift`, add `advisor` case to the `SidebarItem` enum (after line 9, `case analysis = "Analysis"`):

```swift
    case advisor = "Advisor"
```

Add the icon in the `icon` computed property (after the `.analysis` case):

```swift
        case .advisor: return "brain.head.profile.fill"
```

**Step 2: Add sidebar entry and detail view routing**

In the sidebar `List`, inside the `Section(l10n.analysisSection)` block (after the analysis Label, line 54-55), add:

```swift
                    Label(l10n.aiAdvisor, systemImage: SidebarItem.advisor.icon)
                        .tag(SidebarItem.advisor)
```

In the detail `switch` statement (after the `case .analysis:` block, line 93), add:

```swift
                    case .advisor:
                        AdvisorSettingsView()
```

**Step 3: Add `aiAdvisor` to L10n sidebar section**

In `Localization.swift`, in the `// MARK: - Sidebar` section (after `var analysis`), add:

```swift
    var aiAdvisorSidebar: String { s("AI Advisor", "AI 顧問") }
```

Then use `l10n.aiAdvisorSidebar` instead of `l10n.aiAdvisor` in the sidebar Label above (to allow a shorter sidebar label).

**Step 4: Create AdvisorSettingsView**

Create `LedgeIt/LedgeIt/Views/Analysis/AdvisorSettingsView.swift`:

```swift
import SwiftUI

struct AdvisorSettingsView: View {
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    private var currentPersona: AdvisorPersona {
        AdvisorPersona.resolve(id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.aiAdvisor)
                        .font(.title2).fontWeight(.bold)
                    Text(l10n.aiAdvisorSubtitle)
                        .font(.callout).foregroundStyle(.secondary)
                }

                // Persona cards grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    personaCard(id: "conservative", icon: "shield.fill", color: .blue,
                                name: l10n.conservative, desc: l10n.conservativeDesc,
                                target: "30%")
                    personaCard(id: "moderate", icon: "scale.3d", color: .green,
                                name: l10n.moderate, desc: l10n.moderateDesc,
                                target: "20%")
                    personaCard(id: "aggressive", icon: "flame.fill", color: .orange,
                                name: l10n.aggressive, desc: l10n.aggressiveDesc,
                                target: "10%")
                    personaCard(id: "custom", icon: "slider.horizontal.3", color: .purple,
                                name: l10n.custom, desc: l10n.customDesc,
                                target: "\(Int(customSavingsTarget * 100))%")
                }

                // Custom configuration (only shown when custom is selected)
                if personaId == "custom" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.savingsTargetLabel)
                            .font(.subheadline).fontWeight(.semibold)

                        HStack {
                            Slider(value: $customSavingsTarget, in: 0.05...0.50, step: 0.05)
                            Text("\(Int(customSavingsTarget * 100))%")
                                .font(.title3).fontWeight(.bold).monospacedDigit()
                                .frame(width: 50)
                        }

                        Text(l10n.riskLevel)
                            .font(.subheadline).fontWeight(.semibold)

                        Picker(l10n.riskLevel, selection: $customRiskLevel) {
                            Text(l10n.riskLow).tag("low")
                            Text(l10n.riskMedium).tag("medium")
                            Text(l10n.riskHigh).tag("high")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                    .padding(16)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Budget hints preview
                VStack(alignment: .leading, spacing: 10) {
                    Label(l10n.categoryBudgets, systemImage: "chart.bar.fill")
                        .font(.headline)

                    let sortedHints = currentPersona.categoryBudgetHints.sorted { $0.value > $1.value }
                    ForEach(sortedHints, id: \.key) { category, maxPct in
                        HStack {
                            Text(CategoryStyle.style(forRawCategory: category).displayName)
                                .font(.callout)
                            Spacer()
                            Text("\(Int(maxPct * 100))% \(l10n.ofIncome)")
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .navigationTitle(l10n.aiAdvisor)
    }

    private func personaCard(id: String, icon: String, color: Color, name: String, desc: String, target: String) -> some View {
        Button {
            personaId = id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                    Text(target)
                        .font(.title3).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(color)
                }
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(personaId == id ? color.opacity(0.08) : Color.clear)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(personaId == id ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
```

**Step 5: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add LedgeIt/Views/Analysis/AdvisorSettingsView.swift LedgeIt/Views/ContentView.swift LedgeIt/Utilities/Localization.swift
git commit -m "feat: add AI Advisor settings view with persona selection"
```

---

### Task 5: Connect AnalysisDashboardView to Persona

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift:9,189-222,277-303`

**Step 1: Add persona resolution to AnalysisDashboardView**

In `AnalysisDashboardView.swift`, add these `@AppStorage` properties after line 9 (`@AppStorage("appLanguage")`):

```swift
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
```

Add a computed property after `l10n`:

```swift
    private var persona: AdvisorPersona {
        AdvisorPersona.resolve(id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }
```

**Step 2: Pass persona in generateReport()**

In the `generateReport()` function, change:

```swift
                report = try await generator.generateMonthlyReport(year: year, month: month, language: appLanguage)
```

To:

```swift
                report = try await generator.generateMonthlyReport(year: year, month: month, language: appLanguage, persona: persona)
```

**Step 3: Add persona-aware coloring to categoryInsightsSection**

In `categoryInsightsSection`, replace the `HStack` that shows the category name (lines 197-201):

```swift
                    HStack {
                        Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                            .font(.callout).fontWeight(.semibold)
                        Spacer()
                    }
```

With:

```swift
                    HStack {
                        Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                            .font(.callout).fontWeight(.semibold)
                        Spacer()
                        if let budgetPct = persona.categoryBudgetHints[insight.category] {
                            Text("\(Int(budgetPct * 100))% max")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(budgetStatusColor(category: insight.category).opacity(0.15))
                                .foregroundStyle(budgetStatusColor(category: insight.category))
                                .clipShape(Capsule())
                        }
                    }
```

Add this helper function after the `healthScoreColor` function:

```swift
    private func budgetStatusColor(category: String) -> Color {
        guard let report,
              let budgetPct = persona.categoryBudgetHints[category] else { return .secondary }

        let income = report.monthlyReport.totalIncome
        guard income > 0 else { return .secondary }

        let budgetLimit = income * budgetPct
        let actual = report.monthlyReport.categoryBreakdown.first { $0.category == category }?.amount ?? 0

        if actual <= budgetLimit * 0.8 { return .green }
        if actual <= budgetLimit { return .yellow }
        return .red
    }
```

**Step 4: Update savingsTarget reference line to use persona**

In `savingsTrendChart`, change the `RuleMark`:

```swift
            RuleMark(y: .value("Target", 20))
```

To:

```swift
            RuleMark(y: .value("Target", persona.savingsTarget * 100))
```

And change the caption text from `l10n.savingsTarget` to a dynamic string. Replace:

```swift
            Text(l10n.savingsTarget)
                .font(.caption).foregroundStyle(.tertiary)
```

With:

```swift
            Text(l10n.savingsTarget.replacingOccurrences(of: "20%", with: "\(Int(persona.savingsTarget * 100))%"))
                .font(.caption).foregroundStyle(.tertiary)
```

**Step 5: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add LedgeIt/Views/Analysis/AnalysisDashboardView.swift
git commit -m "feat: connect analysis dashboard to advisor persona for contextual display"
```

---

### Task 6: Transaction Confidence Badges + Inline Editing

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/TransactionListView.swift`
- Modify: `LedgeIt/LedgeIt/Views/TransactionDetailView.swift`

**Step 1: Add confidence badge to TransactionRow**

In `TransactionListView.swift`, modify the `TransactionRow` struct (lines 132-161). Replace the entire struct:

```swift
private struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 8) {
            // Confidence indicator
            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)

            if let category = transaction.category {
                CategoryIcon(category: category, size: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.merchant ?? "Unknown Merchant")
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let date = transaction.transactionDate {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let category = transaction.category {
                        CategoryBadge(category: category)
                    }
                }
            }
            Spacer(minLength: 8)
            AmountText(amount: transaction.amount, currency: transaction.currency, type: transaction.type)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            (transaction.confidence ?? 1.0) < 0.7
                ? Color.yellow.opacity(0.06)
                : Color.clear
        )
    }

    private var confidenceColor: Color {
        let conf = transaction.confidence ?? 1.0
        if conf >= 0.8 { return .green }
        if conf >= 0.5 { return .yellow }
        return .red
    }
}
```

**Step 2: Add inline editing to TransactionDetailView**

Replace the entire content of `TransactionDetailView.swift`:

```swift
import SwiftUI

struct TransactionDetailView: View {
    let transaction: Transaction
    @State private var isEditing = false
    @State private var editAmount: String = ""
    @State private var editMerchant: String = ""
    @State private var editCategory: String = ""
    @State private var editDate: String = ""
    @State private var editType: String = ""
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    private let categories = AutoCategorizer.LeanCategory.allCases.map(\.rawValue)
    private let types = ["debit", "credit", "transfer"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.merchant ?? "Transaction")
                            .font(.title3)
                            .fontWeight(.bold)
                        if let date = transaction.transactionDate {
                            Text(date)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 8) {
                        confidenceBadge
                        AmountText(amount: transaction.amount, currency: transaction.currency, type: transaction.type)
                            .font(.title3)
                    }
                }

                Divider()

                if isEditing {
                    editForm
                } else {
                    detailContent
                }
            }
            .padding(20)
        }
        .frame(minWidth: 280, maxWidth: .infinity)
        .toolbar {
            Button(isEditing ? l10n.cancel : l10n.editTransaction) {
                if isEditing {
                    isEditing = false
                } else {
                    startEditing()
                }
            }
        }
    }

    // MARK: - Confidence Badge

    private var confidenceBadge: some View {
        let conf = transaction.confidence ?? 1.0
        let color: Color = conf >= 0.8 ? .green : conf >= 0.5 ? .yellow : .red
        let label = conf >= 0.8 ? l10n.highConfidence : conf >= 0.5 ? l10n.mediumConfidence : l10n.lowConfidence

        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Detail Content (read-only)

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let category = transaction.category {
                detailRow(l10n.category) {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 28)
                        CategoryBadge(category: category)
                    }
                }
            }
            if let type = transaction.type {
                detailRow(l10n.type, value: type.capitalized)
            }
            detailRow("Currency", value: transaction.currency)
            if let transferType = transaction.transferType {
                detailRow("Transfer Type", value: transferType)
            }

            if let description = transaction.description, !description.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(description)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Edit Form

    private var editForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldGroup(l10n.amount) {
                TextField("0.00", text: $editAmount)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.merchant) {
                TextField("Merchant name", text: $editMerchant)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.category) {
                Picker(l10n.category, selection: $editCategory) {
                    ForEach(categories, id: \.self) { cat in
                        Text(CategoryStyle.style(forRawCategory: cat).displayName).tag(cat)
                    }
                }
            }
            fieldGroup(l10n.date) {
                TextField("YYYY-MM-DD", text: $editDate)
                    .textFieldStyle(.roundedBorder)
            }
            fieldGroup(l10n.type) {
                Picker(l10n.type, selection: $editType) {
                    ForEach(types, id: \.self) { t in
                        Text(t.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(spacing: 12) {
                Button(l10n.save) {
                    saveEdits()
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    flagAsIncorrect()
                } label: {
                    Label(l10n.flagIncorrect, systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func startEditing() {
        editAmount = String(format: "%.2f", transaction.amount)
        editMerchant = transaction.merchant ?? ""
        editCategory = transaction.category ?? "GENERAL"
        editDate = transaction.transactionDate ?? ""
        editType = transaction.type ?? "debit"
        isEditing = true
    }

    private func saveEdits() {
        guard let txId = transaction.id else { return }
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var tx = try Transaction.fetchOne(db, key: txId) {
                    if let newAmount = Double(editAmount) { tx.amount = newAmount }
                    tx.merchant = editMerchant.isEmpty ? nil : editMerchant
                    tx.category = editCategory
                    tx.transactionDate = editDate.isEmpty ? nil : editDate
                    tx.type = editType
                    try tx.update(db)
                }
            }
            isEditing = false
        }
    }

    private func flagAsIncorrect() {
        guard let txId = transaction.id else { return }
        Task {
            try? await AppDatabase.shared.db.write { db in
                if var tx = try Transaction.fetchOne(db, key: txId) {
                    tx.confidence = 0
                    try tx.update(db)
                }
            }
            isEditing = false
        }
    }

    private func fieldGroup<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary).fontWeight(.medium)
            content()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        detailRow(label) {
            Text(value).fontWeight(.medium)
        }
    }

    private func detailRow<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value()
        }
        .font(.callout)
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/Views/TransactionListView.swift LedgeIt/Views/TransactionDetailView.swift
git commit -m "feat: add confidence badges to transactions and inline editing in detail view"
```

---

### Task 7: Final Integration Build & Test

**Step 1: Clean build**

```bash
cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt
swift package clean && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 2: Build and launch as standalone app**

```bash
./build.sh --run
```
Expected: LedgeIt launches with its own Dock icon.

**Step 3: Verify all features**

1. **AI Advisor sidebar**: New "AI Advisor" item appears in Analysis section between Financial Analysis and Goals
2. **Persona selection**: Click AI Advisor → 4 persona cards shown in 2x2 grid. Click each to select. Custom shows slider + picker.
3. **Budget hints**: Preview section updates when persona changes
4. **Report generation**: Click Financial Analysis → Generate Report → advice tone matches selected persona
5. **Savings target line**: Chart dashed line matches persona's savings target %
6. **Category coloring**: Category insights show budget status badges (green/yellow/red)
7. **Transaction confidence**: Click Transactions → each row has a small colored dot (confidence indicator)
8. **Low-confidence highlight**: Transactions with confidence < 0.7 have subtle yellow background
9. **Inline edit**: Click a transaction → detail panel shows confidence badge → click Edit → form appears → edit fields → Save
10. **Flag incorrect**: Click Edit → "Flag as Incorrect" button → sets confidence to 0

**Step 4: Commit any final adjustments if needed**
