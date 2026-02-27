# LedgeIt

A native macOS app that automatically extracts financial transactions from your Gmail, classifies them with AI, and presents them in a personal finance dashboard with calendar integration.

## What It Does

1. **Syncs Gmail** — Fetches emails via Gmail API (OAuth 2.0, read-only)
2. **AI Classification** — Rule-based filter + LLM fallback (via OpenRouter) to identify financial emails
3. **Transaction Extraction** — Extracts merchant, amount, currency, date from receipts, invoices, and bank notifications
4. **Credit Card Bills** — Detects statement emails and tracks due dates / amounts owed
5. **Auto-Categorization** — 15 spending categories with subcategories (food, transport, utilities, etc.)
6. **Calendar Sync** — Creates Google Calendar events for each transaction
7. **Cloud Backup** — Optional Supabase integration to back up financial emails
8. **Auto-Sync** — Background sync every 15 minutes when the app is running

## Screenshots

The app has 5 main views accessible from the sidebar:

- **Dashboard** — Monthly spending/income summary, category breakdown chart, top merchants, spending velocity alert, upcoming credit card bills
- **Transactions** — Searchable/filterable table of all extracted transactions
- **Emails** — Raw Gmail inbox with processing status
- **Calendar** — Month view with transaction dots and bill due date markers
- **Settings** — API credentials, Google connection status, sync controls

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6.0 |
| UI | SwiftUI (macOS 14+) |
| Database | SQLite via [GRDB](https://github.com/groue/GRDB.swift) 7.0 |
| AI/LLM | [OpenRouter](https://openrouter.ai) API (Claude, GPT, etc.) |
| Auth | Google OAuth 2.0 (Desktop app flow) |
| Cloud | Supabase REST API (optional, no SDK) |
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
  └── Deduplication (amount + currency + date)
  │
  ▼
transactions table ──► DashboardView, CalendarView, TransactionListView
credit_card_bills table ──► DashboardView (upcoming bills), CalendarView (due dates)
  │
  ▼
CalendarService ──► Google Calendar (payment events)
SupabaseService ──► Supabase (financial email cloud backup)
```

## Project Structure

```
LedgeIt/
├── LedgeIt/
│   ├── LedgeItApp.swift              # App entry point
│   ├── Database/
│   │   ├── AppDatabase.swift         # GRDB database setup
│   │   └── DatabaseMigrations.swift  # Schema migrations (v1-v4)
│   ├── Models/
│   │   ├── Email.swift
│   │   ├── Transaction.swift
│   │   ├── CreditCardBill.swift
│   │   ├── CalendarEvent.swift
│   │   ├── Attachment.swift
│   │   └── SyncState.swift
│   ├── PFM/                          # Personal Finance Management
│   │   ├── ExtractionPipeline.swift  # Main processing orchestrator
│   │   ├── IntentClassifier.swift    # Rule-based email filtering
│   │   ├── LLMProcessor.swift        # OpenRouter AI calls
│   │   ├── AutoCategorizer.swift     # Merchant categorization
│   │   ├── TransferDetector.swift    # Transfer identification
│   │   └── PFMConfig.swift           # Thresholds & trusted institutions
│   ├── Services/
│   │   ├── GmailService.swift        # Gmail REST API client
│   │   ├── GoogleAuthService.swift   # OAuth 2.0 flow
│   │   ├── SyncService.swift         # Email sync orchestration
│   │   ├── CalendarService.swift     # Google Calendar API
│   │   ├── OpenRouterService.swift   # LLM API client
│   │   ├── SupabaseService.swift     # Cloud backup (REST, no SDK)
│   │   ├── PersonalFinanceService.swift # Dashboard data queries
│   │   ├── KeychainService.swift     # Secure credential storage
│   │   └── PDFParserService.swift    # PDF text extraction
│   ├── Views/
│   │   ├── ContentView.swift         # Sidebar + auto-sync
│   │   ├── DashboardView.swift       # Financial dashboard
│   │   ├── TransactionListView.swift # Transactions table
│   │   ├── TransactionDetailView.swift
│   │   ├── EmailListView.swift       # Email inbox
│   │   ├── CalendarView.swift        # Calendar with bill markers
│   │   ├── SettingsView.swift        # Credentials & sync controls
│   │   └── Components/              # CategoryIcon, CategoryBadge, AmountText
│   └── Utilities/
│       ├── DateFormatters.swift
│       └── JSONParser.swift
├── Package.swift
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

Or for a release build:

```bash
swift build -c release
```

### 3. Configure in App

1. Open **Settings** (sidebar or Cmd+,)
2. Enter your Google Client ID and Client Secret
3. Enter your OpenRouter API key
4. (Optional) Enter Supabase URL and Anon Key for cloud backup
5. Click **Save & Connect Google** — this opens the OAuth flow in your browser
6. Once connected, the app automatically syncs and processes emails

### Install to Applications

```bash
# Build release
swift build -c release

# Copy to .app bundle (if already created)
cp .build/release/LedgeIt /Applications/LedgeIt.app/Contents/MacOS/LedgeIt
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

## Supabase Setup (Optional)

To enable cloud backup of financial emails:

1. Create a Supabase project
2. Run this SQL in the SQL Editor:

```sql
CREATE TABLE emails (
    id TEXT PRIMARY KEY,
    thread_id TEXT,
    subject TEXT,
    sender TEXT,
    date TEXT,
    snippet TEXT,
    body_text TEXT,
    body_html TEXT,
    labels TEXT,
    is_financial BOOLEAN NOT NULL DEFAULT FALSE,
    is_processed BOOLEAN NOT NULL DEFAULT FALSE,
    classification_result TEXT,
    created_at TEXT DEFAULT NOW()::TEXT
);

ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow anon full access" ON emails
    FOR ALL USING (true) WITH CHECK (true);
```

3. Enter your project URL and Anon Key in Settings

Only emails classified as financial are synced to Supabase.

## License

Private project.
