# AI Agent Memory & Identity System — Design Spec

**Date:** 2026-03-12
**Scope:** Phase 1 (Identity Files) + Phase 2 (Hierarchical Memory) for LedgeIt financial advisor chat
**Approach:** Lightweight file system + tool-driven memory (Approach 1)

## Goal

Make the LedgeIt AI financial advisor "remember" the user — their preferences, financial background, past conversations, and ongoing context — by storing identity and memory as Markdown files and injecting them into the system prompt. The AI writes memories via tool calling (AI-initiated, not automatic).

## File Structure

```
~/Library/Application Support/LedgeIt/agent/
├── PERSONA.md              # AI personality, tone, boundary rules
├── USER.md                 # User preferences, financial background (AI-written)
└── memory/
    ├── YYYY-MM-DD.md       # Daily tactical memory (append-only)
    ├── active-context.md   # Working memory (in-progress projects, todos)
    └── MEMORY.md           # Long-term strategic memory (curated facts)
```

### PERSONA.md (shipped with defaults, rarely changed)

- AI name and self-description
- Tone: professional but approachable financial advisor
- Boundary rules: no legal/tax advice, confirm before destructive actions, protect privacy
- Response format preferences (bullet points, currency formatting)
- Memory tool usage guidelines (when to save what, where)

### USER.md (AI-written via tool calling)

- User's preferred name, timezone
- Financial goals summary (savings targets, investment preferences)
- Communication preferences (language, verbosity level)
- Spending habit notes (e.g., "monthly mortgage payment 25,000")

### Memory Files

- **`memory/YYYY-MM-DD.md`** — Daily log. Append-only. Timestamped entries. AI writes decisions, observations, notable interactions.
- **`active-context.md`** — Working scratchpad. Replace mode. Ongoing projects, deadlines, action items.
- **`MEMORY.md`** — Curated long-term facts. Append mode. Patterns, stable user habits, key financial decisions.

## AgentPromptBuilder

Replaces `ChatEngine.buildSystemPrompt()`. Assembles system prompt before each LLM call.

### Assembly Order (highest to lowest priority)

1. `PERSONA.md` full text (personality + rules, never omitted)
2. `USER.md` full text (user preferences)
3. `active-context.md` full text (working memory)
4. Today + yesterday's `memory/YYYY-MM-DD.md` (recent context)
5. `MEMORY.md` first 200 lines (long-term memory, truncated)
6. Financial snapshot (existing: income/expense/goals data from FinancialQueryService)

### Truncation Rules

- Per-file cap: 15,000 characters. Excess truncated with `[truncated — use memory_search for full content]`.
- Total system prompt cap: 50,000 characters (~12K tokens). When exceeded, remove from lowest priority upward.

## Memory Tools (3 new tools added to ChatEngine)

### `memory_save`

| Parameter | Type | Description |
|-----------|------|-------------|
| `file` | enum | `user_profile`, `long_term`, `daily`, `active_context` |
| `content` | string | Text to write |
| `mode` | enum | `append` (default) or `replace` |

Behavior:
- `daily` → writes to `memory/YYYY-MM-DD.md`, auto-prepends timestamp `[HH:mm]`
- `user_profile` → writes to `USER.md`, typically replace
- `long_term` → writes to `MEMORY.md`, typically append
- `active_context` → writes to `active-context.md`, typically replace

Returns: confirmation with file path and character count.

### `memory_search`

| Parameter | Type | Description |
|-----------|------|-------------|
| `query` | string | Search keywords |
| `scope` | enum (optional) | `all` (default), `daily`, `long_term` |

Behavior:
- Scans `.md` files in agent directory (line-level keyword matching, case-insensitive)
- Returns up to 10 results, each max 500 characters, with file name + line number
- v1: keyword search only. Can upgrade to vector search later.

### `memory_get`

| Parameter | Type | Description |
|-----------|------|-------------|
| `file` | string | File identifier: `user_profile`, `long_term`, `active_context`, `persona`, or `daily:YYYY-MM-DD` |

Behavior:
- Reads full file content, truncated at 10,000 characters
- Used when AI needs complete context from a specific memory file

### System Prompt Guidance for AI

Included in PERSONA.md to instruct the AI:
- User expresses preference or corrects AI → `memory_save` to `user_profile`
- Important financial pattern or long-term fact discovered → `memory_save` to `long_term`
- Starting/updating a multi-session task → `memory_save` to `active_context`
- Need to recall past conversations → `memory_search` first, then `memory_get` if needed

## AgentFileManager

New class handling all file I/O for the agent system.

**Responsibilities:**
- Ensure directory structure exists on first access
- Write default `PERSONA.md` if missing
- `read(file:)` — read a memory file, return content or nil
- `write(file:content:mode:)` — write/append to a memory file
- `search(query:scope:)` — keyword search across memory files
- All paths resolved relative to `~/Library/Application Support/LedgeIt/agent/`

## ChatEngine Integration

**Changes to ChatEngine only:**

1. Hold `AgentFileManager` and `AgentPromptBuilder` instances
2. Replace `buildSystemPrompt()` call with `AgentPromptBuilder.build(fileManager:)`
3. Add 3 memory tool definitions to existing tool array
4. Add 3 cases to `executeTool()` dispatching to `AgentFileManager`

**Files NOT changed:** SessionFactory, LLMSession, any Provider, ChatView, ChatSessionManager, ChatMessage.

## New Files

| File | Purpose |
|------|---------|
| `Services/Agent/AgentFileManager.swift` | Memory file I/O, directory management, keyword search |
| `Services/Agent/AgentPromptBuilder.swift` | System prompt assembly from identity + memory files |

## Modified Files

| File | Change |
|------|--------|
| `Services/ChatEngine.swift` | Inject AgentPromptBuilder, add 3 memory tools + execution |

## Out of Scope (future phases)

- Vector search / hybrid retrieval (Phase 3)
- Context compaction / pre-compaction memory flush (Phase 4)
- Reflection/consolidation job (Phase 4)
- Heartbeat / proactive agent (Phase 5)
- Settings UI for editing PERSONA.md / USER.md
