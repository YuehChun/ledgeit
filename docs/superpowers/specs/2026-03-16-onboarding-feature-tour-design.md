# Onboarding Feature Tour — Design Spec

## Overview

Add an interactive feature tour at the very beginning of the onboarding flow, before the existing chat wizard setup. The tour showcases 6 core features with SwiftUI animated illustrations, helping new users understand the app's value before committing to the setup process.

## Requirements

- Display a horizontal PageTabView with 6 feature cards before the chat wizard
- Each card has a SwiftUI animated illustration + feature name + one-line description
- Deep blue gradient background (#060d1a → #112240)
- Page dots at bottom, active dot color matches card's accent color
- Skip button (top-right) to jump directly to chat wizard
- Language toggle button (top-right) to switch between English and 繁體中文
- Default language detected from `Locale.current`; user can override via toggle
- Last card shows "Get Started →" button to enter chat wizard
- Language selection syncs to `appLanguage` UserDefaults (used by entire app)
- `UserDefaults("hasCompletedFeatureTour")` persists completion state

## Feature Cards (6 total)

| # | Feature | Accent Color | Icon/Animation | Title (EN) | Title (zh-Hant) | Description (EN) | Description (zh-Hant) |
|---|---------|-------------|----------------|------------|-----------------|-------------------|----------------------|
| 1 | Smart Extraction | #2563eb (blue) | Envelope with floating transaction chips flying out | Smart Extraction | 智慧擷取 | Automatically extract transactions from your Gmail — receipts, bills, and subscriptions. | 自動從 Gmail 擷取消費紀錄 — 收據、帳單、訂閱，一次到位。 |
| 2 | Dashboard | #f59e0b (amber) | Bar chart bars growing upward with animated counter | Dashboard | 財務總覽 | See your full financial picture at a glance — income, spending, and savings rate. | 一眼掌握收支全貌 — 收入、支出、儲蓄率。 |
| 3 | Spending Diary | #38bdf8 (sky) | Calendar page flipping with pen writing effect and diary snippet | Spending Diary | 消費日記 | AI writes a daily diary in your style, reflecting on the day's spending. | AI 用你的風格每天寫一篇消費日記。 |
| 4 | AI Advisory | #ec4899 (pink) | Chat bubbles alternating with typing indicator | AI Advisory | AI 理財顧問 | Chat with AI about your finances — ask anything, get personalized answers. | 跟 AI 聊你的財務狀況 — 隨時提問，獲得個人化回答。 |
| 5 | Financial Analysis | #8b5cf6 (violet) | Pie chart splitting into category segments | Financial Analysis | 財務分析 | AI analyzes your spending habits and provides actionable insights. | AI 分析消費習慣，提供可執行的建議。 |
| 6 | Goal Tracking | #22c55e (green) | Target icon with progress bar filling up | Goal Tracking | 財務目標 | Set savings goals, track progress, and get AI suggestions to stay on track. | 設定儲蓄目標，追蹤進度，AI 助你達標。 |

## Architecture

### Flow Integration

```
App Launch
  │
  ▼
hasCompletedOnboarding == false?
  │ yes
  ▼
hasCompletedFeatureTour == false?
  │ yes                          │ no (already seen tour)
  ▼                              ▼
FeatureTourView ──────────► OnboardingChatView
  (6 cards, swipe)               (existing chat wizard)
  Skip or "Get Started →"
```

### New File: `FeatureTourView.swift`

Location: `LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift`

- Standalone SwiftUI View
- Uses `TabView` with `.tabViewStyle(.page(indexDisplayMode: .never))` for custom dots
- Each card is a `FeatureCardView` subview
- `@State` tracks current page index
- `@AppStorage("appLanguage")` for language sync
- On completion: sets `UserDefaults("hasCompletedFeatureTour") = true` and transitions to chat wizard

### Card Layout (each card)

```
┌─────────────────────────────┐
│  LedgeIt          Skip  🌐  │  ← top bar
│                             │
│                             │
│      ┌─────────────┐       │
│      │  Animated    │       │  ← radial glow + icon + floating elements
│      │  Illustration│       │
│      └─────────────┘       │
│                             │
│      Feature Title          │  ← 24pt bold white
│      One-line description   │  ← 15pt gray, max 320px
│                             │
│      [Get Started →]        │  ← only on last card
│                             │
│        ● ○ ○ ○ ○ ○         │  ← custom page dots
└─────────────────────────────┘
```

### Visual Design

- **Background**: `LinearGradient` from #060d1a → #0d1b2e → #112240
- **Glow**: `RadialGradient` behind each card's icon, using card's accent color at 15-20% opacity
- **Floating elements**: Small chips/shapes around the icon that hint at the feature
- **Page dots**: Custom `HStack` of circles, active dot uses card's accent color, inactive uses #1a2a42
- **Typography**: Title in white (#e8edf5), description in muted blue-gray (#7a8ba8)
- **"Get Started →" button**: Blue gradient (#1d4ed8 → #2563eb) with subtle shadow

### Language Toggle

- Small globe icon button (🌐) at top-right, next to Skip
- Toggles between "EN" and "繁中"
- Changes `@AppStorage("appLanguage")` which propagates to the chat wizard
- Default: `Locale.current.language.languageCode?.identifier == "zh" ? "zh-Hant" : "en"`

### Animations (SwiftUI)

Each card has a unique entry animation triggered by `onAppear` or page change:

1. **Smart Extraction**: Transaction chips fly in from envelope with `.transition(.scale.combined(with: .opacity))` and staggered delays
2. **Dashboard**: Bar chart bars grow from bottom with `.animation(.spring())` staggered
3. **Spending Diary**: Calendar page flips, pen writes (offset animation), diary text types in
4. **AI Advisory**: Chat bubbles slide in alternately from left/right with typing dots
5. **Financial Analysis**: Pie segments fan out from center with rotation
6. **Goal Tracking**: Progress bar fills from 0% to 72% with `.animation(.easeOut(duration: 1.0))`

Animations should be lightweight — SF Symbols + basic shapes + offset/opacity/scale transforms. No Lottie or external dependencies.

## Modified Files

| File | Change |
|------|--------|
| `LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift` | Create — new feature tour view |
| `LedgeIt/LedgeIt/LedgeItApp.swift` or onboarding entry point | Modify — add FeatureTourView before OnboardingChatView |
| `LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift` | Modify — read language from `appLanguage` if already set by tour |

## Out of Scope

- Changing the existing chat wizard setup flow
- Adding new setup steps
- Auto-play / timed transitions
- Analytics or tracking
- Showing the tour to existing users (only for new onboarding)
