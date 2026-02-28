# Multi-Persona Financial Advisor System Design

**Date**: 2026-02-28
**Status**: Approved

## Overview

Replace the single generic financial advisor with a multi-persona system: 3 preset advisor types (Conservative, Moderate, Aggressive) + 1 user-customizable advisor. Each persona affects the full pipeline: AI advice tone, goal suggestions, and dashboard spending highlights. Additionally, add inline transaction verification so users can confirm/correct LLM-extracted data.

## Advisor Personas

### Preset Personas

| Persona | Savings Target | Risk Level | Philosophy |
|---------|---------------|------------|------------|
| Conservative (保守型) | 30%+ | Low | Minimize discretionary spending, maximize emergency fund, avoid all debt, prioritize capital preservation |
| Moderate (穩健型) | 20% | Medium | Balance lifestyle and savings, steady growth, diversified approach, moderate risk tolerance |
| Aggressive (積極型) | 10% | High | Maximize growth and ROI, invest heavily, tolerate higher spending if it generates income, aggressive debt leverage |

### Custom Persona (自訂)

User configures two inputs:
- **Savings target**: slider 5%-50%, stored as `Double`
- **Risk level**: picker Low / Medium / High

System generates a persona description from these inputs to pass to the LLM.

### Data Model

```swift
struct AdvisorPersona: Codable, Sendable {
    let id: String                    // "conservative", "moderate", "aggressive", "custom"
    let name: String                  // Display name (localized)
    let savingsTarget: Double         // 0.10 - 0.50
    let riskLevel: String             // "low", "medium", "high"
    let spendingPhilosophy: String    // Text injected into LLM system prompt
    let categoryBudgetHints: [String: Double]  // Category → max % of income
}
```

Storage: `@AppStorage("advisorPersonaId")` for selected persona ID. Custom persona parameters stored in `@AppStorage("customSavingsTarget")` and `@AppStorage("customRiskLevel")`.

## Pipeline Integration

### 1. FinancialAdvisor (Advice Generation)

The system prompt gains a persona section:

```
You are a [PERSONA_NAME] financial planner.
Philosophy: [SPENDING_PHILOSOPHY]
Target savings rate: [SAVINGS_TARGET]%
Risk tolerance: [RISK_LEVEL]

Evaluate spending against these standards. A [PERSONA] advisor would...
```

This changes the tone, severity of warnings, and nature of action items.

### 2. GoalPlanner (Goal Suggestions)

Persona affects goal priorities:
- **Conservative**: Emergency fund first, debt elimination, insurance review
- **Moderate**: Balanced savings/investment, moderate spending reduction
- **Aggressive**: Investment goals first, income growth, leverage opportunities

The system prompt includes persona context so goals align with the advisor's philosophy.

### 3. Dashboard Display

Category spending cards show color-coded indicators relative to the persona's budget hints:
- Green: within persona's recommended range
- Yellow: 80-100% of recommended limit
- Red: exceeding recommended limit

The `categoryBudgetHints` dict maps category names to max percentage of income. For example, conservative might set `ENTERTAINMENT: 0.05` (5% max) while aggressive sets `ENTERTAINMENT: 0.15` (15%).

### 4. SpendingAnalyzer

The analyzer itself doesn't change (it's pure SQL math). But the `MonthlyReport` is displayed differently based on persona thresholds.

## Transaction Verification (Inline Edit)

### Confidence Display

Each transaction in `TransactionListView` shows:
- **Confidence badge**: colored dot (green >= 0.8, yellow 0.5-0.8, red < 0.5) using the existing `confidence` field
- Low-confidence transactions (< 0.7) get a subtle yellow background highlight

### Inline Editing

Tapping a transaction expands it to show editable fields:
- Amount (TextField)
- Merchant (TextField)
- Category (Picker with all LeanCategory values)
- Date (DatePicker)
- Type (Picker: debit/credit/transfer)
- "Flag as Incorrect" button (sets confidence to 0, marks for re-review)

Changes save directly to the database. No separate review queue needed.

## New Sidebar Item: AI Advisor

Add "AI Advisor" (AI 理財顧問) to the Analysis section in the sidebar, between "Financial Analysis" and "Goals".

### AI Advisor View Layout

Top section: 4 persona cards in a 2x2 grid:
- Each card shows: icon, persona name, savings target, one-line philosophy
- Selected card has a highlighted border
- Custom card shows the slider/picker controls when selected

Bottom section: Preview of how the selected persona affects analysis:
- Key metrics: target savings rate, risk tolerance level
- Category budget hints preview (if applicable)

"Apply & Regenerate Report" button at the bottom.

## Files Affected

**New files:**
- `LedgeIt/PFM/AdvisorPersona.swift` — persona model and preset definitions
- `LedgeIt/Views/Analysis/AdvisorSettingsView.swift` — new sidebar view

**Modified files:**
- `LedgeIt/PFM/FinancialAdvisor.swift` — accept persona parameter, modify prompts
- `LedgeIt/PFM/GoalPlanner.swift` — accept persona parameter, modify prompts
- `LedgeIt/PFM/ReportGenerator.swift` — pass persona through generation chain
- `LedgeIt/Views/Analysis/AnalysisDashboardView.swift` — persona-aware category coloring
- `LedgeIt/Views/Analysis/GoalsView.swift` — minor: show persona context on goals
- `LedgeIt/Views/ContentView.swift` — add AI Advisor sidebar item
- `LedgeIt/Views/TransactionListView.swift` — confidence badges + inline edit
- `LedgeIt/Utilities/Localization.swift` — new translated strings
