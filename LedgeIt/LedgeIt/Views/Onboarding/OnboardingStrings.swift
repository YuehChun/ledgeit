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
