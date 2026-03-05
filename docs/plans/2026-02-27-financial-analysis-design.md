# Financial Analysis & AI Advisory System Design

**Date**: 2026-02-27
**Status**: Approved

## Overview

Extend the existing LedgeIt macOS App with financial analysis, AI-powered advisory, and goal planning capabilities. All new functionality is implemented as Swift modules within the existing `PFM/` directory, using the existing OpenRouter LLM integration.

## Architecture

### Data Flow

```
Gmail Sync (existing)
    |
    v
Intent Classifier (existing) -> Filter financial emails
    |
    v
Extraction Pipeline (existing) -> Extract transaction data
    |
    +-- PDFExtractor (NEW) <- Parse PDF attachments for bills/transactions
    |
    v
SQLite Database (existing: transactions, credit_card_bills)
    |
    +-- SpendingAnalyzer (NEW) -> Statistical analysis of spending behavior
    |       |                     (monthly trends, category breakdown, anomaly detection)
    |       v
    +-- FinancialAdvisor (NEW) -> LLM advisory engine
    |       |                     (professional CFP perspective on spending habits)
    |       v
    +-- GoalPlanner (NEW)     -> AI short/long-term goal suggestions
            |                     (savings goals, budget control, investment direction)
            v
    ReportGenerator (NEW)     -> Consolidated report output
            |
            v
    Dashboard Views (NEW)     -> SwiftUI presentation
            |
            v
    Google Calendar (existing) -> Sync important financial events/due dates
```

### New Modules

| Module | Responsibility | Data Source |
|--------|---------------|-------------|
| **PDFExtractor** | Parse PDF attachments using PDFKit, extract bill details and transactions | `attachments` table |
| **SpendingAnalyzer** | Pure computation: monthly stats, category distribution, trends, anomaly detection | `transactions` table |
| **FinancialAdvisor** | LLM-powered spending habit evaluation from professional CFP perspective | SpendingAnalyzer output |
| **GoalPlanner** | LLM-generated short-term (1-3 months) and long-term (1-3 years) financial goals | FinancialAdvisor assessment + spending data |
| **ReportGenerator** | Combine all analysis results into structured reports | All upstream modules |

## Module Details

### 1. PDFExtractor

**Location**: `PFM/PDFExtractor.swift`

Uses Apple PDFKit (no external dependencies) to extract text from PDF email attachments, then sends financial-related text to LLM for structured data extraction.

**Flow**: Gmail attachment download -> PDFKit text extraction -> Financial relevance check -> LLM structured extraction -> Write to transactions/credit_card_bills

**Integration**: Called within the existing `ExtractionPipeline` when processing emails with PDF attachments.

```swift
struct PDFExtractor {
    func extractText(from pdfData: Data) -> String
    func extractFinancialData(text: String) async throws -> [ExtractedTransaction]
}
```

### 2. SpendingAnalyzer

**Location**: `PFM/SpendingAnalyzer.swift`

Pure computation module (no LLM calls). Queries SQLite to produce statistical analysis.

```swift
struct SpendingAnalyzer {
    func monthlyBreakdown(year: Int, month: Int) -> MonthlyReport
    func categoryDistribution(from: Date, to: Date) -> [CategoryStat]
    func spendingTrend(months: Int) -> [MonthTrend]
    func detectAnomalies(from: Date, to: Date) -> [AnomalyAlert]
    func topMerchants(from: Date, to: Date, limit: Int) -> [MerchantStat]
}

struct MonthlyReport {
    let totalSpending: Decimal
    let totalIncome: Decimal
    let savingsRate: Double
    let categoryBreakdown: [CategoryStat]
    let topMerchants: [MerchantStat]
    let anomalies: [AnomalyAlert]
}
```

### 3. FinancialAdvisor

**Location**: `PFM/FinancialAdvisor.swift`

Uses OpenRouter LLM to analyze spending habits from a professional Taiwan CFP perspective. Considers local cost of living, savings rate benchmarks, and insurance coverage.

```swift
struct FinancialAdvisor {
    let llmProcessor: LLMProcessor
    func analyzeSpendingHabits(report: MonthlyReport) async throws -> SpendingAdvice
    func evaluateHealthiness(report: MonthlyReport) async throws -> HealthScore
}

struct SpendingAdvice {
    let overallAssessment: String
    let positiveHabits: [String]
    let concerns: [String]
    let actionItems: [String]
    let healthScore: Int              // 0-100
}
```

### 4. GoalPlanner

**Location**: `PFM/GoalPlanner.swift`

LLM-powered goal suggestion engine. First version is AI-only suggestions; user-defined goals will be added later.

```swift
struct GoalPlanner {
    let llmProcessor: LLMProcessor
    func suggestGoals(
        report: MonthlyReport,
        advice: SpendingAdvice,
        existingGoals: [FinancialGoal]
    ) async throws -> GoalSuggestions
}

struct GoalSuggestions {
    let shortTerm: [GoalSuggestion]   // 1-3 months
    let longTerm: [GoalSuggestion]    // 1-3 years
}

struct GoalSuggestion {
    let title: String
    let description: String
    let targetAmount: Decimal?
    let targetDate: Date?
    let category: GoalCategory        // savings, budget, investment, debt
    let reasoning: String
}
```

### 5. ReportGenerator

**Location**: `PFM/ReportGenerator.swift`

Orchestrates the full analysis pipeline and persists results.

```swift
struct ReportGenerator {
    func generateMonthlyReport(year: Int, month: Int) async throws -> FinancialReport
    func runFullAnalysis(year: Int, month: Int) async throws -> FinancialReport
}
```

## Database Schema Changes

### New Tables

```sql
CREATE TABLE financial_reports (
    id TEXT PRIMARY KEY,
    report_type TEXT NOT NULL,        -- 'monthly' | 'quarterly' | 'yearly'
    period_start TEXT NOT NULL,
    period_end TEXT NOT NULL,
    summary_json TEXT NOT NULL,
    advice_json TEXT NOT NULL,
    goals_json TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE financial_goals (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL,               -- 'short_term' | 'long_term'
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    target_amount REAL,
    target_date TEXT,
    category TEXT,                    -- 'savings' | 'budget' | 'investment' | 'debt'
    status TEXT DEFAULT 'suggested',  -- 'suggested' | 'accepted' | 'completed' | 'dismissed'
    progress REAL DEFAULT 0,
    created_at TEXT NOT NULL
);
```

## New UI Views

```
Views/Analysis/
    AnalysisDashboardView.swift   -- Analysis overview page
    SpendingReportView.swift      -- Spending report (charts + statistics)
    AdviceCardView.swift          -- Financial advice cards
    GoalsView.swift               -- Goals list with progress tracking
```

## Technology Choices

- **PDF Parsing**: Apple PDFKit (native, no external dependencies)
- **LLM Provider**: OpenRouter (existing integration via LLMProcessor)
- **Database**: SQLite via GRDB (existing)
- **Charts**: Swift Charts (native)
- **Calendar**: Google Calendar API (existing integration)

## Team Structure (Claude Code Agents)

Five parallel agents for implementation:

1. **pdf-parser** -- PDFExtractor module + ExtractionPipeline integration
2. **spending-analyzer** -- SpendingAnalyzer module + DB migration for financial_reports
3. **ai-advisor** -- FinancialAdvisor + GoalPlanner modules + DB migration for financial_goals
4. **report-engine** -- ReportGenerator orchestration + integration tests
5. **ui-views** -- All new SwiftUI views under Views/Analysis/
