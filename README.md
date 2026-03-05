# LedgeIt

A native macOS app that automatically extracts financial transactions from your Gmail, classifies them with AI, and presents them in a personal finance dashboard with AI-powered advisory, goal tracking, and calendar integration.

## User Stories

### [Where Did My Money Go This Month?](docs/user-stories/where-did-my-money-go.md)

See your complete financial picture at a glance — spending, income, upcoming bills, category breakdown, and trends.

![Dashboard](screenshots/dashboard.png)

---

### [Can I Afford a Trip?](docs/user-stories/can-i-afford-a-trip.md)

Ask your finances questions in plain language. The AI searches your transaction data using local RAG (hybrid semantic + keyword search) and gives answers grounded in real numbers.

![AI Advisory Chat](screenshots/ai_advisor_chatting.png)

---

### [Am I Financially Healthy?](docs/user-stories/am-i-financially-healthy.md)

Get an AI-generated financial health score with category insights, warning flags, and actionable recommendations.

![Financial Analysis](screenshots/financial_analysis.png)

---

### [Help Me Save Money](docs/user-stories/help-me-save-money.md)

AI-suggested financial goals based on your spending patterns, with progress tracking and accept/dismiss workflow.

![Financial Goals](screenshots/financial_goal.png)

---

### [Import My Credit Card PDF](docs/user-stories/import-my-credit-card-pdf.md)

Decrypt and parse password-protected credit card PDFs. Extract dozens of transactions in one click with smart deduplication.

![Statement Parser](screenshots/statements_parser.png)

---

### [Did the AI Get It Right?](docs/user-stories/did-the-ai-get-it-right.md)

Review AI-extracted transactions grouped by source email. Verify accuracy, correct mistakes, and approve before they affect your reports.

![Transaction Review](screenshots/transactions_review.png)

---

### [The Advisor Is Too Strict](docs/user-stories/the-advisor-is-too-strict.md)

Customize your AI financial advisor's persona, budget limits, and behavior with natural language feedback and version-controlled prompts.

![AI Advisor Tuning](screenshots/ai_advisor_tuning.png)

---

## What It Does

1. **Syncs Gmail** — Fetches emails via Gmail API (OAuth 2.0, read-only)
2. **AI Classification** — Rule-based filter + LLM fallback (via OpenRouter) to identify financial emails
3. **Transaction Extraction** — Extracts merchant, amount, currency, date from receipts, invoices, and bank notifications
4. **Credit Card Bills** — Detects statement emails and tracks due dates / amounts owed
5. **Auto-Categorization** — 15 spending categories with subcategories (food, transport, utilities, etc.)
6. **Smart Deduplication** — Rule-based fuzzy matching + LLM tiebreaker to prevent duplicate transactions across email and PDF statement imports
7. **Bill Reconciliation** — Automatically detects overlap between credit card bill totals and individual transactions
8. **Financial Analysis** — AI-powered spending analysis with health scores, category insights, and savings rate trends
9. **AI Advisor** — Multi-persona financial advisor (conservative / moderate / aggressive / custom) with iterative prompt optimization
10. **Financial Goals** — AI-suggested goals with progress tracking, accept/dismiss workflow, and progress sliders (language-aware)
11. **Prompt Version Control** — Version-tracked advisor prompts with user feedback → LLM optimization loop
12. **Transaction Verification** — Edit and flag AI-extracted transactions for accuracy
13. **Calendar Sync** — Creates Google Calendar events for each transaction
14. **Auto-Sync** — Background sync every 15 minutes when the app is running
15. **AI Chat** — Natural language chat interface with local RAG (multilingual embeddings + FTS5 hybrid search) and tool calling
16. **MCP Server** — Model Context Protocol (stdio) server exposing financial data to third-party AI agents (e.g., Claude Desktop)
17. **PDF Statement Import** — Decrypt and parse password-protected credit card PDFs with multi-layer LLM extraction
18. **AI Progress UX** — Animated progress indicators with step-by-step checklists for all AI operations
19. **Bilingual** — Full English and Traditional Chinese (繁體中文) support for UI and AI-generated content

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via [GRDB](https://github.com/groue/GRDB.swift) 7.0 |
| AI/LLM | [OpenRouter](https://openrouter.ai) API (Claude, GPT, etc.) |
| Embeddings | multilingual-e5-small (local, on-device) |
| Vector Search | sqlite-vec + FTS5 hybrid search |
| Auth | Google OAuth 2.0 (Desktop app flow) |
| Package Manager | Swift Package Manager |
| Secrets | macOS Keychain |

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
  ├── LLMProcessor (AI classification + extraction for uncertain emails)
  ├── AutoCategorizer (merchant → category mapping)
  ├── TransferDetector (inter-account transfer identification)
  ├── DeduplicationService (fuzzy matching + LLM tiebreaker)
  └── BillReconciler (bill vs transaction overlap detection)
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
EmbeddingService (multilingual-e5-small + sqlite-vec + FTS5)
  │
  ▼
FinancialQueryService (shared query layer)
  ├──► ChatEngine + OpenRouter (streaming + tool calling) ──► ChatView
  └──► MCPServer (stdio JSON-RPC) ──► Third-party AI agents
```

### AI Advisor Flow

```
User selects persona (conservative/moderate/aggressive/custom)
  │
  ├──► Apply & Regenerate ──► GoalPlanner ──► new AI-suggested goals
  │
  └──► User feedback ──► PromptOptimizer (LLM) ──► optimized prompt preview
         │
         └──► Apply ──► save PromptVersion to DB ──► regenerate goals
```

## Project Structure

```
LedgeIt/
├── LedgeIt/
│   ├── LedgeItApp.swift              # App entry point
│   ├── Database/
│   │   ├── AppDatabase.swift         # GRDB database setup
│   │   └── DatabaseMigrations.swift  # Schema migrations (v1-v14)
│   ├── Models/
│   │   ├── Email.swift
│   │   ├── Transaction.swift
│   │   ├── CreditCardBill.swift
│   │   ├── CalendarEvent.swift
│   │   ├── Attachment.swift
│   │   ├── SyncState.swift
│   │   ├── FinancialReport.swift     # AI analysis reports
│   │   ├── FinancialGoal.swift       # Goal tracking
│   │   ├── PromptVersion.swift       # Prompt version control
│   │   ├── ChatMessage.swift         # Chat message types + stream events
│   │   └── QueryTypes.swift          # Shared query filters & summaries
│   ├── PFM/                          # Personal Finance Management
│   │   ├── ExtractionPipeline.swift  # Main processing orchestrator
│   │   ├── IntentClassifier.swift    # Rule-based email filtering
│   │   ├── LLMProcessor.swift        # OpenRouter AI calls
│   │   ├── AutoCategorizer.swift     # Merchant categorization
│   │   ├── TransferDetector.swift    # Transfer identification
│   │   ├── PFMConfig.swift           # Thresholds & trusted institutions
│   │   ├── SpendingAnalyzer.swift    # Spending pattern analysis
│   │   ├── ReportGenerator.swift     # AI financial report generation
│   │   ├── FinancialAdvisor.swift    # Multi-persona advisor engine
│   │   ├── GoalPlanner.swift         # AI goal suggestion & planning
│   │   ├── AdvisorPersona.swift      # Persona definitions & resolution
│   │   ├── PromptOptimizer.swift     # LLM-based prompt refinement
│   │   ├── PDFExtractor.swift        # PDF document parsing
│   │   ├── DeduplicationService.swift # Smart dedup (fuzzy + LLM)
│   │   └── BillReconciler.swift      # Bill vs transaction reconciliation
│   ├── Services/
│   │   ├── GmailService.swift        # Gmail REST API client
│   │   ├── GoogleAuthService.swift   # OAuth 2.0 flow
│   │   ├── SyncService.swift         # Email sync orchestration
│   │   ├── CalendarService.swift     # Google Calendar API
│   │   ├── OpenRouterService.swift   # LLM API client (streaming + tool calling)
│   │   ├── PersonalFinanceService.swift # Dashboard data queries
│   │   ├── KeychainService.swift     # Secure credential storage
│   │   ├── PDFParserService.swift    # PDF text extraction
│   │   ├── StatementService.swift    # PDF statement decrypt + extract pipeline
│   │   ├── GoalGenerationService.swift # Background goal generation
│   │   ├── EmbeddingService.swift    # Multilingual embeddings + hybrid search
│   │   ├── ChatEngine.swift          # AI chat with tool-calling loop
│   │   └── FinancialQueryService.swift # Shared query layer for chat & MCP
│   ├── Views/
│   │   ├── ContentView.swift         # Sidebar + auto-sync
│   │   ├── DashboardView.swift       # Financial dashboard
│   │   ├── TransactionListView.swift # Transactions table
│   │   ├── TransactionDetailView.swift # Transaction edit/verify
│   │   ├── EmailListView.swift       # Email inbox
│   │   ├── CalendarView.swift        # Calendar with bill markers
│   │   ├── SettingsView.swift        # Credentials & sync controls
│   │   ├── Chat/
│   │   │   ├── ChatView.swift               # AI chat interface
│   │   │   └── MessageBubble.swift          # Chat message rendering
│   │   ├── Analysis/
│   │   │   ├── AnalysisDashboardView.swift  # AI spending analysis
│   │   │   ├── AdvisorSettingsView.swift    # Persona + prompt management
│   │   │   └── GoalsView.swift              # Goal tracking + progress
│   │   ├── Statements/
│   │   │   └── StatementsView.swift       # PDF statement import + parsing
│   │   └── Components/              # CategoryIcon, CategoryBadge, AmountText, AIProgressView
│   ├── MCP/
│   │   ├── MCPServer.swift           # stdio JSON-RPC MCP server
│   │   └── MCPToolHandler.swift      # MCP tool definitions & execution
│   └── Utilities/
│       ├── Localization.swift        # En + zh-Hant localization
│       ├── DateFormatters.swift
│       └── JSONParser.swift
├── Tests/
│   ├── AutoCategorizerTests.swift
│   ├── DatabaseTests.swift
│   ├── IntentClassifierTests.swift
│   ├── JSONParserTests.swift
│   └── TransferDetectorTests.swift
├── Package.swift
├── build.sh                          # Release .app bundle builder
└── project.yml                       # XcodeGen config
```

## Setup

### Prerequisites

- macOS 14.0+
- Swift 6.0+ toolchain
- A Google Cloud project with Gmail API and Google Calendar API enabled
- An [OpenRouter](https://openrouter.ai) API key

### 1. Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Create a project and enable **Gmail API** and **Google Calendar API**
3. Create an **OAuth 2.0 Client ID** (Desktop application type)
4. Note your **Client ID** and **Client Secret**

### 2. Build & Run

```bash
cd LedgeIt
swift build
swift run
```

Or build as a .app bundle:

```bash
bash build.sh
open .build/LedgeIt.app
```

### 3. Configure in App

1. Open **Settings** from the sidebar
2. Enter your Google Client ID and Client Secret
3. Enter your OpenRouter API key
4. Click **Save & Connect Google** — this opens the OAuth flow in your browser
5. Once connected, the app automatically syncs and processes emails

### Install to Applications

```bash
bash build.sh
cp -R .build/LedgeIt.app /Applications/LedgeIt.app
```

## Email Processing Pipeline

The pipeline classifies emails in two stages to minimize LLM API costs:

### Stage 1: Rule-Based (free, instant)

- **Accept** — Trusted bank sender + transaction keywords, payment confirmations with transaction IDs
- **Reject** — Newsletters, marketing (3+ spam keywords), news articles, very long non-financial emails
- **Credit Card Statement** — Detected by keywords like "帳單", "繳款", "statement", "payment due"

### Stage 2: LLM (only for uncertain emails)

- Scores `transactionIntent` (0-10) and `marketingProbability` (0-10)
- Accept if intent >= 7 and marketing < 3
- Reject if intent < 2 or marketing >= 7

### Extraction

For accepted emails, the LLM extracts structured transaction data:
- Merchant name, amount, currency, date, description, type (debit/credit/transfer)

For credit card statements, a separate prompt extracts:
- Bank name, due date, amount due, currency, statement period

## AI Advisor System

### Personas

| Persona | Savings Target | Risk Level | Philosophy |
|---------|---------------|------------|------------|
| Conservative | 30% | Low | Minimize discretionary spending, maximize emergency fund |
| Moderate | 20% | Medium | Balance lifestyle and savings, diversified approach |
| Aggressive | 10% | High | Growth-focused, leverage debt strategically |
| Custom | User-defined | User-defined | Configurable targets and budget hints |

### Prompt Optimization

Users can iteratively refine the advisor's behavior:

1. Select a base persona or customize budget allocations
2. Provide natural language feedback (e.g., "dining suggestions are too strict")
3. The PromptOptimizer sends feedback + current prompt to LLM → returns refined prompt with change summary
4. Preview changes → Apply → new version saved to DB → goals regenerated
5. Version history allows reverting to any previous configuration

## AI Chat

The Chat view provides a natural language interface for querying financial data. It uses OpenRouter (Claude Sonnet 4.5) with streaming responses and tool calling, powered by local RAG with multilingual embeddings.

### Available Tools

| Tool | Description |
|------|------------|
| `semantic_search` | Hybrid search (vector + FTS5 keyword) with cross-language support |
| `get_transactions` | Query transactions with filters (date range, category, merchant, amount, type) |
| `get_spending_summary` | Income, expenses, and net savings for a date range |
| `get_category_breakdown` | Spending breakdown by category with percentages |
| `get_top_merchants` | Top merchants by spending amount |
| `get_upcoming_payments` | All unpaid credit card bills (including overdue) |
| `get_goals` | Financial goals filtered by status |
| `get_account_overview` | High-level account snapshot |

The system prompt includes a live financial snapshot so the LLM has context before tool use.

## MCP Server

LedgeIt includes a stdio-based [Model Context Protocol](https://modelcontextprotocol.io) server that exposes the same financial query tools to third-party AI agents (e.g., Claude Desktop, Cursor).

The MCP server reads JSON-RPC requests from stdin and writes responses to stdout. It supports `initialize`, `tools/list`, and `tools/call` methods with the same tools available in the chat interface.

## License

Private project.
