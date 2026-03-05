# UX Improvements Design

**Date**: 2026-02-28
**Status**: Approved

## Overview

Fix four UX issues in the LedgeIt macOS app: sidebar grouping, analysis report persistence, goals empty state, and standalone app bundle.

## Issue 1: Sidebar Grouped Sections

**Problem**: Flat list of 7 items with no visual hierarchy.

**Solution**: Group sidebar items into sections using SwiftUI `Section` views:

```
── Overview ──────────
   Dashboard

── Data ──────────────
   Transactions
   Emails
   Calendar

── Analysis ──────────
   Financial Analysis
   Goals

── ───────────────────
   Settings
```

**Files**: `ContentView.swift` — modify the sidebar `List` to use `Section` wrappers with headers.

## Issue 2: Analysis Report State Loss & Layout

**Problem**: Report stored in `@State` is lost when navigating away. Layout is hard to read.

**Solution — State Persistence**:
- Add `.onAppear` to `AnalysisDashboardView` that loads the latest `FinancialReport` from database
- Decode `adviceJSON` back into `SpendingAdvice`, reconstruct `MonthlyReport` from `summaryJSON`
- Store trends in the report JSON so they can be restored
- Button changes to "Refresh Report" when a saved report exists

**Solution — Layout**:
- Add clear section dividers with headings
- Category insights: show amount + percentage alongside assessment
- Savings trend chart: increase height, add data labels
- Consistent card padding and whitespace

**Files**:
- `AnalysisDashboardView.swift` — add `onAppear` restore, layout improvements
- `ReportGenerator.swift` — include trends in persisted report JSON

## Issue 3: Goals Empty State & Default Filter

**Problem**: Default filter is `.active` (status="accepted") but new goals have status "suggested", so users see nothing.

**Solution**:
- Smart default filter: if "suggested" goals exist, default to `.suggested`; otherwise `.all`
- Improved empty states:
  - No goals at all: "Generate a Financial Analysis to get AI-suggested goals" + navigation button
  - Filter empty: "No [filter] goals. Try switching filters."
- After report generation, show banner: "X new goals suggested! View Goals →"

**Files**:
- `GoalsView.swift` — smart default filter, improved empty states
- `AnalysisDashboardView.swift` — add post-generation goals banner

## Issue 4: Standalone App Bundle

**Problem**: Running from SPM debug binary appears under iTerm2, no Dock icon.

**Solution**: Create `build.sh` script that:
1. Runs `swift build -c release`
2. Creates proper `.app` bundle structure: `LedgeIt.app/Contents/{MacOS,Resources,Info.plist}`
3. Copies binary, Info.plist, entitlements
4. Result: launchable `.app` with its own Dock presence

**Files**: `LedgeIt/build.sh` (new)
