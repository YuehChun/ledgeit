# Onboarding Chat Flow Design

## Overview

Replace the current static onboarding screen with an AI-guided, chat-based onboarding experience. The onboarding uses a full-screen chat interface with auto-managed floating form cards for user input. A hybrid approach uses scripted messages before the API key is configured, then switches to real LLM responses afterward.

## Decisions

| Decision | Choice |
|----------|--------|
| Layout | Full-screen chat + floating card overlay for forms |
| AI mode | Hybrid: scripted (steps 1-2) → real LLM (steps 3-7) |
| Step progression | Strictly linear, no skip, no back |
| Language | Select before API key, switches all subsequent messages |
| Card behavior | Auto-managed: appears for input, hides during AI talk |
| Email sync | Always 2 months, no user choice |
| PDF password | Auto-skip if no password-protected PDFs found |
| Low transaction data | Proceed anyway with whatever is available |
| Final transition | Chat feature overview + "Get Started" button |

## Architecture: Single OnboardingChatView

One self-contained view with its own view model. Reuses existing services directly. Chat messages stored in-memory only (not persisted to DB). Floating card is a SwiftUI overlay driven by the current step.

## State Machine

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome          // Language selection
    case apiKey           // OpenAI/OpenRouter API key + endpoint URL
    case apiKeyTest       // Auto-test with gpt-5-mini chat completion
    case gmailAuth        // Google Client ID + Secret, then OAuth browser flow
    case emailSync        // Auto-sync 2 months, show progress
    case emailReview      // User reviews/approves extracted emails
    case pdfPassword      // Ask for PDF passwords (auto-skip if none needed)
    case financialReport  // Run FinancialAdvisor, show report in chat
    case suggestions      // Ask if user wants suggestions, generate them
    case complete         // Feature overview + "Get Started" button
}
```

Each step has a `canAdvance` condition. The view model advances only when conditions are met. Some steps auto-advance (apiKeyTest succeeds → gmailAuth, emailSync completes → emailReview). `currentStep` persisted in UserDefaults for resume on quit. `hasCompletedOnboarding` boolean marks final completion.

## View Architecture

```
OnboardingChatView (full screen, replaces ContentView when !hasCompletedOnboarding)
├── ZStack
│   ├── Chat area (ScrollView)
│   │   ├── ChatBubble (assistant) — left-aligned
│   │   ├── ChatBubble (user) — right-aligned
│   │   └── TypingIndicator (during LLM streaming)
│   │
│   ├── Floating FormCard (overlay, centered/top area)
│   │   ├── Appears when step needs user input
│   │   ├── Auto-hides when AI is responding
│   │   ├── Content varies by step:
│   │   │   ├── welcome: Language picker (English / 繁體中文)
│   │   │   ├── apiKey: Endpoint URL + API key fields + "Connect" button
│   │   │   ├── gmailAuth: Client ID + Secret fields + "Authenticate" button
│   │   │   ├── emailReview: List of extracted emails with confirm button
│   │   │   ├── pdfPassword: Bank name + password fields + "Submit" button
│   │   │   └── suggestions: Confirmation button
│   │   └── Validation errors shown inline
│   │
│   └── Bottom chat input (text field + send button)
│       ├── Always visible for user questions
│       ├── Scripted steps: echoes user text, responds with template
│       └── LLM steps: sends to real LLM for response
```

FormCard slides in from top with animation, has semi-transparent background blur, max-width ~400pt. Steps without form input (apiKeyTest, emailSync, financialReport) show no card — just chat messages with progress.

## Hybrid Chat Logic

### Scripted Phase (steps 1-2: welcome, apiKey, apiKeyTest)

`OnboardingMessage` structs stored in-memory:

```swift
struct OnboardingMessage: Identifiable {
    let id: UUID
    let role: MessageRole  // .assistant or .user
    let content: String
    let timestamp: Date
}
```

Scripted messages are localized strings keyed by step + language. On user form submission:
1. Append user message
2. Show typing indicator (brief delay)
3. Append scripted assistant response
4. Advance step if conditions met

API key test: creates `OpenAICompatibleSession`, sends test prompt to gpt-5-mini. Success → auto-advance. Failure → error message, FormCard reappears.

### LLM Phase (steps 3-7: gmailAuth onward)

Once API key is validated, creates `LLMSession` via `SessionFactory`. Steps needing AI content (financialReport, suggestions) call the session with crafted prompts, streaming into chat. Intermediate steps (emailSync, emailReview, pdfPassword) use templates but route user chat questions to real LLM.

## Service Integration

| Step | Service | Usage |
|------|---------|-------|
| apiKey | AIProviderConfigStore | Save endpoint + key to config |
| apiKey | KeychainService | Store API key in Keychain |
| apiKeyTest | SessionFactory → OpenAICompatibleSession | Test completion to gpt-5-mini |
| gmailAuth | KeychainService | Save Client ID + Secret |
| gmailAuth | GoogleAuthService | Trigger OAuth browser flow |
| emailSync | SyncService | Sync with 60-day lookback |
| emailReview | AppDatabase | Query synced emails |
| emailReview | ExtractionPipeline | Run extraction on confirmed emails |
| pdfPassword | AppDatabase | Query emails with PDF attachments |
| pdfPassword | KeychainService | Save statement passwords |
| financialReport | SpendingAnalyzer | Generate MonthlyReport + MonthTrend |
| financialReport | FinancialAdvisor | analyzeSpendingHabits() |
| suggestions | FinancialAdvisor / direct LLM | Generate actionable suggestions |

No new services needed. Entry point change: `ContentView.swift` shows `OnboardingChatView` when `!hasCompletedOnboarding` instead of the old `OnboardingView`.

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Invalid API key | Test fails → error in chat + FormCard reappears |
| Invalid endpoint URL | Inline validation error in FormCard |
| Gmail OAuth denied/failed | Chat explains error, "Try Again" in FormCard |
| OAuth browser not opening | Chat provides manual URL to copy |
| Email sync fails | Chat error, auto-retry once, then suggest checking credentials |
| No emails found | Chat acknowledges, proceeds to next step |
| PDF password wrong | Chat explains, FormCard reappears for retry |
| No PDF attachments | Auto-skip pdfPassword step with chat explanation |
| 0 transactions for report | Proceeds with minimal report |
| User quits mid-onboarding | currentStep persisted, resumes on next launch |
| User types question (scripted) | Generic help template response |
| User types question (LLM) | Route to real LLM with onboarding context |
| Network lost | Chat error, retry button in FormCard |

On resume after quit: reload credentials from Keychain, re-validate completed steps, show "Welcome back" and continue from saved step. If previously valid credentials expired, step back to the failed step.
