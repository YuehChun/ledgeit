# Prompt Version Diff & Review Design

**Goal:** Add a dedicated Prompt Versions page with GitHub-style inline diff view for reviewing AI advisor prompt changes before approval.

**Architecture:** New sidebar page with version history list and inline diff panel. Uses line-based LCS diff algorithm in pure Swift. Pending optimization results are held in-memory until user approves/rejects.

## Decisions

- **Diff scope**: Optimize-only (diff shown when PromptOptimizer generates a new version)
- **Diff style**: Inline unified diff (red deletions, green additions)
- **Placement**: New dedicated sidebar page "Prompt Versions"
- **Approach**: Standalone diff page with version history + approval flow
- **Pending state**: In-memory (no DB migration needed)

## Page Layout

- Header: "Prompt Versions" title + Optimize button (triggers feedback input + optimizer)
- Version History: Compact list showing all versions (active badge, persona, feedback, date)
- Pending Review section (visible only when optimizer has generated a pending version):
  - Changes summary text from optimizer
  - Parameter comparison (savings target, risk level, category budgets: old -> new)
  - Inline prompt diff (monospaced, colored backgrounds)
  - Approve / Reject buttons

## Diff Algorithm

Line-by-line LCS (longest common subsequence) in pure Swift:
- Split text by newline
- Compute LCS to identify unchanged lines
- Mark each line as .unchanged, .added, or .removed
- ~40 lines of Swift code, no dependencies

## Data Flow

1. User enters feedback text + clicks Optimize
2. PromptOptimizer generates new parameters + spending_philosophy
3. Result held in @State as pending (not saved to DB yet)
4. Diff computed between active version's prompt and proposed prompt
5. User reviews diff + parameter changes
6. Approve: save as new PromptVersion (is_active=true), deactivate old
7. Reject: discard pending state

## Files

- **New**: `PromptVersionsView.swift` — the main page
- **New**: `TextDiff.swift` — LCS diff utility
- **Modified**: `ContentView.swift` — add sidebar item
- **Modified**: `Localization.swift` — ~10 new strings
