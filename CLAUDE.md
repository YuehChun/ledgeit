# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LedgeIt** — a native macOS app for personal finance management. Automatically extracts financial transactions from Gmail, classifies them with AI (via OpenRouter), and provides dashboards, AI advisory, goal tracking, and calendar integration.

## Commands

### Build & Run (from `LedgeIt/`)
```bash
swift build              # build
swift run                # run
bash build.sh            # build .app bundle
```

## Architecture

```
Gmail API
  │
  ▼
SyncService ──► emails table (SQLite)
  │
  ▼
ExtractionPipeline
  ├── IntentClassifier (rule-based accept/reject/uncertain)
  ├── LLMProcessor (AI classification + extraction via OpenRouter)
  ├── AutoCategorizer (merchant → category mapping)
  ├── TransferDetector (inter-account transfer identification)
  └── Deduplication (amount + currency + date)
  │
  ▼
transactions table ──► DashboardView, CalendarView, TransactionListView
credit_card_bills table ──► DashboardView (upcoming bills), CalendarView (due dates)
  │
  ├──► CalendarService ──► Google Calendar (payment events)
  ├──► SpendingAnalyzer + ReportGenerator ──► AnalysisDashboardView
  ├──► FinancialAdvisor + GoalPlanner ──► GoalsView
  ├──► PromptOptimizer ──► AdvisorSettingsView (version-controlled prompts)
  │
  ▼
FinancialQueryService (shared query layer)
  ├──► ChatEngine + OpenRouter (streaming + tool calling) ──► ChatView
  └──► MCPServer (stdio JSON-RPC) ──► Third-party AI agents
```

## Code Conventions

- **ALL code, comments, docstrings, prompts, variables, and error messages MUST be in English** — no Chinese characters in code files
- Swift 6.0, SwiftUI, macOS 14+
- Database: SQLite via GRDB 7.0
- Secrets: macOS Keychain (OpenRouter API key, Google OAuth credentials)
- LLM: OpenRouter API (Claude, GPT, etc.)
- Package Manager: Swift Package Manager

## Key Dependencies

**Swift**: GRDB 7.0 (SQLite), OpenRouter API, Google OAuth 2.0, Gmail API, Google Calendar API
