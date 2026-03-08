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

AI Provider Layer (AnyLanguageModel + SessionFactory)
  ├── OpenAILanguageModel (OpenAI, OpenRouter, Ollama, Groq, etc.)
  ├── AnthropicLanguageModel (direct Anthropic API)
  ├── GeminiLanguageModel (Google Gemini API)
  └── AIProviderConfigStore (UserDefaults + Keychain)
```

## Code Conventions

- **ALL code, comments, docstrings, prompts, variables, and error messages MUST be in English** — no Chinese characters in code files
- Swift 6.2, SwiftUI, macOS 15+
- Database: SQLite via GRDB 7.0
- Secrets: macOS Keychain (API keys per provider, Google OAuth credentials)
- LLM: Multi-provider via AnyLanguageModel + SessionFactory (OpenAI-compatible, Anthropic, Google Gemini)
- Package Manager: Swift Package Manager

## AI Provider Architecture

- **AnyLanguageModel** (v0.7+) — third-party framework providing unified multi-provider LLM API
- **SessionFactory** — creates `LanguageModelSession` instances based on `AIProviderConfiguration`
  - `makeSession(assignment:config:tools:instructions:)` → `LanguageModelSession`
  - `makeModel(assignment:config:)` → `any LanguageModel` (for custom session construction)
- **LanguageModelSession** — AnyLanguageModel's session manager with automatic tool-calling loop and transcript management
  - `session.respond(to:options:)` for text, `session.respond(to:image:options:)` for multimodal
  - `session.streamResponse(to:)` for streaming
  - `GenerationOptions(temperature:)` for temperature control
- **Tool protocol + @Generable macro** — type-safe tool definitions (see `LedgeIt/Services/Tools/`)
- **DynamicTool** — runtime tool definitions using `DynamicGenerationSchema` for plugin-style registration
- **ChatToolExecutionDelegate** — observes tool calls for `.toolCallStarted` events in ChatEngine
- **AIProviderConfigStore** — persists provider config in UserDefaults, API keys in Keychain
- Users can add multiple OpenAI-compatible endpoints (OpenAI, OpenRouter, Ollama, Groq, etc.)
- Each use case (classification, extraction, statement, chat) can use a different provider + model

## Key Dependencies

**Swift**: GRDB 7.0 (SQLite), swift-embeddings (ML embeddings), AnyLanguageModel 0.7+ (multi-provider LLM), Google OAuth 2.0, Gmail API, Google Calendar API
