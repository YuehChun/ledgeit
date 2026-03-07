# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**LedgeIt** — a native macOS app for personal finance management. Automatically extracts financial transactions from Gmail, classifies them with AI (multi-provider: OpenAI-compatible, Anthropic, Google), and provides dashboards, AI advisory, goal tracking, and calendar integration.

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
  ├── LLMProcessor (AI classification + extraction via SessionFactory)
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
  ├──► ChatEngine + SessionFactory (streaming + tool calling) ──► ChatView
  └──► MCPServer (stdio JSON-RPC) ──► Third-party AI agents

AI Provider Layer (SessionFactory)
  ├── OpenAICompatibleSession (OpenAI, OpenRouter, Ollama, Groq, etc.)
  ├── AnthropicSession (SwiftAgent built-in)
  ├── GoogleSession (Gemini API)
  └── AIProviderConfigStore (UserDefaults + Keychain)
```

## Code Conventions

- **ALL code, comments, docstrings, prompts, variables, and error messages MUST be in English** — no Chinese characters in code files
- Swift 6.2, SwiftUI, macOS 26+
- Database: SQLite via GRDB 7.0
- Secrets: macOS Keychain (API keys per provider, Google OAuth credentials)
- LLM: Multi-provider via SessionFactory (OpenAI-compatible, Anthropic, Google Gemini)
- Package Manager: Swift Package Manager

## AI Provider Architecture

- **SessionFactory** creates the right session based on `AIProviderConfiguration`
- **OpenAICompatibleSession** — supports any OpenAI API-compatible endpoint (configurable base URL + optional API key)
- **GoogleSession** — Google Gemini API adapter
- **AnthropicSession** — SwiftAgent built-in (via OpenAI-compatible proxy for now)
- **AIProviderConfigStore** — persists provider config in UserDefaults, API keys in Keychain
- **LLMTypes.swift** — shared types: `LLMMessage`, `LLMToolDefinition`, `LLMToolCall`, `LLMStreamEvent`
- Users can add multiple OpenAI-compatible endpoints (OpenAI, OpenRouter, Ollama, Groq, etc.)
- Each use case (classification, extraction, statement, chat) can use a different provider + model

## Key Dependencies

**Swift**: GRDB 7.0 (SQLite), [SwiftAgent (AI session framework)](https://github.com/SwiftedMind/SwiftAgent), Google OAuth 2.0, Gmail API, Google Calendar API
