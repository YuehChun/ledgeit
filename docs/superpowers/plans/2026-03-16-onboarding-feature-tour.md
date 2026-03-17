# Onboarding Feature Tour Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an interactive feature tour with 6 animated cards at the start of onboarding, before the chat wizard setup flow.

**Architecture:** New `FeatureTourView` with `TabView(.page)` containing 6 `FeatureCardView` instances. Inserted in `ContentView.swift` before `OnboardingChatView`. Language toggle syncs to `@AppStorage("appLanguage")` which propagates to the chat wizard.

**Tech Stack:** Swift 6.2, SwiftUI (TabView, spring animations, LinearGradient, RadialGradient), @AppStorage

**Spec:** `docs/superpowers/specs/2026-03-16-onboarding-feature-tour-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift` | Create | Main tour container with TabView, language toggle, Skip button |
| `LedgeIt/LedgeIt/Views/Onboarding/FeatureCardView.swift` | Create | Individual card component with animated illustration |
| `LedgeIt/LedgeIt/Views/ContentView.swift` | Modify | Add `hasCompletedFeatureTour` check before onboarding |
| `LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift` | Modify | Read `appLanguage` on init if set by tour |

---

## Chunk 1: FeatureCardView Component

### Task 1: Create FeatureCardView

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/FeatureCardView.swift`

- [ ] **Step 1: Create FeatureCardView with data model and card layout**

This is a single card in the feature tour. It receives a `FeatureCard` data struct and renders the animated illustration, title, and description.

```swift
// LedgeIt/LedgeIt/Views/Onboarding/FeatureCardView.swift
import SwiftUI

struct FeatureCard: Identifiable {
    let id = UUID()
    let index: Int
    let titleEN: String
    let titleZH: String
    let descriptionEN: String
    let descriptionZH: String
    let accentColor: Color
    let iconName: String

    func title(language: String) -> String {
        language == "zh-Hant" ? titleZH : titleEN
    }

    func description(language: String) -> String {
        language == "zh-Hant" ? descriptionZH : descriptionEN
    }

    static let allCards: [FeatureCard] = [
        FeatureCard(
            index: 0,
            titleEN: "Smart Extraction",
            titleZH: "智慧擷取",
            descriptionEN: "Automatically extract transactions from your Gmail — receipts, bills, and subscriptions, all in one place.",
            descriptionZH: "自動從 Gmail 擷取消費紀錄 — 收據、帳單、訂閱，一次到位。",
            accentColor: Color(red: 0.15, green: 0.39, blue: 0.92), // #2563eb
            iconName: "envelope.fill"
        ),
        FeatureCard(
            index: 1,
            titleEN: "Dashboard",
            titleZH: "財務總覽",
            descriptionEN: "See your full financial picture at a glance — income, spending, and savings rate.",
            descriptionZH: "一眼掌握收支全貌 — 收入、支出、儲蓄率。",
            accentColor: Color(red: 0.96, green: 0.62, blue: 0.04), // #f59e0b
            iconName: "chart.bar.fill"
        ),
        FeatureCard(
            index: 2,
            titleEN: "Spending Diary",
            titleZH: "消費日記",
            descriptionEN: "AI writes a daily diary in your style, reflecting on the day's spending.",
            descriptionZH: "AI 用你的風格每天寫一篇消費日記。",
            accentColor: Color(red: 0.22, green: 0.74, blue: 0.97), // #38bdf8
            iconName: "calendar.badge.clock"
        ),
        FeatureCard(
            index: 3,
            titleEN: "AI Advisory",
            titleZH: "AI 理財顧問",
            descriptionEN: "Chat with AI about your finances — ask anything, get personalized answers.",
            descriptionZH: "跟 AI 聊你的財務狀況 — 隨時提問，獲得個人化回答。",
            accentColor: Color(red: 0.93, green: 0.29, blue: 0.60), // #ec4899
            iconName: "bubble.left.and.bubble.right.fill"
        ),
        FeatureCard(
            index: 4,
            titleEN: "Financial Analysis",
            titleZH: "財務分析",
            descriptionEN: "AI analyzes your spending habits and provides actionable insights.",
            descriptionZH: "AI 分析消費習慣，提供可執行的建議。",
            accentColor: Color(red: 0.55, green: 0.36, blue: 0.96), // #8b5cf6
            iconName: "chart.pie.fill"
        ),
        FeatureCard(
            index: 5,
            titleEN: "Goal Tracking",
            titleZH: "財務目標",
            descriptionEN: "Set savings goals, track progress, and get AI suggestions to stay on track.",
            descriptionZH: "設定儲蓄目標，追蹤進度，AI 助你達標。",
            accentColor: Color(red: 0.13, green: 0.77, blue: 0.37), // #22c55e
            iconName: "target"
        ),
    ]
}

struct FeatureCardView: View {
    let card: FeatureCard
    let language: String
    let isVisible: Bool
    let isLastCard: Bool
    let onGetStarted: () -> Void

    @State private var animateIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated illustration area
            ZStack {
                // Radial glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [card.accentColor.opacity(0.2), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                // Main icon
                Image(systemName: card.iconName)
                    .font(.system(size: 56))
                    .foregroundStyle(card.accentColor)
                    .scaleEffect(animateIn ? 1.0 : 0.5)
                    .opacity(animateIn ? 1.0 : 0.0)

                // Floating accent elements
                floatingElements
            }
            .frame(height: 220)

            // Title
            Text(card.title(language: language))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(red: 0.91, green: 0.93, blue: 0.96)) // #e8edf5
                .padding(.top, 24)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 10)

            // Description
            Text(card.description(language: language))
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.48, green: 0.55, blue: 0.66)) // #7a8ba8
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(4)
                .padding(.top, 10)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 10)

            // Get Started button (last card only)
            if isLastCard {
                Button(action: onGetStarted) {
                    Text(language == "zh-Hant" ? "開始設定 →" : "Get Started →")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.11, green: 0.31, blue: 0.85), Color(red: 0.15, green: 0.39, blue: 0.92)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color(red: 0.15, green: 0.39, blue: 0.92).opacity(0.3), radius: 8, y: 4)
                }
                .padding(.top, 32)
                .opacity(animateIn ? 1.0 : 0.0)
                .scaleEffect(animateIn ? 1.0 : 0.9)
            }

            Spacer()
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                animateIn = false
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    animateIn = true
                }
            } else {
                animateIn = false
            }
        }
        .onAppear {
            if isVisible {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                    animateIn = true
                }
            }
        }
    }

    @ViewBuilder
    private var floatingElements: some View {
        switch card.index {
        case 0: // Smart Extraction — floating transaction chips
            Group {
                chipView("☕ $45", offset: CGSize(width: 70, height: -60), rotation: 5)
                chipView("🍔 $189", offset: CGSize(width: -75, height: -30), rotation: -8)
                chipView("🛒 $520", offset: CGSize(width: 60, height: 50), rotation: -3)
            }
        case 1: // Dashboard — bar chart bars
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(card.accentColor.opacity(0.6))
                        .frame(width: 12, height: animateIn ? CGFloat([30, 50, 40, 65, 45][i]) : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(Double(i) * 0.08), value: animateIn)
                }
            }
            .offset(y: 70)
        case 2: // Spending Diary — pen + diary snippet
            Group {
                Image(systemName: "pencil.line")
                    .font(.system(size: 24))
                    .foregroundStyle(card.accentColor)
                    .offset(x: 55, y: 40)
                    .opacity(animateIn ? 1 : 0)
                    .offset(x: animateIn ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: animateIn)
            }
        case 3: // AI Advisory — chat bubbles
            Group {
                chatBubble(isUser: false, offset: CGSize(width: -50, height: -50))
                chatBubble(isUser: true, offset: CGSize(width: 50, height: 10))
                chatBubble(isUser: false, offset: CGSize(width: -40, height: 55))
            }
        case 4: // Financial Analysis — pie segments
            Group {
                pieSegment(startAngle: 0, endAngle: 120, color: card.accentColor)
                pieSegment(startAngle: 120, endAngle: 220, color: card.accentColor.opacity(0.6))
                pieSegment(startAngle: 220, endAngle: 360, color: card.accentColor.opacity(0.3))
            }
            .offset(y: 70)
        case 5: // Goal Tracking — progress bar
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(red: 0.10, green: 0.16, blue: 0.26))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(colors: [card.accentColor, card.accentColor.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                            )
                            .frame(width: animateIn ? geo.size.width * 0.72 : 0, height: 8)
                            .animation(.easeOut(duration: 1.0).delay(0.3), value: animateIn)
                    }
                }
                .frame(width: 140, height: 8)
                Text("72%")
                    .font(.system(size: 10))
                    .foregroundStyle(card.accentColor)
                    .frame(width: 140, alignment: .trailing)
                    .opacity(animateIn ? 1 : 0)
            }
            .offset(y: 70)
        default:
            EmptyView()
        }
    }

    private func chipView(_ text: String, offset: CGSize, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Color(red: 0.38, green: 0.65, blue: 0.98))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.06, green: 0.16, blue: 0.28))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.12, green: 0.23, blue: 0.37), lineWidth: 1))
            .rotationEffect(.degrees(rotation))
            .offset(offset)
            .scaleEffect(animateIn ? 1.0 : 0.3)
            .opacity(animateIn ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double.random(in: 0.1...0.3)), value: animateIn)
    }

    private func chatBubble(isUser: Bool, offset: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isUser ? card.accentColor.opacity(0.3) : Color(red: 0.06, green: 0.16, blue: 0.28))
            .frame(width: isUser ? 40 : 50, height: 20)
            .offset(offset)
            .opacity(animateIn ? 1 : 0)
            .offset(x: animateIn ? 0 : (isUser ? 30 : -30))
            .animation(.easeOut(duration: 0.4).delay(isUser ? 0.4 : 0.2), value: animateIn)
    }

    private func pieSegment(startAngle: Double, endAngle: Double, color: Color) -> some View {
        Circle()
            .trim(from: startAngle / 360, to: animateIn ? endAngle / 360 : startAngle / 360)
            .stroke(color, lineWidth: 12)
            .frame(width: 60, height: 60)
            .rotationEffect(.degrees(-90))
            .animation(.spring(response: 0.6).delay(0.2), value: animateIn)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds (view not yet used anywhere)

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/FeatureCardView.swift
git commit -m "feat(onboarding): add FeatureCardView with animated illustrations"
```

---

## Chunk 2: FeatureTourView Container

### Task 2: Create FeatureTourView

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift`

- [ ] **Step 1: Create FeatureTourView**

```swift
// LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift
import SwiftUI

struct FeatureTourView: View {
    @AppStorage("appLanguage") private var appLanguage = {
        Locale.current.language.languageCode?.identifier == "zh" ? "zh-Hant" : "en"
    }()

    @State private var currentPage = 0
    let onComplete: () -> Void

    private let cards = FeatureCard.allCards

    var body: some View {
        ZStack {
            // Deep blue gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.10), // #060d1a
                    Color(red: 0.05, green: 0.11, blue: 0.18), // #0d1b2e
                    Color(red: 0.07, green: 0.13, blue: 0.25), // #112240
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: LedgeIt label + Skip + Language toggle
                HStack {
                    Text("LedgeIt")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.29, green: 0.42, blue: 0.54))
                        .tracking(2)
                        .textCase(.uppercase)

                    Spacer()

                    // Language toggle
                    Button {
                        appLanguage = appLanguage == "zh-Hant" ? "en" : "zh-Hant"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(appLanguage == "zh-Hant" ? "繁中" : "EN")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.23, green: 0.35, blue: 0.48))
                    }
                    .buttonStyle(.plain)

                    // Skip button
                    Button(appLanguage == "zh-Hant" ? "略過" : "Skip") {
                        onComplete()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.23, green: 0.35, blue: 0.48))
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        FeatureCardView(
                            card: card,
                            language: appLanguage,
                            isVisible: currentPage == index,
                            isLastCard: index == cards.count - 1,
                            onGetStarted: onComplete
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Custom page dots
                HStack(spacing: 8) {
                    ForEach(0..<cards.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? cards[index].accentColor : Color(red: 0.10, green: 0.16, blue: 0.26))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/FeatureTourView.swift
git commit -m "feat(onboarding): add FeatureTourView container with TabView and language toggle"
```

---

## Chunk 3: Integration into ContentView + OnboardingViewModel

### Task 3: Wire FeatureTourView into ContentView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

- [ ] **Step 1: Add feature tour state and conditional**

In ContentView, find the existing onboarding check (around line 44 and 52-55):

```swift
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
```

Add a new AppStorage property nearby:

```swift
@AppStorage("hasCompletedFeatureTour") private var hasCompletedFeatureTour = false
```

Then modify the body conditional. Currently it is:

```swift
if !hasCompletedOnboarding {
    OnboardingChatView()
        .frame(minWidth: 960, minHeight: 640)
} else {
```

Change to:

```swift
if !hasCompletedOnboarding {
    if !hasCompletedFeatureTour {
        FeatureTourView {
            hasCompletedFeatureTour = true
        }
        .frame(minWidth: 960, minHeight: 640)
    } else {
        OnboardingChatView()
            .frame(minWidth: 960, minHeight: 640)
    }
} else {
```

- [ ] **Step 2: Build and verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat(onboarding): wire FeatureTourView before chat wizard in ContentView"
```

### Task 4: Sync language to OnboardingViewModel

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift`

- [ ] **Step 1: Read appLanguage on init**

In `OnboardingViewModel.init()`, after the existing initialization, add:

```swift
// If feature tour already set a language preference, use it
if UserDefaults.standard.object(forKey: "appLanguage") != nil,
   let tourLanguage = UserDefaults.standard.string(forKey: "appLanguage") {
    self.selectedLanguage = tourLanguage
    self.strings = OnboardingStrings(language: tourLanguage)
    UserDefaults.standard.set(tourLanguage, forKey: "onboardingLanguage")
}
```

This ensures if the user set a language in the feature tour (English or Chinese), the chat wizard starts in that language.

- [ ] **Step 2: Build and verify**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Run all tests**

Run: `cd LedgeIt && swift test 2>&1 | tail -20`
Expected: All existing tests still pass

- [ ] **Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift
git commit -m "feat(onboarding): sync feature tour language selection to chat wizard"
```

### Task 5: Final Build and Verification

- [ ] **Step 1: Full build**

Run: `cd LedgeIt && swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 2: Run tests**

Run: `cd LedgeIt && swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 3: Final commit if needed**

```bash
git status
# Only commit if there are uncommitted changes
```
