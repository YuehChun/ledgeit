import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.ledgeit.app", category: "OnboardingViewModel")

@MainActor
final class OnboardingViewModel: ObservableObject {

    // MARK: - Persisted Step

    @Published var currentStep: OnboardingStep {
        didSet {
            UserDefaults.standard.set(currentStep.rawValue, forKey: "onboardingCurrentStep")
        }
    }

    // MARK: - Chat State

    @Published var messages: [OnboardingMessage] = []
    @Published var isTyping = false
    @Published var showFormCard = false
    @Published var formError: String?
    @Published var isProcessing = false

    // MARK: - Form Fields

    // Welcome / Language
    @Published var selectedLanguage: String = "en"

    // API Key
    @Published var apiKeyEndpointName: String = "OpenRouter"
    @Published var apiKeyEndpointURL: String = "https://openrouter.ai/api/v1"
    @Published var apiKeyValue: String = ""
    @Published var apiKeyModel: String = "anthropic/claude-sonnet-4-6"

    // Gmail Auth
    @Published var googleClientID: String = ""
    @Published var googleClientSecret: String = ""

    // PDF Password
    @Published var pdfBankName: String = ""
    @Published var pdfCardLabel: String = ""
    @Published var pdfPassword: String = ""

    // Email Review
    @Published var extractedTransactionCount: Int = 0
    @Published var syncedEmailCount: Int = 0

    // Financial Report
    @Published var financialReportText: String = ""

    // Suggestions
    @Published var suggestionsText: String = ""

    // MARK: - Completion Flag

    private static let completedKey = "hasCompletedOnboarding"

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }

    // MARK: - Services

    private let database: AppDatabase
    private let googleAuthService: GoogleAuthService
    private var strings: OnboardingStrings

    // MARK: - Init

    init(database: AppDatabase = .shared, googleAuthService: GoogleAuthService = GoogleAuthService()) {
        let savedStep = UserDefaults.standard.integer(forKey: "onboardingCurrentStep")
        self.currentStep = OnboardingStep(rawValue: savedStep) ?? .welcome
        self.database = database
        self.googleAuthService = googleAuthService
        // If feature tour already set a language preference, use it
        if UserDefaults.standard.object(forKey: "appLanguage") != nil,
           let tourLanguage = UserDefaults.standard.string(forKey: "appLanguage") {
            self.selectedLanguage = tourLanguage
            self.strings = OnboardingStrings(language: tourLanguage)
            UserDefaults.standard.set(tourLanguage, forKey: "onboardingLanguage")
        } else {
            self.strings = OnboardingStrings(language: "en")
        }
    }

    // MARK: - Lifecycle

    func onAppear() async {
        if messages.isEmpty {
            if currentStep == .welcome {
                await appendAssistantMessage(strings.welcomeGreeting)
            } else {
                // Resuming — reload language preference
                let savedLang = UserDefaults.standard.string(forKey: "onboardingLanguage") ?? "en"
                selectedLanguage = savedLang
                strings = OnboardingStrings(language: savedLang)
                await appendAssistantMessage(strings.welcomeBack)
                await enterStep(currentStep)
            }
            showFormCard = currentStep.needsFormCard
        }
    }

    // MARK: - Step Actions

    func selectLanguage(_ language: String) async {
        selectedLanguage = language
        strings = OnboardingStrings(language: language)
        UserDefaults.standard.set(language, forKey: "onboardingLanguage")

        appendUserMessage(language == "zh-Hant" ? "繁體中文" : "English")
        await appendAssistantMessage(strings.languageSelected)
        await advanceToNext()
    }

    func submitAPIKey() async {
        formError = nil
        guard !apiKeyValue.isEmpty else {
            formError = "API Key is required."
            return
        }

        appendUserMessage("API Key: \u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
        showFormCard = false

        // Build config from form fields
        var config = AIProviderConfigStore.load()

        // Find or create the endpoint
        let endpointId: UUID
        if let existing = config.endpoints.first(where: { $0.baseURL == apiKeyEndpointURL }) {
            endpointId = existing.id
        } else {
            let newEndpoint = OpenAICompatibleEndpoint(
                id: UUID(),
                name: apiKeyEndpointName,
                baseURL: apiKeyEndpointURL,
                requiresAPIKey: true,
                defaultModel: apiKeyModel
            )
            config.endpoints.append(newEndpoint)
            endpointId = newEndpoint.id
        }

        // Save API key
        do {
            try KeychainService.saveEndpointAPIKey(endpointId: endpointId, value: apiKeyValue)
        } catch {
            formError = "Failed to save API key: \(error.localizedDescription)"
            showFormCard = true
            return
        }

        // Set all model assignments to use this endpoint
        let assignment = ModelAssignment(
            provider: .openAICompatible,
            endpointId: endpointId,
            model: apiKeyModel
        )
        config.classification = assignment
        config.extraction = assignment
        config.statement = assignment
        config.chat = assignment
        AIProviderConfigStore.save(config)

        await advanceToNext()
    }

    func submitGmailCredentials() async {
        formError = nil
        guard !googleClientID.isEmpty, !googleClientSecret.isEmpty else {
            formError = "Both Client ID and Client Secret are required."
            return
        }

        appendUserMessage("Google OAuth credentials submitted")
        showFormCard = false

        // Save credentials to Keychain
        do {
            try KeychainService.save(key: .googleClientID, value: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines))
            try KeychainService.save(key: .googleClientSecret, value: googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            formError = "Failed to save credentials: \(error.localizedDescription)"
            showFormCard = true
            return
        }

        await appendAssistantMessage(strings.gmailAuthenticating)

        // Attempt Google sign-in
        do {
            try await googleAuthService.signIn()
            await appendAssistantMessage(strings.gmailAuthSuccess)
            await advanceToNext()
        } catch {
            let errorMsg = error.localizedDescription
            logger.error("Gmail auth failed: \(errorMsg)")
            await appendAssistantMessage(strings.gmailAuthError(errorMsg))
            formError = errorMsg
            showFormCard = true
        }
    }

    func confirmEmailReview() async {
        appendUserMessage(selectedLanguage == "zh-Hant" ? "確認" : "Confirmed")
        await appendAssistantMessage(strings.emailReviewConfirmed)
        await advanceToNext()
    }

    func submitPDFPassword() async {
        formError = nil
        guard !pdfBankName.isEmpty, !pdfPassword.isEmpty else {
            formError = "Bank name and password are required."
            return
        }

        appendUserMessage("\(pdfBankName): ****")
        showFormCard = false

        let newPassword = StatementPassword(
            bankName: pdfBankName,
            cardLabel: pdfCardLabel,
            password: pdfPassword
        )

        do {
            var existing = StatementPassword.loadAll()
            existing.append(newPassword)
            try StatementPassword.saveAll(existing)
            await appendAssistantMessage(strings.pdfPasswordSuccess)
            // Clear fields for potential additional passwords
            pdfBankName = ""
            pdfCardLabel = ""
            pdfPassword = ""
            await advanceToNext()
        } catch {
            formError = error.localizedDescription
            showFormCard = true
        }
    }

    func skipPDFPassword() async {
        appendUserMessage(selectedLanguage == "zh-Hant" ? "跳過" : "Skip")
        await advanceToNext()
    }

    func confirmSuggestions() async {
        appendUserMessage(selectedLanguage == "zh-Hant" ? "\u{662F}\u{7684}\u{FF0C}\u{751F}\u{6210}\u{5EFA}\u{8B70}" : "Yes, generate suggestions")
        showFormCard = false
        isProcessing = true
        await appendAssistantMessage(strings.suggestionsGenerating)

        do {
            let config = AIProviderConfigStore.load()
            let session = try SessionFactory.makeSession(
                assignment: config.chat,
                config: config,
                instructions: selectedLanguage == "zh-Hant"
                    ? "You are a helpful financial advisor. Reply in Traditional Chinese."
                    : "You are a helpful financial advisor."
            )

            // Build context from SpendingAnalyzer
            let analyzer = SpendingAnalyzer(database: database)
            let calendar = Calendar.current
            let now = Date()
            let year = calendar.component(.year, from: now)
            let month = calendar.component(.month, from: now)
            let report = try analyzer.monthlyBreakdown(year: year, month: month)

            // Format report as text context
            var context = "Total spending: \(String(format: "%.2f", report.totalSpending)), "
            context += "Total income: \(String(format: "%.2f", report.totalIncome)), "
            context += "Savings rate: \(String(format: "%.1f", report.savingsRate * 100))%\n"
            context += "Categories:\n"
            for cat in report.categoryBreakdown {
                context += "- \(cat.category): \(String(format: "%.2f", cat.amount)) (\(String(format: "%.1f", cat.percentage))%)\n"
            }
            context += "Top merchants:\n"
            for m in report.topMerchants {
                context += "- \(m.merchant): \(String(format: "%.2f", m.amount)) (\(m.count) txns)\n"
            }

            let prompt = selectedLanguage == "zh-Hant"
                ? "Based on the following monthly spending data, provide 3-5 specific and actionable financial suggestions in Traditional Chinese. Explain the benefit and expected impact of each.\n\nSpending data: \(context)"
                : "Based on the following monthly spending data, provide 3-5 specific and actionable financial suggestions. Explain the benefit and expected impact of each.\n\nSpending data: \(context)"

            let response = try await session.complete(
                messages: [.user(prompt)],
                temperature: 0.5,
                maxTokens: 800
            )
            isProcessing = false
            await appendAssistantMessage(response)
        } catch {
            isProcessing = false
            let fallback = selectedLanguage == "zh-Hant"
                ? "\u{66AB}\u{6642}\u{7121}\u{6CD5}\u{751F}\u{6210}\u{5EFA}\u{8B70}\u{FF0C}\u{4F60}\u{53EF}\u{4EE5}\u{4E4B}\u{5F8C}\u{5728}\u{300C}\u{9867}\u{554F}\u{300D}\u{529F}\u{80FD}\u{4E2D}\u{7372}\u{53D6}\u{500B}\u{4EBA}\u{5316}\u{7684}\u{8CA1}\u{52D9}\u{5EFA}\u{8B70}\u{3002}"
                : "Unable to generate suggestions right now. You can get personalized financial advice from the Advisor feature later."
            await appendAssistantMessage(fallback)
        }

        await advanceToNext()
    }

    func skipSuggestions() async {
        appendUserMessage(selectedLanguage == "zh-Hant" ? "\u{4E0D}\u{7528}\u{4E86}" : "No thanks")
        showFormCard = false
        await advanceToNext()
    }

    func completeOnboarding() {
        Self.hasCompletedOnboarding = true
    }

    // MARK: - Chat Input

    func sendChatMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        appendUserMessage(trimmed)

        // Before API key is set up, use scripted responses
        if currentStep.rawValue <= OnboardingStep.apiKey.rawValue {
            await appendAssistantMessage(strings.helpResponse)
            return
        }

        // After API key, try real LLM
        await sendToLLM(trimmed)
    }

    // MARK: - Private: Step Entry & Advancement

    private func enterStep(_ step: OnboardingStep) async {
        showFormCard = step.needsFormCard
        formError = nil

        switch step {
        case .welcome:
            // Already handled in onAppear
            break

        case .apiKey:
            await appendAssistantMessage(strings.apiKeyIntro)

        case .apiKeyTest:
            await runAPIKeyTest()

        case .gmailAuth:
            await appendAssistantMessage(strings.gmailAuthIntro)

        case .emailSync:
            await runEmailSync()

        case .emailReview:
            await showEmailReview()

        case .pdfPassword:
            await checkPDFPasswords()

        case .financialReport:
            await generateFinancialReport()

        case .suggestions:
            await appendAssistantMessage(strings.suggestionsAsk)

        case .complete:
            await appendAssistantMessage(strings.completeIntro)
        }
    }

    private func advanceToNext() async {
        let allSteps = OnboardingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex + 1 < allSteps.count else {
            return
        }

        let nextStep = allSteps[currentIndex + 1]
        currentStep = nextStep
        await enterStep(nextStep)
    }

    // MARK: - Private: Auto-Advancing Steps

    private func runAPIKeyTest() async {
        isProcessing = true
        await appendAssistantMessage(strings.apiKeyTesting)

        let config = AIProviderConfigStore.load()
        let assignment = config.chat

        do {
            let session = try SessionFactory.makeSession(
                assignment: assignment,
                config: config,
                instructions: "You are a helpful assistant."
            )
            let _ = try await session.complete(
                messages: [.user("Say hello in one sentence.")],
                temperature: 0.1,
                maxTokens: 50
            )
            isProcessing = false
            await appendAssistantMessage(strings.apiKeySuccess)
            await advanceToNext()
        } catch {
            isProcessing = false
            let errorMsg = error.localizedDescription
            logger.error("API key test failed: \(errorMsg)")
            await appendAssistantMessage(strings.apiKeyError(errorMsg))
            // Go back to apiKey step for retry
            currentStep = .apiKey
            showFormCard = true
        }
    }

    private func runEmailSync() async {
        isProcessing = true
        await appendAssistantMessage(strings.emailSyncIntro)

        let syncService = SyncService(database: database)
        syncService.configure(accessTokenProvider: { [googleAuthService] in
            try await googleAuthService.getValidAccessToken()
        })

        do {
            try await syncService.performInitialSync(lookbackDays: 30)

            let emailCount = try await database.db.read { db in
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
            let providerConfig = AIProviderConfigStore.load()
            let llmProcessor = LLMProcessor(providerConfig: providerConfig)
            let pipeline = ExtractionPipeline(database: database, llmProcessor: llmProcessor)
            try await pipeline.processUnprocessedEmails()

            let txnCount = try await database.db.read { db in
                try Transaction.filter(Transaction.Columns.deletedAt == nil).fetchCount(db)
            }
            extractedTransactionCount = txnCount

            isProcessing = false
            await advanceToNext()
        } catch {
            isProcessing = false
            let errorMsg = error.localizedDescription
            logger.error("Email sync failed: \(errorMsg)")
            await appendAssistantMessage(
                selectedLanguage == "zh-Hant"
                    ? "同步失敗：\(errorMsg)\n\n請檢查你的網路連線和 Gmail 認證狀態。"
                    : "Sync failed: \(errorMsg)\n\nPlease check your network connection and Gmail authentication."
            )
            // Go back to gmailAuth step for retry
            currentStep = .gmailAuth
            showFormCard = true
        }
    }

    // MARK: - Private: Email Review

    private func showEmailReview() async {
        let count = extractedTransactionCount
        if count == 0 {
            await appendAssistantMessage(
                selectedLanguage == "zh-Hant"
                    ? "未提取到任何交易記錄，跳過此步驟。"
                    : "No transactions were extracted, skipping this step."
            )
            await advanceToNext()
            return
        }

        // Fetch a summary of recent transactions
        do {
            let transactions = try await database.db.read { db in
                try Transaction
                    .filter(Transaction.Columns.deletedAt == nil)
                    .order(Transaction.Columns.transactionDate.desc)
                    .limit(10)
                    .fetchAll(db)
            }

            var summary = strings.emailReviewIntro + "\n\n"
            for txn in transactions {
                let merchant = txn.merchant ?? "Unknown"
                let amount = String(format: "%.2f", abs(txn.amount))
                let date = txn.transactionDate ?? "N/A"
                let type = txn.type ?? "debit"
                summary += "- \(date) | \(merchant) | \(amount) \(txn.currency) (\(type))\n"
            }
            if count > 10 {
                summary += "\n"
                summary += selectedLanguage == "zh-Hant"
                    ? "... 還有 \(count - 10) 筆交易"
                    : "... and \(count - 10) more transactions"
            }

            await appendAssistantMessage(summary)
        } catch {
            await appendAssistantMessage(strings.emailReviewIntro)
        }
    }

    // MARK: - Private: PDF Password Check

    private func checkPDFPasswords() async {
        // Check if there are password-protected PDFs
        do {
            let hasPasswordPDFs = try await database.db.read { db -> Bool in
                // Check for attachments that are PDFs but have no extracted text
                let count = try Attachment
                    .filter(Attachment.Columns.mimeType == "application/pdf")
                    .filter(Attachment.Columns.extractedText == nil)
                    .fetchCount(db)
                return count > 0
            }

            if hasPasswordPDFs {
                await appendAssistantMessage(strings.pdfPasswordIntro)
            } else {
                await appendAssistantMessage(strings.pdfPasswordSkipped)
                showFormCard = false
                await advanceToNext()
            }
        } catch {
            // If we can't check, skip
            await appendAssistantMessage(strings.pdfPasswordSkipped)
            showFormCard = false
            await advanceToNext()
        }
    }

    // MARK: - Private: Financial Report

    private func generateFinancialReport() async {
        isProcessing = true
        await appendAssistantMessage(strings.financialReportGenerating)

        let analyzer = SpendingAnalyzer(database: database)
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        do {
            let report = try analyzer.monthlyBreakdown(year: year, month: month)
            let trends = try analyzer.spendingTrend(months: 6)

            let providerConfig = AIProviderConfigStore.load()
            let advisor = FinancialAdvisor(providerConfig: providerConfig)
            let advice = try await advisor.analyzeSpendingHabits(
                report: report,
                trends: trends,
                language: selectedLanguage
            )

            // Format the advice as chat text
            var reportText = advice.overallAssessment + "\n\n"
            reportText += selectedLanguage == "zh-Hant" ? "**健康分數：**\(advice.healthScore)/100\n\n" : "**Health Score:** \(advice.healthScore)/100\n\n"

            if !advice.positiveHabits.isEmpty {
                reportText += selectedLanguage == "zh-Hant" ? "**正面習慣：**\n" : "**Positive Habits:**\n"
                for habit in advice.positiveHabits {
                    reportText += "- \(habit)\n"
                }
                reportText += "\n"
            }

            if !advice.concerns.isEmpty {
                reportText += selectedLanguage == "zh-Hant" ? "**注意事項：**\n" : "**Concerns:**\n"
                for concern in advice.concerns {
                    reportText += "- \(concern)\n"
                }
                reportText += "\n"
            }

            if !advice.actionItems.isEmpty {
                reportText += selectedLanguage == "zh-Hant" ? "**建議行動：**\n" : "**Action Items:**\n"
                for item in advice.actionItems {
                    reportText += "- \(item)\n"
                }
            }

            financialReportText = reportText
            isProcessing = false
            await appendAssistantMessage(reportText)
            await advanceToNext()
        } catch {
            isProcessing = false
            let errorMsg = error.localizedDescription
            logger.error("Financial report generation failed: \(errorMsg)")
            let fallback = selectedLanguage == "zh-Hant"
                ? "無法生成財務報告：\(errorMsg)\n\n不用擔心，你之後可以在分析頁面查看報告。"
                : "Could not generate financial report: \(errorMsg)\n\nDon't worry, you can view reports later in the Analysis tab."
            await appendAssistantMessage(fallback)
            await advanceToNext()
        }
    }

    // MARK: - Private: LLM Chat

    private func sendToLLM(_ text: String) async {
        isTyping = true

        let config = AIProviderConfigStore.load()
        let assignment = config.chat

        do {
            let session = try SessionFactory.makeSession(
                assignment: assignment,
                config: config,
                instructions: selectedLanguage == "zh-Hant"
                    ? "You are a friendly financial setup assistant for LedgeIt. Reply in Traditional Chinese (繁體中文). Keep responses concise."
                    : "You are a friendly financial setup assistant for LedgeIt. Keep responses concise."
            )

            // Build LLM message history from recent chat messages (last 10)
            let recentMessages = messages.suffix(10)
            var llmMessages: [LLMMessage] = recentMessages.compactMap { msg in
                switch msg.role {
                case .user:
                    return .user(msg.content)
                case .assistant:
                    return .assistant(msg.content)
                }
            }

            // Ensure the last message is the user's
            if llmMessages.last?.role != .user {
                llmMessages.append(.user(text))
            }

            let response = try await session.complete(
                messages: llmMessages,
                temperature: 0.5,
                maxTokens: 500
            )

            isTyping = false
            await appendAssistantMessage(response)
        } catch {
            isTyping = false
            logger.error("LLM chat failed: \(error.localizedDescription)")
            await appendAssistantMessage(strings.helpResponse)
        }
    }

    // MARK: - Private: Message Helpers

    private func appendAssistantMessage(_ content: String) async {
        isTyping = true
        // Small delay for typing feel
        try? await Task.sleep(for: .milliseconds(300))
        let message = OnboardingMessage(role: .assistant, content: content)
        messages.append(message)
        isTyping = false
    }

    private func appendUserMessage(_ content: String) {
        let message = OnboardingMessage(role: .user, content: content)
        messages.append(message)
    }
}
