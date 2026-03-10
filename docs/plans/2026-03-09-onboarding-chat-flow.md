# Onboarding Chat Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the static onboarding screen with an AI-guided chat-based onboarding that walks users through API setup, Gmail auth, email sync, review, and financial analysis.

**Architecture:** Single `OnboardingChatView` with `OnboardingViewModel` (ObservableObject). Full-screen chat + auto-managed floating form cards. Hybrid: scripted messages before API key, real LLM after. Strictly linear step progression persisted in UserDefaults.

**Tech Stack:** Swift 6.2, SwiftUI, GRDB, Keychain, existing services (SessionFactory, GoogleAuthService, SyncService, ExtractionPipeline, FinancialAdvisor, SpendingAnalyzer)

**Design doc:** `docs/plans/2026-03-09-onboarding-chat-flow-design.md`

---

### Task 1: OnboardingStep enum and OnboardingMessage model

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingTypes.swift`

**Step 1: Create the types file**

```swift
import Foundation

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case apiKey
    case apiKeyTest
    case gmailAuth
    case emailSync
    case emailReview
    case pdfPassword
    case financialReport
    case suggestions
    case complete

    var needsFormCard: Bool {
        switch self {
        case .welcome, .apiKey, .gmailAuth, .emailReview, .pdfPassword, .suggestions:
            return true
        case .apiKeyTest, .emailSync, .financialReport, .complete:
            return false
        }
    }

    var isAutoAdvance: Bool {
        switch self {
        case .apiKeyTest, .emailSync:
            return true
        default:
            return false
        }
    }
}

enum MessageRole {
    case assistant
    case user
}

struct OnboardingMessage: Identifiable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date

    init(role: MessageRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingTypes.swift
git commit -m "feat(onboarding): add OnboardingStep enum and OnboardingMessage model"
```

---

### Task 2: Onboarding localized strings

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingStrings.swift`

**Step 1: Create the localized strings provider**

This struct holds all scripted messages keyed by step and language. The LLM phase steps have template messages for progress/instructions, while the actual analysis content comes from the real LLM.

```swift
import Foundation

struct OnboardingStrings {
    let language: String // "en" or "zh-Hant"

    // MARK: - Welcome Step
    var welcomeGreeting: String {
        language == "zh-Hant"
            ? "歡迎使用 LedgeIt！我是你的設定助手，將引導你完成應用程式的初始設定。\n\n首先，請選擇你偏好的語言。"
            : "Welcome to LedgeIt! I'm your setup assistant and I'll guide you through the initial configuration.\n\nFirst, please select your preferred language."
    }

    var languageSelected: String {
        language == "zh-Hant"
            ? "太好了！接下來的所有說明將以繁體中文顯示。"
            : "Great! All instructions will be displayed in English from now on."
    }

    // MARK: - API Key Step
    var apiKeyIntro: String {
        language == "zh-Hant"
            ? "接下來，我們需要設定 AI 服務。LedgeIt 使用 AI 來分類和提取你的財務交易資料。\n\n請輸入你的 OpenAI 或 OpenRouter API Key 和端點 URL。"
            : "Next, we need to set up the AI service. LedgeIt uses AI to classify and extract your financial transactions.\n\nPlease enter your OpenAI or OpenRouter API Key and endpoint URL."
    }

    var apiKeyTesting: String {
        language == "zh-Hant"
            ? "正在測試你的 API Key..."
            : "Testing your API Key..."
    }

    var apiKeySuccess: String {
        language == "zh-Hant"
            ? "API Key 驗證成功！AI 服務已就緒。"
            : "API Key verified successfully! AI service is ready."
    }

    func apiKeyError(_ error: String) -> String {
        language == "zh-Hant"
            ? "API Key 驗證失敗：\(error)\n\n請檢查你的 API Key 和端點 URL 是否正確，然後重試。"
            : "API Key verification failed: \(error)\n\nPlease check your API Key and endpoint URL, then try again."
    }

    // MARK: - Gmail Auth Step
    var gmailAuthIntro: String {
        language == "zh-Hant"
            ? "接下來，我們需要連接你的 Gmail 帳號來讀取財務相關的電子郵件。\n\n請輸入你的 Google OAuth Client ID 和 Client Secret。\n\n如果你還沒有，請前往 [Google Cloud Console](https://console.cloud.google.com/apis/credentials) 建立一個 OAuth 2.0 用戶端。"
            : "Next, we need to connect your Gmail account to read financial emails.\n\nPlease enter your Google OAuth Client ID and Client Secret.\n\nIf you don't have one yet, visit [Google Cloud Console](https://console.cloud.google.com/apis/credentials) to create an OAuth 2.0 client."
    }

    var gmailAuthenticating: String {
        language == "zh-Hant"
            ? "正在開啟瀏覽器進行 Google 認證..."
            : "Opening browser for Google authentication..."
    }

    var gmailAuthSuccess: String {
        language == "zh-Hant"
            ? "Gmail 認證成功！已連接到你的帳號。"
            : "Gmail authentication successful! Connected to your account."
    }

    func gmailAuthError(_ error: String) -> String {
        language == "zh-Hant"
            ? "Gmail 認證失敗：\(error)\n\n請確認你的 Client ID 和 Secret 是否正確，然後重試。"
            : "Gmail authentication failed: \(error)\n\nPlease verify your Client ID and Secret, then try again."
    }

    // MARK: - Email Sync Step
    var emailSyncIntro: String {
        language == "zh-Hant"
            ? "現在開始同步你過去兩個月的電子郵件..."
            : "Now syncing your emails from the past 2 months..."
    }

    func emailSyncProgress(_ progress: String) -> String {
        language == "zh-Hant"
            ? "同步進度：\(progress)"
            : "Sync progress: \(progress)"
    }

    func emailSyncComplete(_ count: Int) -> String {
        language == "zh-Hant"
            ? "同步完成！共找到 \(count) 封電子郵件。正在處理和提取財務資料..."
            : "Sync complete! Found \(count) emails. Processing and extracting financial data..."
    }

    var emailSyncNoEmails: String {
        language == "zh-Hant"
            ? "同步完成，但未找到電子郵件。這可能是因為你的 Gmail 中沒有財務相關的郵件。我們繼續下一步吧。"
            : "Sync complete, but no emails were found. This might be because there are no financial emails in your Gmail. Let's continue to the next step."
    }

    // MARK: - Email Review Step
    var emailReviewIntro: String {
        language == "zh-Hant"
            ? "以下是我們提取的交易記錄，請確認是否正確。"
            : "Here are the extracted transactions. Please review and confirm they look correct."
    }

    var emailReviewConfirmed: String {
        language == "zh-Hant"
            ? "太好了！交易記錄已確認。"
            : "Great! Transactions have been confirmed."
    }

    // MARK: - PDF Password Step
    var pdfPasswordIntro: String {
        language == "zh-Hant"
            ? "我們發現了一些需要密碼的 PDF 附件（通常是信用卡帳單）。請輸入 PDF 密碼以解鎖這些文件。"
            : "We found some PDF attachments that require a password (usually credit card statements). Please enter the PDF password to unlock these documents."
    }

    var pdfPasswordSkipped: String {
        language == "zh-Hant"
            ? "沒有發現需要密碼的 PDF 附件，跳過此步驟。"
            : "No password-protected PDF attachments found, skipping this step."
    }

    var pdfPasswordSuccess: String {
        language == "zh-Hant"
            ? "PDF 密碼設定成功！正在解鎖並提取文件內容..."
            : "PDF password set successfully! Unlocking and extracting document contents..."
    }

    func pdfPasswordError(_ error: String) -> String {
        language == "zh-Hant"
            ? "PDF 密碼不正確：\(error)\n\n請重新輸入正確的密碼。"
            : "PDF password incorrect: \(error)\n\nPlease re-enter the correct password."
    }

    // MARK: - Financial Report Step
    var financialReportGenerating: String {
        language == "zh-Hant"
            ? "正在分析你的財務資料並生成報告..."
            : "Analyzing your financial data and generating a report..."
    }

    // MARK: - Suggestions Step
    var suggestionsAsk: String {
        language == "zh-Hant"
            ? "是否要我為你生成個人化的財務建議？"
            : "Would you like me to generate personalized financial suggestions for you?"
    }

    var suggestionsGenerating: String {
        language == "zh-Hant"
            ? "正在為你生成財務建議..."
            : "Generating financial suggestions for you..."
    }

    // MARK: - Complete Step
    var completeIntro: String {
        language == "zh-Hant"
            ? """
            設定完成！以下是 LedgeIt 提供的所有功能：

            📊 **儀表板** — 財務總覽與趨勢圖表
            💬 **AI 聊天** — 與 AI 助手討論你的財務狀況
            💳 **交易記錄** — 瀏覽和搜尋所有交易
            📧 **郵件** — 查看已同步的財務郵件
            📅 **行事曆** — 繳費日期與到期提醒
            📄 **帳單** — 信用卡帳單管理
            📈 **分析** — 深度消費分析報告
            🎯 **目標** — 設定和追蹤財務目標
            🧑‍💼 **顧問** — AI 財務顧問建議

            點擊「開始使用」進入主畫面！
            """
            : """
            Setup complete! Here are all the features LedgeIt offers:

            📊 **Dashboard** — Financial overview with trend charts
            💬 **AI Chat** — Discuss your finances with the AI assistant
            💳 **Transactions** — Browse and search all transactions
            📧 **Emails** — View synced financial emails
            📅 **Calendar** — Payment dates and due date reminders
            📄 **Statements** — Credit card statement management
            📈 **Analysis** — In-depth spending analysis reports
            🎯 **Goals** — Set and track financial goals
            🧑‍💼 **Advisor** — AI financial advisor suggestions

            Click "Get Started" to enter the main app!
            """
    }

    // MARK: - Chat Helpers
    var helpResponse: String {
        language == "zh-Hant"
            ? "我是你的設定助手。請按照上方的表單完成當前步驟。如果你有任何問題，請隨時在這裡輸入。"
            : "I'm your setup assistant. Please complete the current step using the form above. If you have any questions, feel free to type here."
    }

    var welcomeBack: String {
        language == "zh-Hant"
            ? "歡迎回來！讓我們繼續之前的設定。"
            : "Welcome back! Let's continue where we left off."
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingStrings.swift
git commit -m "feat(onboarding): add localized scripted messages for all onboarding steps"
```

---

### Task 3: OnboardingViewModel — state machine and scripted phase

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift`

**Step 1: Create the view model**

This is the core state machine. It manages step progression, messages, and form card visibility. This task covers the scripted phase (welcome, apiKey, apiKeyTest). LLM-phase steps will be added in Task 4.

```swift
import Foundation
import SwiftUI

@MainActor
final class OnboardingViewModel: ObservableObject {
    // MARK: - State
    @Published var currentStep: OnboardingStep {
        didSet { UserDefaults.standard.set(currentStep.rawValue, forKey: "onboardingCurrentStep") }
    }
    @Published var messages: [OnboardingMessage] = []
    @Published var isTyping = false
    @Published var showFormCard = false
    @Published var formError: String?
    @Published var isProcessing = false

    // MARK: - Form Fields
    @Published var endpointName = "OpenRouter"
    @Published var endpointURL = "https://openrouter.ai/api/v1"
    @Published var apiKey = ""
    @Published var googleClientID = ""
    @Published var googleClientSecret = ""
    @Published var pdfBankName = ""
    @Published var pdfCardLabel = ""
    @Published var pdfPassword = ""

    // MARK: - Sync/Review State
    @Published var syncProgress = ""
    @Published var syncedEmailCount = 0
    @Published var extractedTransactionCount = 0
    @Published var pendingPDFAttachments: [(emailSubject: String, sender: String)] = []

    // MARK: - Services
    private let authService = GoogleAuthService()
    private var llmSession: (any LLMSession)?

    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "appLanguage") }
    }
    var strings: OnboardingStrings { OnboardingStrings(language: language) }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
    }

    // MARK: - Init
    init() {
        let savedStep = UserDefaults.standard.integer(forKey: "onboardingCurrentStep")
        self.currentStep = OnboardingStep(rawValue: savedStep) ?? .welcome
        self.language = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
    }

    // MARK: - Lifecycle
    func onAppear() async {
        if messages.isEmpty {
            if currentStep == .welcome {
                await appendAssistantMessage(strings.welcomeGreeting)
                showFormCard = true
            } else {
                await appendAssistantMessage(strings.welcomeBack)
                await resumeStep()
            }
        }
    }

    // MARK: - Step Entry
    private func resumeStep() async {
        // Re-validate and enter the current step
        await enterStep(currentStep)
    }

    private func enterStep(_ step: OnboardingStep) async {
        currentStep = step
        formError = nil

        switch step {
        case .welcome:
            showFormCard = true
        case .apiKey:
            await appendAssistantMessage(strings.apiKeyIntro)
            showFormCard = true
        case .apiKeyTest:
            showFormCard = false
            await testAPIKey()
        case .gmailAuth:
            await appendAssistantMessage(strings.gmailAuthIntro)
            showFormCard = true
        case .emailSync:
            showFormCard = false
            await performEmailSync()
        case .emailReview:
            await appendAssistantMessage(strings.emailReviewIntro)
            showFormCard = true
        case .pdfPassword:
            await checkAndEnterPDFStep()
        case .financialReport:
            showFormCard = false
            await generateFinancialReport()
        case .suggestions:
            await appendAssistantMessage(strings.suggestionsAsk)
            showFormCard = true
        case .complete:
            showFormCard = false
            await appendAssistantMessage(strings.completeIntro)
        }
    }

    private func advanceToNext() async {
        guard let nextIndex = OnboardingStep.allCases.firstIndex(of: currentStep)
            .map({ OnboardingStep.allCases.index(after: $0) }),
              nextIndex < OnboardingStep.allCases.endIndex else {
            return
        }
        let next = OnboardingStep.allCases[nextIndex]
        await enterStep(next)
    }

    // MARK: - Welcome Step
    func selectLanguage(_ lang: String) async {
        language = lang
        let displayName = lang == "zh-Hant" ? "繁體中文" : "English"
        await appendUserMessage(displayName)
        showFormCard = false
        await appendAssistantMessage(strings.languageSelected)
        await advanceToNext()
    }

    // MARK: - API Key Step
    func submitAPIKey() async {
        guard !apiKey.isEmpty else {
            formError = language == "zh-Hant" ? "請輸入 API Key" : "Please enter an API Key"
            return
        }
        guard !endpointURL.isEmpty, URL(string: endpointURL) != nil else {
            formError = language == "zh-Hant" ? "請輸入有效的端點 URL" : "Please enter a valid endpoint URL"
            return
        }

        let maskedKey = String(apiKey.prefix(8)) + "..."
        await appendUserMessage("API Key: \(maskedKey)\nEndpoint: \(endpointURL)")
        showFormCard = false

        // Save endpoint to config
        var config = AIProviderConfigStore.load()
        let endpoint = OpenAICompatibleEndpoint(
            name: endpointName,
            baseURL: endpointURL,
            requiresAPIKey: true,
            defaultModel: "gpt-5-mini"
        )

        // Add or replace endpoint
        if let existingIndex = config.endpoints.firstIndex(where: { $0.name == endpointName }) {
            config.endpoints[existingIndex] = endpoint
        } else {
            config.endpoints.append(endpoint)
        }

        // Assign to all use cases
        let assignment = ModelAssignment(
            provider: .openAICompatible,
            endpointId: endpoint.id,
            model: "gpt-5-mini"
        )
        config.classification = assignment
        config.extraction = assignment
        config.statement = assignment
        config.chat = assignment
        AIProviderConfigStore.save(config)

        // Save API key
        KeychainService.saveEndpointAPIKey(endpointId: endpoint.id, value: apiKey)

        await advanceToNext()
    }

    // MARK: - API Key Test
    private func testAPIKey() async {
        await appendAssistantMessage(strings.apiKeyTesting)
        isProcessing = true

        do {
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(assignment: config.chat, config: config)
            let testMessages = [LLMMessage(role: .user, content: "Say 'Hello' in one word.")]
            let response = try await session.complete(messages: testMessages)

            isProcessing = false

            if !response.isEmpty {
                await appendAssistantMessage(strings.apiKeySuccess)
                llmSession = session
                await advanceToNext()
            } else {
                await appendAssistantMessage(strings.apiKeyError("Empty response"))
                currentStep = .apiKey
                showFormCard = true
            }
        } catch {
            isProcessing = false
            await appendAssistantMessage(strings.apiKeyError(error.localizedDescription))
            currentStep = .apiKey
            showFormCard = true
        }
    }

    // MARK: - Gmail Auth Step
    func submitGmailCredentials() async {
        guard !googleClientID.isEmpty else {
            formError = language == "zh-Hant" ? "請輸入 Client ID" : "Please enter Client ID"
            return
        }
        guard !googleClientSecret.isEmpty else {
            formError = language == "zh-Hant" ? "請輸入 Client Secret" : "Please enter Client Secret"
            return
        }

        await appendUserMessage("Client ID: \(String(googleClientID.prefix(20)))...")
        showFormCard = false

        // Save to Keychain
        KeychainService.save(key: .googleClientID, value: googleClientID)
        KeychainService.save(key: .googleClientSecret, value: googleClientSecret)

        await appendAssistantMessage(strings.gmailAuthenticating)
        isProcessing = true

        do {
            try await authService.signIn()
            isProcessing = false
            await appendAssistantMessage(strings.gmailAuthSuccess)
            await advanceToNext()
        } catch {
            isProcessing = false
            await appendAssistantMessage(strings.gmailAuthError(error.localizedDescription))
            showFormCard = true
        }
    }

    // MARK: - Email Sync Step
    private func performEmailSync() async {
        await appendAssistantMessage(strings.emailSyncIntro)
        isProcessing = true

        do {
            let db = AppDatabase.shared
            let syncService = SyncService(database: db)
            syncService.configure(accessTokenProvider: { [weak self] in
                guard self != nil else { throw SyncServiceError.notConfigured }
                return try await GoogleAuthService().getValidAccessToken()
            })

            // Sync 60 days
            try await syncService.performInitialSync(lookbackDays: 60)

            // Count synced emails
            let emailCount = try await db.reader.read { db in
                try Email.fetchCount(db)
            }
            syncedEmailCount = emailCount

            if emailCount == 0 {
                isProcessing = false
                await appendAssistantMessage(strings.emailSyncNoEmails)
                await advanceToNext()
                return
            }

            await appendAssistantMessage(strings.emailSyncComplete(emailCount))

            // Run extraction pipeline
            let pipeline = ExtractionPipeline(database: db)
            try await pipeline.processUnprocessedEmails()

            let txCount = try await db.reader.read { db in
                try Transaction.fetchCount(db)
            }
            extractedTransactionCount = txCount

            isProcessing = false
            await advanceToNext()
        } catch {
            isProcessing = false
            await appendAssistantMessage(strings.emailSyncIntro + "\n\nError: \(error.localizedDescription)")
        }
    }

    // MARK: - Email Review Step
    func confirmEmailReview() async {
        await appendUserMessage(language == "zh-Hant" ? "確認" : "Confirmed")
        showFormCard = false
        await appendAssistantMessage(strings.emailReviewConfirmed)
        await advanceToNext()
    }

    // MARK: - PDF Password Step
    private func checkAndEnterPDFStep() async {
        // Check if there are PDF attachments that need passwords
        do {
            let db = AppDatabase.shared
            let hasPDFs = try await db.reader.read { db in
                try Attachment.filter(Column("mimeType") == "application/pdf").fetchCount(db) > 0
            }

            if !hasPDFs {
                await appendAssistantMessage(strings.pdfPasswordSkipped)
                await advanceToNext()
                return
            }

            await appendAssistantMessage(strings.pdfPasswordIntro)
            showFormCard = true
        } catch {
            await appendAssistantMessage(strings.pdfPasswordSkipped)
            await advanceToNext()
        }
    }

    func submitPDFPassword() async {
        guard !pdfPassword.isEmpty else {
            formError = language == "zh-Hant" ? "請輸入密碼" : "Please enter a password"
            return
        }

        await appendUserMessage("\(pdfBankName) - ••••••")
        showFormCard = false

        // Save password
        var passwords = StatementPassword.loadAll()
        let newPassword = StatementPassword(
            id: UUID().uuidString,
            bankName: pdfBankName,
            cardLabel: pdfCardLabel,
            password: pdfPassword
        )
        passwords.append(newPassword)
        StatementPassword.saveAll(passwords: passwords)

        await appendAssistantMessage(strings.pdfPasswordSuccess)
        isProcessing = true

        // Re-run extraction with passwords
        do {
            let db = AppDatabase.shared
            let pipeline = ExtractionPipeline(database: db)
            try await pipeline.processUnprocessedEmails()
            isProcessing = false
        } catch {
            isProcessing = false
        }

        await advanceToNext()
    }

    // MARK: - Financial Report Step (LLM Phase)
    private func generateFinancialReport() async {
        await appendAssistantMessage(strings.financialReportGenerating)
        isProcessing = true

        do {
            let db = AppDatabase.shared
            let analyzer = SpendingAnalyzer(database: db)
            let report = try await analyzer.generateMonthlyReport()
            let trends = try await analyzer.getMonthlyTrends(months: 2)

            let advisor = FinancialAdvisor()
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(assignment: config.chat, config: config)

            let advice = try await advisor.analyzeSpendingHabits(
                report: report,
                trends: trends,
                language: language
            )

            isProcessing = false

            // Format advice as chat message
            var reportText = advice.overallAssessment + "\n\n"
            if !advice.positiveHabits.isEmpty {
                reportText += (language == "zh-Hant" ? "**正面習慣：**\n" : "**Positive Habits:**\n")
                for habit in advice.positiveHabits {
                    reportText += "• \(habit)\n"
                }
                reportText += "\n"
            }
            if !advice.concerns.isEmpty {
                reportText += (language == "zh-Hant" ? "**需注意事項：**\n" : "**Concerns:**\n")
                for concern in advice.concerns {
                    reportText += "• \(concern)\n"
                }
                reportText += "\n"
            }
            if !advice.actionItems.isEmpty {
                reportText += (language == "zh-Hant" ? "**建議行動：**\n" : "**Action Items:**\n")
                for item in advice.actionItems {
                    reportText += "• \(item)\n"
                }
            }

            await appendAssistantMessage(reportText)
            await advanceToNext()
        } catch {
            isProcessing = false
            let fallback = language == "zh-Hant"
                ? "由於資料有限，無法產生完整的財務報告。你可以在主畫面的「分析」功能中查看更多資訊。"
                : "Unable to generate a complete financial report due to limited data. You can check the Analysis feature in the main app for more details."
            await appendAssistantMessage(fallback)
            await advanceToNext()
        }
    }

    // MARK: - Suggestions Step (LLM Phase)
    func confirmSuggestions() async {
        await appendUserMessage(language == "zh-Hant" ? "是的，請生成建議" : "Yes, generate suggestions")
        showFormCard = false
        isProcessing = true
        await appendAssistantMessage(strings.suggestionsGenerating)

        do {
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(assignment: config.chat, config: config)

            // Build context from available data
            let db = AppDatabase.shared
            let analyzer = SpendingAnalyzer(database: db)
            let report = try await analyzer.generateMonthlyReport()

            let prompt = language == "zh-Hant"
                ? "根據以下月度消費報告，提供 3-5 個具體且可執行的財務建議。每個建議要說明好處。\n\n月度總支出：\(report.totalSpending)\n類別分佈：\(report.categoryBreakdown.map { "\($0.key): \($0.value)" }.joined(separator: ", "))"
                : "Based on the following monthly spending report, provide 3-5 specific and actionable financial suggestions. Explain the benefit of each.\n\nMonthly total spending: \(report.totalSpending)\nCategory breakdown: \(report.categoryBreakdown.map { "\($0.key): \($0.value)" }.joined(separator: ", "))"

            let messages = [LLMMessage(role: .user, content: prompt)]
            let response = try await session.complete(messages: messages)

            isProcessing = false
            await appendAssistantMessage(response)
        } catch {
            isProcessing = false
            let fallback = language == "zh-Hant"
                ? "暫時無法生成建議，你可以之後在「顧問」功能中獲取個人化的財務建議。"
                : "Unable to generate suggestions right now. You can get personalized financial advice from the Advisor feature later."
            await appendAssistantMessage(fallback)
        }

        await advanceToNext()
    }

    // MARK: - Complete Step
    func completeOnboarding() {
        Self.hasCompletedOnboarding = true
    }

    // MARK: - Chat Input (user questions)
    func sendChatMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await appendUserMessage(text)

        // If we have an LLM session (post API key validation), use it
        if currentStep.rawValue >= OnboardingStep.gmailAuth.rawValue {
            do {
                let config = AIProviderConfigStore.load()
                let session = try SessionFactory.makeSession(assignment: config.chat, config: config)
                let contextPrompt = language == "zh-Hant"
                    ? "你是 LedgeIt 應用程式的設定助手。使用者正在進行初始設定。請簡短回答他們的問題。\n\n使用者問題：\(text)"
                    : "You are the LedgeIt app setup assistant. The user is going through initial setup. Answer their question briefly.\n\nUser question: \(text)"
                let llmMessages = [LLMMessage(role: .user, content: contextPrompt)]
                let response = try await session.complete(messages: llmMessages)
                await appendAssistantMessage(response)
            } catch {
                await appendAssistantMessage(strings.helpResponse)
            }
        } else {
            // Scripted phase — generic help
            await appendAssistantMessage(strings.helpResponse)
        }
    }

    // MARK: - Message Helpers
    private func appendAssistantMessage(_ content: String) async {
        isTyping = true
        // Brief delay for natural feel
        try? await Task.sleep(for: .milliseconds(500))
        messages.append(OnboardingMessage(role: .assistant, content: content))
        isTyping = false
    }

    private func appendUserMessage(_ content: String) async {
        messages.append(OnboardingMessage(role: .user, content: content))
    }
}
```

**Note:** This file references services that exist in the codebase. Some method signatures may need adjustment during implementation — check the actual service APIs (SpendingAnalyzer, FinancialAdvisor, etc.) and adapt. The structure and flow are what matters here.

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -20`
Expected: Build succeeded (may need minor fixes for exact API signatures)

**Step 3: Fix any compilation errors**

Adjust method calls to match actual service APIs. Common fixes:
- `SpendingAnalyzer` init/method signatures
- `ExtractionPipeline` method names
- `SyncService` configuration pattern
- `Attachment` model column names

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingViewModel.swift
git commit -m "feat(onboarding): add OnboardingViewModel with state machine and hybrid chat logic"
```

---

### Task 4: OnboardingChatView — chat UI

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingChatView.swift`

**Step 1: Create the chat view**

```swift
import SwiftUI

struct OnboardingChatView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var chatInput = ""

    var body: some View {
        ZStack {
            // Background
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Chat area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicatorView()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastId = viewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Chat input
                HStack(spacing: 8) {
                    TextField(
                        viewModel.language == "zh-Hant" ? "輸入訊息..." : "Type a message...",
                        text: $chatInput
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendMessage() }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderless)
                }
                .padding()
            }

            // Floating FormCard overlay
            if viewModel.showFormCard {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                FormCardView(viewModel: viewModel)
                    .frame(maxWidth: 400)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.4), value: viewModel.showFormCard)
            }
        }
        .task {
            await viewModel.onAppear()
        }
    }

    private func sendMessage() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        chatInput = ""
        Task {
            await viewModel.sendChatMessage(text)
        }
    }
}

// MARK: - Chat Bubble
struct ChatBubbleView: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(.init(message.content)) // Supports markdown
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .assistant
                              ? Color(.controlBackgroundColor)
                              : Color.accentColor.opacity(0.15))
                )
                .frame(maxWidth: 500, alignment: message.role == .assistant ? .leading : .trailing)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicatorView: View {
    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            Text(String(repeating: "●", count: dotCount + 1))
                .foregroundColor(.secondary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.controlBackgroundColor))
                )
            Spacer()
        }
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingChatView.swift
git commit -m "feat(onboarding): add OnboardingChatView with chat bubbles and typing indicator"
```

---

### Task 5: FormCardView — floating form cards per step

**Files:**
- Create: `LedgeIt/LedgeIt/Views/Onboarding/FormCardView.swift`

**Step 1: Create the form card view**

```swift
import SwiftUI

struct FormCardView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            cardContent
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
                .shadow(radius: 20)
        )
        .padding()
    }

    @ViewBuilder
    private var cardContent: some View {
        switch viewModel.currentStep {
        case .welcome:
            welcomeCard
        case .apiKey:
            apiKeyCard
        case .gmailAuth:
            gmailAuthCard
        case .emailReview:
            emailReviewCard
        case .pdfPassword:
            pdfPasswordCard
        case .suggestions:
            suggestionsCard
        default:
            EmptyView()
        }
    }

    // MARK: - Welcome Card (Language Selection)
    private var welcomeCard: some View {
        VStack(spacing: 16) {
            Text("Select Language / 選擇語言")
                .font(.headline)

            HStack(spacing: 16) {
                Button("English") {
                    Task { await viewModel.selectLanguage("en") }
                }
                .buttonStyle(.borderedProminent)

                Button("繁體中文") {
                    Task { await viewModel.selectLanguage("zh-Hant") }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - API Key Card
    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == "zh-Hant" ? "AI 服務設定" : "AI Service Setup")
                .font(.headline)

            Picker(viewModel.language == "zh-Hant" ? "服務提供者" : "Provider", selection: $viewModel.endpointName) {
                Text("OpenRouter").tag("OpenRouter")
                Text("OpenAI").tag("OpenAI")
                Text("Custom").tag("Custom")
            }
            .onChange(of: viewModel.endpointName) { _, newValue in
                switch newValue {
                case "OpenRouter":
                    viewModel.endpointURL = "https://openrouter.ai/api/v1"
                case "OpenAI":
                    viewModel.endpointURL = "https://api.openai.com/v1"
                default:
                    viewModel.endpointURL = ""
                }
            }

            if viewModel.endpointName == "Custom" {
                TextField("Endpoint URL", text: $viewModel.endpointURL)
                    .textFieldStyle(.roundedBorder)
            }

            SecureField("API Key", text: $viewModel.apiKey)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(viewModel.language == "zh-Hant" ? "連接" : "Connect") {
                Task { await viewModel.submitAPIKey() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.apiKey.isEmpty)
        }
    }

    // MARK: - Gmail Auth Card
    private var gmailAuthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == "zh-Hant" ? "Gmail 認證" : "Gmail Authentication")
                .font(.headline)

            TextField("Google Client ID", text: $viewModel.googleClientID)
                .textFieldStyle(.roundedBorder)

            SecureField("Client Secret", text: $viewModel.googleClientSecret)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Button(viewModel.language == "zh-Hant" ? "認證" : "Authenticate") {
                Task { await viewModel.submitGmailCredentials() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.googleClientID.isEmpty || viewModel.googleClientSecret.isEmpty)
        }
    }

    // MARK: - Email Review Card
    private var emailReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == "zh-Hant" ? "交易審核" : "Transaction Review")
                .font(.headline)

            Text(viewModel.language == "zh-Hant"
                 ? "已提取 \(viewModel.extractedTransactionCount) 筆交易"
                 : "Extracted \(viewModel.extractedTransactionCount) transactions")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(viewModel.language == "zh-Hant" ? "確認" : "Confirm") {
                Task { await viewModel.confirmEmailReview() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - PDF Password Card
    private var pdfPasswordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.language == "zh-Hant" ? "PDF 密碼" : "PDF Password")
                .font(.headline)

            TextField(viewModel.language == "zh-Hant" ? "銀行名稱" : "Bank Name", text: $viewModel.pdfBankName)
                .textFieldStyle(.roundedBorder)

            TextField(viewModel.language == "zh-Hant" ? "卡片標籤（選填）" : "Card Label (optional)", text: $viewModel.pdfCardLabel)
                .textFieldStyle(.roundedBorder)

            SecureField(viewModel.language == "zh-Hant" ? "PDF 密碼" : "PDF Password", text: $viewModel.pdfPassword)
                .textFieldStyle(.roundedBorder)

            if let error = viewModel.formError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                }

            Button(viewModel.language == "zh-Hant" ? "提交" : "Submit") {
                Task { await viewModel.submitPDFPassword() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.pdfPassword.isEmpty)
        }
    }

    // MARK: - Suggestions Card
    private var suggestionsCard: some View {
        VStack(spacing: 16) {
            Text(viewModel.language == "zh-Hant" ? "財務建議" : "Financial Suggestions")
                .font(.headline)

            Button(viewModel.language == "zh-Hant" ? "是的，請生成建議" : "Yes, generate suggestions") {
                Task { await viewModel.confirmSuggestions() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
```

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/FormCardView.swift
git commit -m "feat(onboarding): add FormCardView with per-step form cards"
```

---

### Task 6: Wire up OnboardingChatView in ContentView

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/ContentView.swift`

**Step 1: Add hasCompletedOnboarding check**

In `ContentView.swift`, replace the existing onboarding gate logic. The key changes:

1. Replace `@State private var hasApiKeys = false` with `@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false`
2. Replace the `if !hasApiKeys && selectedItem != .settings` block with `if !hasCompletedOnboarding`
3. Show `OnboardingChatView` instead of the old `OnboardingView`
4. Remove the `checkApiKeys()` method and its `.onAppear` / `.onChange` calls (no longer needed)
5. Keep the old `OnboardingView` struct and `FeatureRow` deleted (no longer used)

**Specific edits:**

Replace line 40:
```swift
// OLD: @State private var hasApiKeys = false
// NEW:
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
```

Replace the detail view conditional (around lines 96-97):
```swift
// OLD: if !hasApiKeys && selectedItem != .settings {
//          OnboardingView(selectedItem: $selectedItem)
// NEW:
if !hasCompletedOnboarding {
    OnboardingChatView()
```

Remove `checkApiKeys()` method (lines 151-155) and its `.onAppear` / `.onChange` calls.

Delete the `OnboardingView` struct (lines 216-266) and `FeatureRow` struct (lines 268-291).

**Step 2: Verify it compiles**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Run the app and test**

Run: `cd LedgeIt && swift run`
Expected: App launches and shows `OnboardingChatView` with welcome message and language selection card

**Step 4: Commit**

```bash
git add LedgeIt/LedgeIt/Views/ContentView.swift
git commit -m "feat(onboarding): wire OnboardingChatView into ContentView, remove old onboarding"
```

---

### Task 7: "Get Started" button and completion flow

**Files:**
- Modify: `LedgeIt/LedgeIt/Views/Onboarding/OnboardingChatView.swift`

**Step 1: Add Get Started button in complete step**

In `OnboardingChatView`, add a "Get Started" button that appears when the step is `.complete`. Add this after the chat messages in the ScrollView:

```swift
if viewModel.currentStep == .complete {
    Button(action: {
        viewModel.completeOnboarding()
    }) {
        Text(viewModel.language == "zh-Hant" ? "開始使用" : "Get Started")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(12)
    }
    .buttonStyle(.plain)
    .padding(.horizontal)
    .padding(.top, 8)
}
```

**Step 2: Verify it compiles and test**

Run: `cd LedgeIt && swift build 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add LedgeIt/LedgeIt/Views/Onboarding/OnboardingChatView.swift
git commit -m "feat(onboarding): add Get Started button for onboarding completion"
```

---

### Task 8: End-to-end manual test and polish

**Files:**
- Possibly modify: any of the Onboarding files for fixes

**Step 1: Reset onboarding state for testing**

```bash
defaults delete com.ledgeit.app onboardingCurrentStep
defaults delete com.ledgeit.app hasCompletedOnboarding
```

**Step 2: Run the app**

Run: `cd LedgeIt && swift run`

**Step 3: Walk through each step**

1. Language selection → verify card appears, chat messages are in correct language
2. API key → enter endpoint + key, verify card hides during test
3. API key test → verify auto-advance on success, retry on failure
4. Gmail auth → enter credentials, verify OAuth browser opens
5. Email sync → verify progress messages, auto-advance
6. Email review → verify transaction count, confirm button
7. PDF password → verify auto-skip or form card
8. Financial report → verify AI-generated report in chat
9. Suggestions → verify confirmation, AI-generated suggestions
10. Complete → verify feature list, "Get Started" button works

**Step 4: Fix any issues found**

Address compilation errors, layout issues, or flow bugs.

**Step 5: Commit fixes**

```bash
git add -A
git commit -m "fix(onboarding): polish onboarding flow after end-to-end testing"
```

---

### Summary

| Task | Description | New/Modified Files |
|------|-------------|-------------------|
| 1 | OnboardingStep enum + OnboardingMessage model | Create: `OnboardingTypes.swift` |
| 2 | Localized scripted messages | Create: `OnboardingStrings.swift` |
| 3 | OnboardingViewModel state machine | Create: `OnboardingViewModel.swift` |
| 4 | OnboardingChatView chat UI | Create: `OnboardingChatView.swift` |
| 5 | FormCardView floating cards | Create: `FormCardView.swift` |
| 6 | Wire into ContentView | Modify: `ContentView.swift` |
| 7 | Get Started button + completion | Modify: `OnboardingChatView.swift` |
| 8 | End-to-end test and polish | Various fixes |

All new files go in: `LedgeIt/LedgeIt/Views/Onboarding/`
