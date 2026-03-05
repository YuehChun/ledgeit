# AI Progress Indicator UX Enhancement — Design

## Goal

Replace inconsistent small `ProgressView()` spinners across all AI-triggered views with a unified, informative `AIProgressView` component that shows an animated indeterminate progress bar + step-by-step checklist.

## Current State

All views use `ProgressView().controlSize(.small)` with varying status text. No step tracking, no pipeline visibility.

| View | Current Loading UI |
|------|--------------------|
| AnalysisDashboardView | `.small` spinner + progress string |
| GoalsView | `.small` spinner + "Generating goals" |
| AdvisorSettingsView | `.small` spinner + "Optimizing" / "Generating goals" |
| StatementsView | `.mini` spinner + localized status |
| DashboardView | `.small` spinner + "Analyzing..." |

## Design

### Reusable Component: `AIProgressView`

A single SwiftUI view that replaces all existing spinner patterns.

**Input:**
- `title: String` — e.g., "Generating Report"
- `steps: [String]` — ordered step labels
- `currentStep: Int` — index of the currently active step (0-based)

**Visual layout:**
```
┌───────────────────────────────────┐
│  Generating Report                │
│  ═══════◆═══════════════════      │  ← animated shimmer bar
│  ✓ Loading data                   │  ← completed (green checkmark)
│  ● Analyzing trends...            │  ← active (blue, pulsing)
│  ○ Generating insights            │  ← pending (gray)
└───────────────────────────────────┘
```

**Animations:**
- Indeterminate bar: horizontal shimmer/gradient slide (repeating)
- Active step: pulse opacity animation on the blue dot
- Step transitions: smooth with `.animation(.easeInOut)`

**SF Symbols:**
- Completed: `checkmark.circle.fill` (green)
- Active: `circle.fill` (blue, pulsing)
- Pending: `circle` (gray)

### Step Definitions Per View

| View | Steps |
|------|-------|
| **AnalysisDashboardView** (Generate Report) | "Loading data" → "Analyzing trends" → "Generating insights" |
| **StatementsView** (Parse PDF) | "Decrypting PDF" → "Classifying document" → "Extracting transactions" → "Categorizing" |
| **AdvisorSettingsView** (Optimize Prompt) | "Processing feedback" → "Adjusting parameters" |
| **AdvisorSettingsView** (Generate Goals) | "Analyzing spending" → "Creating goals" → "Calculating targets" |
| **DashboardView** (Analyze) | "Loading transactions" → "Analyzing patterns" → "Generating insights" |

### Integration Pattern

Each view:
1. Keeps its existing `@State private var isProcessing = false`
2. Adds `@State private var currentStep = 0`
3. Replaces `ProgressView().controlSize(.small)` with `AIProgressView(...)`
4. Advances `currentStep` at each pipeline stage in the async function

### Files

- **Create:** `LedgeIt/Views/Components/AIProgressView.swift` — the reusable component
- **Modify:** `AnalysisDashboardView.swift` — replace spinner, add step tracking
- **Modify:** `StatementsView.swift` — replace spinner, add step tracking
- **Modify:** `AdvisorSettingsView.swift` — replace spinners, add step tracking
- **Modify:** `DashboardView.swift` — replace spinner, add step tracking
- **Modify:** `GoalsView.swift` — replace spinner (uses shared GoalGenerationService)

### What We're NOT Doing

- No overlay/modal — inline only
- No percentage tracking — indeterminate bar
- No changes to Chat view (already has streaming UX)
- No new Observable classes — simple `@State` step index per view
