# UX Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix four UX issues: sidebar grouping, analysis report state persistence + layout, goals empty state, and standalone app bundle.

**Architecture:** All changes are in SwiftUI views and one shell script. Report persistence works by re-running fast SQL queries for statistical data and restoring only the AI advice from saved JSON. No schema changes needed.

**Tech Stack:** SwiftUI, GRDB, Swift Charts, Swift Package Manager

---

### Task 1: Sidebar Grouped Sections

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift:4-42`

**Step 1: Replace the SidebarItem enum and sidebar List**

Replace the current flat `SidebarItem` enum and `List` with grouped sections. The enum stays but the sidebar list uses manual `Section` grouping.

In `ContentView.swift`, replace the entire sidebar body (lines 37-43):

```swift
List(SidebarItem.allCases, selection: $selectedItem) { item in
    Label(item.rawValue, systemImage: item.icon)
        .tag(item)
}
.navigationSplitViewColumnWidth(min: 180, ideal: 200)
.listStyle(.sidebar)
```

With:

```swift
List(selection: $selectedItem) {
    Section("Overview") {
        Label(SidebarItem.dashboard.rawValue, systemImage: SidebarItem.dashboard.icon)
            .tag(SidebarItem.dashboard)
    }
    Section("Data") {
        ForEach([SidebarItem.transactions, .emails, .calendar], id: \.self) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
    }
    Section("Analysis") {
        ForEach([SidebarItem.analysis, .goals], id: \.self) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
    }
    Section {
        Label(SidebarItem.settings.rawValue, systemImage: SidebarItem.settings.icon)
            .tag(SidebarItem.settings)
    }
}
.navigationSplitViewColumnWidth(min: 180, ideal: 200)
.listStyle(.sidebar)
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat: group sidebar items into sections for better navigation UX"
```

---

### Task 2: Analysis Report — Restore from Database on Appear

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift`

The core bug: report is in `@State` which is destroyed when navigating away. Fix: on `.onAppear`, load the latest saved `FinancialReport` from DB, decode `adviceJSON` → `SpendingAdvice`, and re-run `SpendingAnalyzer` (fast SQL, no LLM) for fresh statistical data.

**Step 1: Add `onAppear` restore logic and update button label**

Add a `restoreReport()` function and wire it to `.onAppear`. Also change button text when report exists.

After line 42 (`.navigationTitle("Financial Analysis")`), add:

```swift
.onAppear { restoreReport() }
```

Add this new function after `generateReport()` (after line 283):

```swift
private func restoreReport() {
    guard report == nil, !isGenerating else { return }
    Task {
        do {
            let db = AppDatabase.shared
            // Load latest saved report
            let saved = try await db.db.read { db in
                try FinancialReport
                    .order(FinancialReport.Columns.createdAt.desc)
                    .fetchOne(db)
            }
            guard let saved,
                  let adviceData = saved.adviceJSON.data(using: .utf8) else { return }

            let decoder = JSONDecoder()
            let advice = try decoder.decode(FinancialAdvisor.SpendingAdvice.self, from: adviceData)

            // Parse period from saved report to re-run analyzer
            let components = saved.periodStart.split(separator: "-")
            guard components.count >= 2,
                  let year = Int(components[0]),
                  let month = Int(components[1]) else { return }

            // Re-run fast SQL analysis (no LLM)
            let analyzer = SpendingAnalyzer(database: db)
            let monthlyReport = try analyzer.monthlyBreakdown(year: year, month: month)
            let trends = try analyzer.spendingTrend(months: 6)

            report = ReportGenerator.FullReport(
                monthlyReport: monthlyReport,
                trends: trends,
                advice: advice,
                goals: GoalPlanner.GoalSuggestions(shortTerm: [], longTerm: [])
            )
        } catch {
            // Silently fail — user can still generate fresh report
            print("AnalysisDashboardView: failed to restore report: \(error)")
        }
    }
}
```

**Step 2: Update button label to show "Refresh" when report exists**

In `headerSection` (line 62-64), change:

```swift
Button { generateReport() } label: {
    Label("Generate Report", systemImage: "sparkles")
}
```

To:

```swift
Button { generateReport() } label: {
    Label(report != nil ? "Refresh Report" : "Generate Report", systemImage: "sparkles")
}
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift
git commit -m "fix: restore analysis report from database on view appear"
```

---

### Task 3: Analysis Report — Improve Layout

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift`

Make the report easier to read: larger text, amounts in category insights, taller chart, better section structure.

**Step 1: Improve categoryInsightsSection to show amounts**

Replace the `categoryInsightsSection` function (lines 188-213) with:

```swift
private func categoryInsightsSection(_ insights: [FinancialAdvisor.CategoryInsight]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Label("Category Insights", systemImage: "chart.pie.fill")
            .font(.headline)
        ForEach(insights, id: \.category) { insight in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                        .font(.callout).fontWeight(.semibold)
                    Spacer()
                }
                Text(insight.assessment)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion = insight.suggestion {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.caption)
                        Text(suggestion)
                            .font(.callout).foregroundStyle(.blue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(.background.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    .padding(16)
    .background(.background.secondary)
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```

**Step 2: Improve adviceSection text size**

In `adviceSection` (lines 113-156), change all `.font(.caption)` on habit/action/concern text to `.font(.callout)`. There are 4 occurrences:

- Line 122: `Text(habit).font(.caption)` → `Text(habit).font(.callout)`
- Line 138: `Text(item).font(.caption)` → `Text(item).font(.callout)`
- Line 146: `Text(concern).font(.caption)` → `Text(concern).font(.callout)`

Also the icon fonts on lines 121, 137, 145: change `.font(.caption)` → `.font(.callout)` on the Image system names.

**Step 3: Make savings chart taller with section icon**

Replace the `savingsTrendChart` function (lines 217-241) with:

```swift
private func savingsTrendChart(_ trends: [SpendingAnalyzer.MonthTrend]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Label("Savings Rate Trend", systemImage: "chart.line.uptrend.xyaxis")
            .font(.headline)
        Chart(trends) { trend in
            LineMark(
                x: .value("Month", trend.label),
                y: .value("Rate", trend.savingsRate * 100)
            )
            .foregroundStyle(.green)
            .symbol(Circle())
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Month", trend.label),
                y: .value("Rate", trend.savingsRate * 100)
            )
            .foregroundStyle(.green)
            .annotation(position: .top) {
                Text("\(String(format: "%.0f", trend.savingsRate * 100))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            RuleMark(y: .value("Target", 20))
                .foregroundStyle(.orange.opacity(0.5))
                .lineStyle(StrokeStyle(dash: [5, 5]))
        }
        .chartYAxisLabel("Savings Rate %")
        .frame(height: 240)

        Text("Dashed line = 20% savings target")
            .font(.caption).foregroundStyle(.tertiary)
    }
    .padding(16)
    .background(.background.secondary)
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```

**Step 4: Add section icon to anomalies and improve spacing**

In the main `body` VStack (line 12), change `spacing: 16` to `spacing: 20`.

**Step 5: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Analysis/AnalysisDashboardView.swift
git commit -m "feat: improve analysis report layout with larger text and better charts"
```

---

### Task 4: Goals — Smart Default Filter & Improved Empty States

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Analysis/GoalsView.swift`

The default filter is `.active` (status="accepted") but AI-generated goals start as "suggested", so users see nothing.

**Step 1: Change initial filter and add smart default logic**

Replace the state variable (line 6):
```swift
@State private var filter: GoalFilter = .active
```
With:
```swift
@State private var filter: GoalFilter = .all
@State private var hasInitializedFilter = false
```

In `startObservation()` (line 166), after the existing code, add smart filter initialization. Replace the entire function:

```swift
private func startObservation() {
    loadGoals()
    if !hasInitializedFilter {
        hasInitializedFilter = true
        // Smart default: show suggested if any exist, otherwise all
        let suggestedCount = (try? AppDatabase.shared.db.read { db in
            try FinancialGoal.filter(FinancialGoal.Columns.status == "suggested").fetchCount(db)
        }) ?? 0
        if suggestedCount > 0 {
            filter = .suggested
            loadGoals()
        }
    }
    let observation = ValueObservation.tracking { db -> Int in
        try FinancialGoal.fetchCount(db)
    }
    cancellable = observation.start(
        in: AppDatabase.shared.db,
        scheduling: .immediate
    ) { _ in } onChange: { _ in loadGoals() }
}
```

**Step 2: Improve empty state messaging**

Replace the empty state block (lines 33-39):

```swift
if goals.isEmpty {
    ContentUnavailableView(
        "No Goals",
        systemImage: "target",
        description: Text("Generate a financial analysis to get AI-suggested goals.")
    )
    .frame(maxHeight: .infinity)
}
```

With:

```swift
if goals.isEmpty {
    if filter == .all {
        ContentUnavailableView(
            "No Goals Yet",
            systemImage: "target",
            description: Text("Generate a Financial Analysis first to get AI-suggested goals.")
        )
        .frame(maxHeight: .infinity)
    } else {
        ContentUnavailableView(
            "No \(filter.rawValue) Goals",
            systemImage: "target",
            description: Text("Try switching to a different filter to see your goals.")
        )
        .frame(maxHeight: .infinity)
    }
}
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Analysis/GoalsView.swift
git commit -m "fix: smart default filter for goals, improved empty states"
```

---

### Task 5: Standalone App Bundle Build Script

**Files:**
- Create: `LedgeIt/build.sh`

**Step 1: Create the build script**

Create `LedgeIt/build.sh`:

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="LedgeIt"
BUILD_DIR=".build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

echo "Building ${APP_NAME}..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

# Copy binary
cp "${BUILD_DIR}/arm64-apple-macosx/release/${APP_NAME}" "${CONTENTS}/MacOS/${APP_NAME}"

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>LedgeIt</string>
    <key>CFBundleIdentifier</key>
    <string>com.ledgeit.app</string>
    <key>CFBundleName</key>
    <string>LedgeIt</string>
    <key>CFBundleDisplayName</key>
    <string>LedgeIt</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.finance</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

# Copy resources if they exist
if [ -d "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" ]; then
    cp -R "${BUILD_DIR}/arm64-apple-macosx/release/LedgeIt_LedgeIt.bundle" "${CONTENTS}/Resources/"
fi

echo ""
echo "App bundle created: ${APP_BUNDLE}"
echo "To run: open ${APP_BUNDLE}"
echo ""

# Optionally open the app
if [ "${1:-}" = "--run" ]; then
    open "${APP_BUNDLE}"
fi
```

**Step 2: Make executable**

```bash
chmod +x LedgeIt/build.sh
```

**Step 3: Test the build script**

Run: `cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt && ./build.sh --run`
Expected: App builds, bundle is created, app launches with its own Dock icon.

**Step 4: Commit**

```bash
git add LedgeIt/build.sh
git commit -m "feat: add build script for standalone .app bundle"
```

---

### Task 6: Final Integration Test

**Step 1: Clean build**

```bash
cd /Users/birdtasi/Documents/Projects/ledge-it/LedgeIt
swift package clean && swift build 2>&1 | tail -5
```
Expected: `Build complete!`

**Step 2: Build and launch as standalone app**

```bash
./build.sh --run
```
Expected: LedgeIt launches with its own Dock icon, not under iTerm2.

**Step 3: Verify all fixes**

1. **Sidebar**: Should show grouped sections (Overview, Data, Analysis, Settings)
2. **Analysis**: Click Analysis → if a previous report exists, it should load automatically. Click "Generate Report" → report renders with improved layout
3. **Goals**: Click Goals → should show "suggested" goals if they exist, or helpful empty state message
4. **Navigation**: Click Analysis → generate report → click Dashboard → click Analysis → report should still be visible

**Step 4: Commit any final adjustments if needed**
