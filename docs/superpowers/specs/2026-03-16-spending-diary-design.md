# Spending Diary — Design Spec

## Overview

A daily, narrative-style spending diary that uses the user's selected AdvisorPersona to write a short diary entry reflecting on the day's transactions. Entries appear in CalendarView, integrated as a side panel alongside a compact calendar.

**Key differentiator from HeartbeatService:** Heartbeat produces analytical insights (data-driven, actionable). Spending Diary produces narrative entries (storytelling, persona-voiced). They coexist independently.

## Requirements

- Automatically generate one diary entry per day (covering the previous day's transactions)
- Use the user's selected AdvisorPersona to shape the diary's tone and perspective
- Display diary entries in CalendarView with a compact calendar (1/3) + diary panel (2/3) layout
- Generate entries even on days with no transactions
- Medium-length entries: 100–200 characters, with opening, spending recap, and closing reflection
- Follow the app's language setting
- Free feature (no Pro license required)

## Data Model

### `spending_diary_entries` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | Int64 (PK) | Auto-increment |
| `date` | String | YYYY-MM-DD, unique index — one entry per day |
| `content` | String | LLM-generated diary text |
| `personaId` | String | Persona ID used at generation time |
| `transactionCount` | Int | Number of transactions that day (0 = no-spend day) |
| `totalSpending` | Double | Total spending amount for the day |
| `currency` | String | Primary currency |
| `status` | String | "pending" / "completed" / "failed" |
| `createdAt` | Date | Timestamp of creation |

### Swift Model: `SpendingDiaryEntry`

- Conforms to `Codable`, `FetchableRecord`, `PersistableRecord` (GRDB)
- Unique index on `date`
- Database migration added to `DatabaseMigrations.swift`

## SpendingDiaryService

Actor-based async service, following the HeartbeatService pattern.

### Generation Flow

1. `generateIfNeeded()` — check if yesterday's diary exists; if not, generate it
2. Query `FinancialQueryService` for yesterday's transactions (merchant, category, amount)
3. Load current `AdvisorPersona` from AppStorage
4. Assemble LLM prompt (system prompt with persona voice + language; user prompt with transaction data)
5. Call `SessionFactory` → `LLMSession.complete()` (non-streaming, background generation)
6. Save result to `spending_diary_entries` with status = "completed"
7. On failure: set status = "failed" for retry on next launch

### Scheduling

- Triggered on app launch via `generateIfNeeded()`
- Backfill: look back 7 days for missing entries and generate them
- Cleanup: delete entries older than 90 days

### LLM Configuration

- **Temperature:** 0.7 (creative/narrative)
- **Model:** Uses the advisor model assignment from SessionFactory

## LLM Prompt Design

### System Prompt

```
You are a personal spending diary writer. Write diary entries in first-person
perspective as if you are the user reflecting on their day.

Personality & tone: {persona.spendingPhilosophy}

Rules:
- Write 100-200 characters in {language}
- Narrative style, like a real diary entry
- Mention specific merchants and amounts naturally in the story
- End with a brief reflection or feeling
- If no transactions, write about having a spending-free day
- Never give direct financial advice (that's the advisor's job)
```

### User Prompt

Provides:
- Transaction list for the day (merchant, amount, category)
- Transaction count and total spending
- Month-to-date total and daily average (for comparison context)

### Persona Influence on Tone

| Persona | Diary Tone |
|---------|------------|
| Conservative | Emphasizes satisfaction from saving, notes budget awareness, celebrates no-spend days |
| Moderate | Balanced perspective, records spending without over-judgment |
| Aggressive | Focuses on value received, investment-minded framing, evaluates spend-worthiness |
| Custom | Follows user-defined spendingPhilosophy text |

## CalendarView Integration

### Layout Change

Current CalendarView is restructured to a split layout:

- **Left panel (~1/3 width):** Compact calendar grid
  - Blue dot indicator on dates that have a diary entry
  - Selected date highlighted with blue border
  - Monthly overview stats below the calendar (total spending, diary entry count, daily average)

- **Right panel (~2/3 width):** Diary detail panel
  - Date header with transaction count and total spending
  - Compact horizontal transaction cards (icon + merchant + amount)
  - Diary content as the primary, largest visual element
  - Persona badge showing which persona generated the entry

### States

- **Date with diary:** Show full diary panel with transactions and content
- **Date without diary (future/no data):** Show empty state with explanation
- **Date with failed generation:** Show retry option
- **Loading state:** Show placeholder while diary is being fetched

## File Locations

| File | Purpose |
|------|---------|
| `Models/SpendingDiaryEntry.swift` | Data model |
| `Services/SpendingDiaryService.swift` | Generation service (actor) |
| `Views/Calendar/CalendarView.swift` | Modified layout (compact calendar + diary panel) |
| `Views/Calendar/DiaryPanelView.swift` | New diary detail panel component |
| `Database/DatabaseMigrations.swift` | New migration for `spending_diary_entries` table |

## Out of Scope

- Google Calendar sync for diary entries (only in-app CalendarView)
- Manual diary editing or user-written entries
- Weekly/monthly diary summaries
- Sharing or exporting diary entries
- Streaming generation (background-only, no real-time UI)
