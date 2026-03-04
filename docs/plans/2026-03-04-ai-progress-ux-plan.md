# AI Progress Indicator UX Enhancement — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace all AI-triggered spinners with a unified AIProgressView component showing animated progress bar + step checklist.

**Architecture:** Single reusable SwiftUI component, integrated inline into 5 existing views.

**Tech Stack:** SwiftUI, SF Symbols, Swift animations

---

### Task 1: Create AIProgressView Component

**Files:**
- Create: `LedgeIt/Views/Components/AIProgressView.swift`

**Implementation:**
- SwiftUI view with `title`, `steps`, `currentStep` parameters
- Animated indeterminate progress bar (gradient shimmer)
- Step list with SF Symbols: checkmark.circle.fill (green), circle.fill (blue, pulsing), circle (gray)
- Compact card style with rounded corners and subtle background

### Task 2: Integrate into AnalysisDashboardView

**Files:**
- Modify: `LedgeIt/Views/Analysis/AnalysisDashboardView.swift`

**Changes:**
- Replace `ProgressView().controlSize(.small) + Text(progress)` with `AIProgressView`
- Add `@State private var currentStep = 0`
- Update `generateReport()` to advance steps: Loading data → Analyzing trends → Generating insights

### Task 3: Integrate into StatementsView

**Files:**
- Modify: `LedgeIt/Views/Statements/StatementsView.swift`

**Changes:**
- Replace `ProgressView().controlSize(.mini) + Text(processStatus)` with `AIProgressView`
- Update `processAttachment()` to advance steps: Decrypting PDF → Classifying document → Extracting transactions → Categorizing

### Task 4: Integrate into AdvisorSettingsView

**Files:**
- Modify: `LedgeIt/Views/Analysis/AdvisorSettingsView.swift`

**Changes:**
- Replace spinner in optimize prompt section with `AIProgressView` (2 steps)
- Replace spinner in generate goals section with `AIProgressView` (3 steps)

### Task 5: Integrate into DashboardView

**Files:**
- Modify: `LedgeIt/Views/DashboardView.swift`

**Changes:**
- Replace `ProgressView().controlSize(.small) + Text("Analyzing...")` with `AIProgressView`
- Update `loadAIInsights()` to advance steps: Loading transactions → Analyzing patterns → Generating insights

### Task 6: Build and verify

**Steps:**
- `bash build.sh`
- Copy to /Applications and launch
- Verify all 5 views show the new progress indicator
