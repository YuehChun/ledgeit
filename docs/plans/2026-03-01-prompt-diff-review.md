# Prompt Version Diff & Review Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Prompt Versions page with inline diff view for reviewing AI advisor prompt changes.

**Architecture:** New sidebar page, LCS diff utility, in-memory pending state, approve/reject flow.

**Tech Stack:** SwiftUI, GRDB, pure Swift LCS diff algorithm

---

### Task 1: TextDiff Utility

**Files:**
- Create: `LedgeIt/LedgeIt/Utilities/TextDiff.swift`

Implement a line-based diff utility using LCS algorithm.

```swift
enum DiffLineType { case unchanged, added, removed }

struct DiffLine: Identifiable {
    let id = UUID()
    let type: DiffLineType
    let text: String
}

struct TextDiff {
    static func diff(old: String, new: String) -> [DiffLine]
}
```

The diff function splits both strings by newline, computes the LCS table, then walks it to produce DiffLine array with correct types.

---

### Task 2: L10n Strings

**Files:**
- Modify: `LedgeIt/LedgeIt/Utilities/Localization.swift`

Add these strings to the L10n struct:

```
promptVersions / "Prompt Versions" / "提示詞版本"
promptVersionsSubtitle / "Review and manage AI advisor prompt changes" / "審核與管理 AI 顧問提示詞變更"
pendingReview / "Pending Review" / "待審核"
changesSummary / "Changes Summary" / "變更摘要"
parameters / "Parameters" / "參數"
current / "Current" / "目前"
proposed / "Proposed" / "建議"
promptDiff / "Prompt Diff" / "提示詞差異"
approve / "Approve" / "核准"
reject / "Reject" / "拒絕"
noVersionsYet / "No Versions Yet" / "尚無版本"
noVersionsDescription / "Optimize your advisor in AI Advisor settings to create versions." / "在 AI 顧問設定中優化您的顧問以建立版本。"
noPendingChanges / "No Pending Changes" / "沒有待審核的變更"
noPendingDescription / "Enter feedback and click Optimize to generate prompt improvements." / "輸入回饋並點擊優化以產生提示詞改進。"
version / "Version" / "版本"
```

---

### Task 3: Add Sidebar Item

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

Add `case promptVersions = "Prompt Versions"` to `SidebarItem` enum with icon `"doc.badge.clock.fill"`. Add to sidebar under Analysis section. Add case to detail switch rendering `PromptVersionsView()`.

---

### Task 4: PromptVersionsView

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Analysis/PromptVersionsView.swift`

Main view with:

**State:**
- `@State versions: [PromptVersion]` — loaded from DB
- `@State pendingOptimization: OptimizedPrompt?` — in-memory pending
- `@State currentPersona: AdvisorPersona?` — active persona for diffing
- `@State feedbackText: String` — user feedback input
- `@State isOptimizing: Bool`
- `@State optimizeError: String?`

**Layout:**
1. Header with title + subtitle
2. Feedback input section: TextEditor + Optimize button
3. If pendingOptimization exists: PendingReviewSection
4. Version history list

**PendingReviewSection:**
- Changes summary text (from optimizer)
- Parameter comparison grid: savings target, risk level (current → proposed)
- Category budget comparison (current → proposed) for changed categories only
- Inline diff view of spending_philosophy (using TextDiff)
- Approve / Reject buttons

**DiffView (inline component):**
- ScrollView with monospaced Text lines
- Each DiffLine rendered with:
  - `.removed`: red background (0.15 opacity), red text, "−" prefix
  - `.added`: green background (0.15 opacity), green text, "+" prefix
  - `.unchanged`: no background, secondary text, " " prefix

**Actions:**
- Optimize: call PromptOptimizer, store result in pendingOptimization
- Approve: save new PromptVersion to DB (is_active=true), deactivate old, clear pending, reload versions
- Reject: clear pendingOptimization

**Version History:**
- List of all PromptVersions ordered by id desc
- Each row: version number, persona badge, feedback excerpt, date, active badge
- Active version highlighted

---

### Task 5: Wire Up and Build

- Verify ContentView compiles with new sidebar item
- Verify PromptVersionsView loads versions from DB
- Build release and deploy to /Applications/LedgeIt.app
