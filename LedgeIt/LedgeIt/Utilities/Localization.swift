import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHant: return "繁體中文"
        }
    }
}

struct L10n: Sendable {
    let lang: AppLanguage

    init(_ rawValue: String) {
        self.lang = AppLanguage(rawValue: rawValue) ?? .en
    }

    private func s(_ en: String, _ zh: String) -> String {
        lang == .zhHant ? zh : en
    }

    // MARK: - Sidebar

    var overview: String { s("Overview", "總覽") }
    var data: String { s("Data", "資料") }
    var analysisSection: String { s("Analysis", "分析") }
    var dashboard: String { s("Dashboard", "儀表板") }
    var transactions: String { s("Transactions", "交易記錄") }
    var emails: String { s("Emails", "電子郵件") }
    var calendar: String { s("Calendar", "日曆") }
    var analysis: String { s("Financial Analysis", "財務分析") }
    var goals: String { s("Goals", "財務目標") }
    var settings: String { s("Settings", "設定") }

    // MARK: - Settings

    var settingsSubtitle: String { s("Configure credentials, connect your Google account, and sync emails.", "設定憑證、連接 Google 帳號並同步郵件。") }
    var language: String { s("Language", "語系") }
    var languageDescription: String { s("Choose your preferred display language.", "選擇偏好的顯示語言。") }
    var googleCloudPlatform: String { s("Google Cloud Platform", "Google 雲端平台") }
    var clientID: String { s("Client ID", "用戶端 ID") }
    var clientSecret: String { s("Client Secret", "用戶端密鑰") }
    var googleCloudHint: String { s("Create a Desktop OAuth 2.0 client. Enable Gmail + Calendar APIs.", "建立 Desktop OAuth 2.0 用戶端，啟用 Gmail 及 Calendar API。") }
    var openRouterAI: String { s("OpenRouter (AI)", "OpenRouter (AI)") }
    var apiKey: String { s("API Key", "API 金鑰") }
    var openRouterHint: String { s("Get your API key from openrouter.ai", "從 openrouter.ai 取得 API 金鑰") }
    var openRouterBudget: String { s("Budget", "預算") }
    var openRouterUsed: String { s("Used", "已使用") }
    var openRouterRemaining: String { s("Remaining", "剩餘") }
    var openRouterFreeTier: String { s("Free Tier", "免費方案") }
    var openRouterNoLimit: String { s("No limit set", "未設定上限") }
    var openRouterFetchingCredits: String { s("Fetching credits...", "正在取得額度...") }
    var openRouterCreditsError: String { s("Could not fetch credits", "無法取得額度資訊") }
    var openRouterRefresh: String { s("Refresh", "重新整理") }
    var openRouterCreditUsage: String { s("Credit Usage", "額度使用") }
    func openRouterUsedPercent(_ pct: String) -> String { s("\(pct) used", "已使用 \(pct)") }
    var openRouterTotalCredits: String { s("Total Credits", "總額度") }
    var openRouterLastUpdated: String { s("Last updated", "最後更新") }
    var connectionStatus: String { s("Connection Status", "連線狀態") }
    var googleConnected: String { s("Google Connected", "Google 已連線") }
    var notConnected: String { s("Not Connected", "未連線") }
    var accountLinked: String { s("Account linked and ready.", "帳號已連結，準備就緒。") }
    var saveAndConnect: String { s("Save credentials and connect below.", "儲存憑證並在下方連接。") }
    var lastSync: String { s("Last Sync", "上次同步") }
    var emailsSynced: String { s("Emails Synced", "已同步郵件") }
    var emailsProcessed: String { s("Emails Processed", "已處理郵件") }
    var never: String { s("Never", "從未") }
    var syncAndProcess: String { s("Sync & Process", "同步並處理") }
    var processOnly: String { s("Process Only", "僅處理") }
    var calendarSync: String { s("Calendar Sync", "日曆同步") }
    var disconnect: String { s("Disconnect", "中斷連線") }
    var saveAndConnectGoogle: String { s("Save & Connect Google", "儲存並連接 Google") }
    var permissionsRequested: String { s("Permissions Requested", "請求的權限") }
    var gmailPermission: String { s("Gmail — read-only access to your emails", "Gmail — 唯讀存取您的郵件") }
    var calendarPermission: String { s("Google Calendar — create payment events", "Google 日曆 — 建立付款事件") }

    // MARK: - Analysis Dashboard

    var financialAnalysis: String { s("Financial Analysis", "財務分析") }
    var analysisSubtitle: String { s("AI-powered spending analysis and advice", "AI 驅動的消費分析與建議") }
    var generateReport: String { s("Generate Report", "產生報告") }
    var refreshReport: String { s("Refresh Report", "更新報告") }
    var financialHealthScore: String { s("Financial Health Score", "財務健康分數") }
    var positiveHabits: String { s("Positive Habits", "良好習慣") }
    var actionItems: String { s("Action Items", "行動建議") }
    var unusualSpending: String { s("Unusual Spending", "異常消費") }
    var categoryInsights: String { s("Category Insights", "類別分析") }
    var savingsRateTrend: String { s("Savings Rate Trend", "儲蓄率趨勢") }
    var savingsTarget: String { s("Dashed line = 20% savings target", "虛線 = 20% 儲蓄目標") }
    var noAnalysisYet: String { s("No Analysis Yet", "尚無分析") }
    var noAnalysisDescription: String { s("Click \"Generate Report\" to create an AI-powered financial analysis.", "點擊「產生報告」以建立 AI 財務分析。") }
    var analysisFailed: String { s("Analysis Failed", "分析失敗") }
    var tryAgain: String { s("Try Again", "重試") }
    var avgSuffix: String { s("x avg", "x 平均") }

    // MARK: - Goals

    var financialGoals: String { s("Financial Goals", "財務目標") }
    var active: String { s("Active", "進行中") }
    var suggested: String { s("Suggested", "建議") }
    var completed: String { s("Completed", "已完成") }
    var all: String { s("All", "全部") }
    var noGoalsYet: String { s("No Goals Yet", "尚無目標") }
    var noGoalsDescription: String { s("Goals are generated from the AI Advisor page. Go there to configure your advisor and generate goals.", "目標由 AI 顧問頁面產生。請前往該頁面設定顧問並產生目標。") }
    var noFilteredGoals: String { s("Try switching to a different filter to see your goals.", "請嘗試切換不同的篩選條件以查看目標。") }
    var goToAdvisor: String { s("Go to AI Advisor", "前往 AI 顧問") }
    var goalsFromAdvisor: String { s("Goals are generated from the AI Advisor page.", "目標由 AI 顧問頁面產生。") }
    var shortTermGoals: String { s("Short-Term Goals (1-3 months)", "短期目標（1-3 個月）") }
    var longTermGoals: String { s("Long-Term Goals (1-3 years)", "長期目標（1-3 年）") }
    var accept: String { s("Accept", "接受") }
    var dismiss: String { s("Dismiss", "忽略") }
    var complete: String { s("Complete", "完成") }
    var progress: String { s("Progress", "進度") }
    var markComplete: String { s("Mark Complete", "標記完成") }
    var regeneratingGoals: String { s("Regenerating goals for new advisor...", "正在為新顧問重新產生目標...") }
    func noGoalsForFilter(_ filterName: String) -> String {
        s("No \(filterName) Goals", "沒有\(filterName)的目標")
    }

    // MARK: - AI Advisor

    var aiAdvisor: String { s("AI Advisor", "AI 理財顧問") }
    var aiAdvisorSidebar: String { s("AI Advisor", "AI 顧問") }
    var aiAdvisorSubtitle: String { s("Choose your financial planning style", "選擇您的理財風格") }
    var conservative: String { s("Conservative", "保守型") }
    var moderate: String { s("Moderate", "穩健型") }
    var aggressive: String { s("Aggressive", "積極型") }
    var custom: String { s("Custom", "自訂") }
    var conservativeDesc: String { s("Maximize savings, minimize risk", "最大化儲蓄，最小化風險") }
    var moderateDesc: String { s("Balanced lifestyle and savings", "平衡生活與儲蓄") }
    var aggressiveDesc: String { s("Growth-focused, higher risk tolerance", "成長導向，較高風險承受度") }
    var customDesc: String { s("Set your own targets", "設定您自己的目標") }
    var savingsTargetLabel: String { s("Savings Target", "儲蓄目標") }
    var riskLevel: String { s("Risk Level", "風險等級") }
    var riskLow: String { s("Low", "低") }
    var riskMedium: String { s("Medium", "中") }
    var riskHigh: String { s("High", "高") }
    var applyAndRegenerate: String { s("Apply & Regenerate Report", "套用並重新產生報告") }
    var currentAdvisor: String { s("Current Advisor", "目前顧問") }
    var categoryBudgets: String { s("Category Budget Limits", "類別預算上限") }
    var ofIncome: String { s("of income", "收入占比") }
    var resetToDefault: String { s("Reset to Default", "重設為預設值") }

    // MARK: - Prompt Versioning

    var feedbackSection: String { s("Optimize Advisor", "優化顧問") }
    var feedbackPlaceholder: String { s("How should the advisor adjust? (e.g., 'dining suggestions are too strict')", "顧問應如何調整？（例如：「餐飲建議太嚴格」）") }
    var optimizeButton: String { s("Optimize", "優化") }
    var optimizing: String { s("Optimizing prompt...", "正在優化提示詞...") }
    var optimizePreview: String { s("Proposed Changes", "建議的變更") }
    var applyButton: String { s("Apply", "套用") }
    var generateGoals: String { s("Generate Goals", "產生目標") }
    var generatingGoals: String { s("Generating goals...", "正在產生目標...") }
    var generateGoalsDesc: String { s("Generate AI-suggested financial goals based on your current advisor persona and latest analysis.", "根據目前的顧問角色和最新分析產生 AI 建議的財務目標。") }
    var applying: String { s("Applying changes...", "正在套用變更...") }
    var versionHistory: String { s("Version History", "版本歷史") }
    var initialPreset: String { s("Initial preset", "初始預設") }
    var revert: String { s("Revert", "還原") }
    var activeVersion: String { s("Active", "使用中") }

    // MARK: - Prompt Diff & Review

    var promptVersions: String { s("Prompt Versions", "提示詞版本") }
    var promptVersionsSubtitle: String { s("Review and manage AI advisor prompt changes", "審核與管理 AI 顧問提示詞變更") }
    var pendingReview: String { s("Pending Review", "待審核") }
    var changesSummary: String { s("Changes Summary", "變更摘要") }
    var parameters: String { s("Parameters", "參數") }
    var currentLabel: String { s("Current", "目前") }
    var proposedLabel: String { s("Proposed", "建議") }
    var promptDiff: String { s("Prompt Diff", "提示詞差異") }
    var approvePrompt: String { s("Approve", "核准") }
    var rejectPrompt: String { s("Reject", "拒絕") }
    var noVersionsYet: String { s("No Versions Yet", "尚無版本") }
    var noVersionsDescription: String { s("Optimize your advisor to create prompt versions.", "優化您的顧問以建立提示詞版本。") }
    var noPendingChanges: String { s("No Pending Changes", "沒有待審核的變更") }
    var noPendingDescription: String { s("Enter feedback and click Optimize to generate prompt improvements.", "輸入回饋並點擊優化以產生提示詞改進。") }
    var versionLabel: String { s("Version", "版本") }

    // MARK: - Category Names

    func categoryName(_ raw: String) -> String {
        switch raw {
        case "FOOD_AND_DRINK": return s("Food & Drink", "餐飲")
        case "GROCERIES": return s("Groceries", "生鮮雜貨")
        case "ENTERTAINMENT": return s("Entertainment", "娛樂")
        case "TRAVEL": return s("Travel", "旅遊")
        case "HEALTHCARE": return s("Healthcare", "醫療")
        case "PERSONAL_CARE": return s("Personal Care", "個人護理")
        case "EDUCATION": return s("Education", "教育")
        case "CHARITY": return s("Charity", "慈善")
        case "BANK_FEES_AND_CHARGES": return s("Bank Fees", "銀行手續費")
        case "UTILITIES": return s("Utilities", "水電瓦斯")
        case "INSURANCE": return s("Insurance", "保險")
        case "INVESTMENTS": return s("Investments", "投資")
        case "SHOPPING": return s("Shopping", "購物")
        case "TRANSPORT": return s("Transport", "交通")
        case "GENERAL": return s("General", "一般")
        default: return raw
        }
    }

    // MARK: - Transaction Verification

    var editTransaction: String { s("Edit Transaction", "編輯交易") }
    var amount: String { s("Amount", "金額") }
    var merchant: String { s("Merchant", "商家") }
    var category: String { s("Category", "類別") }
    var date: String { s("Date", "日期") }
    var type: String { s("Type", "類型") }
    var flagIncorrect: String { s("Flag as Incorrect", "標記為不正確") }
    var save: String { s("Save", "儲存") }
    var cancel: String { s("Cancel", "取消") }
    var highConfidence: String { s("High confidence", "高信心度") }
    var mediumConfidence: String { s("Medium confidence", "中信心度") }
    var lowConfidence: String { s("Low confidence", "低信心度") }

    // MARK: - Transaction Review

    var review: String { s("Review", "審核") }
    var transactionReview: String { s("Transaction Review", "交易審核") }
    func unreviewedCount(_ count: Int) -> String {
        s("\(count) unreviewed transactions", "\(count) 筆未審核交易")
    }
    var markAllReviewed: String { s("Mark All Reviewed", "全部標為已審核") }
    var markReviewed: String { s("Mark Reviewed", "標為已審核") }
    var viewOriginalEmail: String { s("View original email", "查看原始郵件") }
    var hideOriginalEmail: String { s("Hide original email", "隱藏原始郵件") }
    var deleteTransaction: String { s("Delete", "刪除") }
    var deleteConfirmTitle: String { s("Delete Transaction?", "刪除交易？") }
    var deleteConfirmMessage: String { s("This transaction will be permanently removed from your records.", "此交易將從您的記錄中永久刪除。") }
    var filterUnreviewed: String { s("Unreviewed", "未審核") }
    var filterReviewed: String { s("Reviewed", "已審核") }
    var filterDeleted: String { s("Deleted", "已刪除") }
    var noUnreviewedTransactions: String { s("All Caught Up", "全部完成") }
    var noUnreviewedDescription: String { s("No transactions need review right now.", "目前沒有需要審核的交易。") }
    var noDeletedTransactions: String { s("No Deleted Transactions", "沒有已刪除的交易") }
    var noDeletedDescription: String { s("Deleted transactions will appear here for 7 days before permanent removal.", "已刪除的交易會在此保留 7 天後永久移除。") }
    var restore: String { s("Restore", "復原") }
    func daysUntilPurge(_ days: Int) -> String {
        s("\(days)d left", "剩餘 \(days) 天")
    }
    var unknownSender: String { s("Unknown sender", "未知寄件者") }
    var noSubject: String { s("No subject", "無主旨") }
    func transactionsFromEmail(_ count: Int) -> String {
        s("\(count) transaction\(count == 1 ? "" : "s")", "\(count) 筆交易")
    }

    // MARK: - Chat

    var chat: String { s("Advisory", "諮詢助手") }
    var chatTitle: String { s("Financial Advisory", "諮詢助手") }
    var chatPlaceholder: String { s("Ask about your finances...", "詢問您的財務狀況...") }
    var chatEmptyTitle: String { s("Ask Me Anything", "隨時提問") }
    var chatEmptyDescription: String { s("Ask about your spending, transactions, goals, or upcoming payments.", "詢問您的消費、交易、目標或即將到期的付款。") }
    var clearChat: String { s("Clear conversation", "清除對話") }
    var newSession: String { s("New Session", "新對話") }
    var newSessionHelp: String { s("Start a new conversation", "開始新的對話") }

    // MARK: - Dashboard

    var spendingOverview: String { s("Spending Overview", "消費概覽") }
    var thisMonth: String { s("This Month", "本月") }
    var income: String { s("Income", "收入") }
    var spending: String { s("Spending", "支出") }
    var savingsRate: String { s("Savings Rate", "儲蓄率") }
    var spendingBudget: String { s("Spending Budget", "消費預算") }
    var disposableBalance: String { s("Disposable Balance", "可動用餘額") }
    var dailyAllowance: String { s("Daily Allowance", "每日可消費") }
    var ofBudget: String { s("of budget this month", "本月預算") }
    func perDayForDays(_ days: Int) -> String {
        s("per day for \(days) remaining days", "剩餘 \(days) 天，每日額度")
    }
    var overBudget: String { s("Over Budget", "超出預算") }
    func overBudgetBy(_ amount: String) -> String {
        s("Over budget by \(amount)", "超出預算 \(amount)")
    }
    var waitingForIncome: String { s("Waiting for income data", "等待收入資料") }
    var waitingForIncomeDesc: String { s("Income transactions will appear after email sync.", "收入交易紀錄將在郵件同步後出現。") }
    var budgetUsed: String { s("Budget Used", "已使用預算") }
    var monthProgress: String { s("Month Progress", "月份進度") }

    // MARK: - Onboarding

    var welcomeTitle: String { s("Welcome to LedgeIt", "歡迎使用 LedgeIt") }
    var welcomeSubtitle: String { s("Personal finance tracking powered by AI", "AI 驅動的個人財務追蹤") }
    var gmailIntegration: String { s("Gmail Integration", "Gmail 整合") }
    var gmailIntegrationDesc: String { s("Automatically scan financial emails", "自動掃描財務郵件") }
    var aiExtraction: String { s("AI-Powered Extraction", "AI 智慧擷取") }
    var aiExtractionDesc: String { s("Extract transactions with Claude AI", "透過 Claude AI 擷取交易資料") }
    var financialDashboard: String { s("Financial Dashboard", "財務儀表板") }
    var financialDashboardDesc: String { s("Visualize spending patterns and trends", "視覺化消費模式與趨勢") }
    var paymentCalendar: String { s("Payment Calendar", "付款日曆") }
    var paymentCalendarDesc: String { s("Track upcoming bills and payments", "追蹤即將到來的帳單與付款") }
    var getStarted: String { s("Get Started", "開始使用") }

    // MARK: - Statements
    var statements: String { s("Statements", "帳單") }
    var statementsSubtitle: String { s("Import credit card statements", "匯入信用卡帳單") }
    var passwordVault: String { s("Password Vault", "密碼保管庫") }
    var addPassword: String { s("Add Password", "新增密碼") }
    var editPassword: String { s("Edit Password", "編輯密碼") }
    var bankName: String { s("Bank Name", "銀行名稱") }
    var cardLabel: String { s("Card Label", "卡片名稱") }
    var pdfPassword: String { s("PDF Password", "PDF 密碼") }
    var deletePassword: String { s("Delete", "刪除") }
    var savePassword: String { s("Save", "儲存") }
    var cancelAction: String { s("Cancel", "取消") }
    var uploadStatement: String { s("Upload Statement", "上傳帳單") }
    var dropPDFHere: String { s("Drop PDF here or click to browse", "拖放 PDF 檔案或點擊瀏覽") }
    var processing: String { s("Processing...", "處理中...") }
    var decrypting: String { s("Decrypting PDF...", "解密 PDF 中...") }
    var extractingText: String { s("Extracting text...", "擷取文字中...") }
    var analyzingTransactions: String { s("Analyzing transactions...", "分析交易中...") }
    var extractedTransactions: String { s("Extracted Transactions", "擷取的交易") }
    var importAll: String { s("Import All", "全部匯入") }
    var noTransactionsFound: String { s("No transactions found", "未找到交易") }
    var noTransactionsDesc: String { s("Could not extract transactions from this statement", "無法從此帳單中擷取交易") }
    var importHistory: String { s("Import History", "匯入記錄") }
    var noImportHistory: String { s("No imports yet", "尚無匯入記錄") }
    var noImportHistoryDesc: String { s("Upload a credit card statement to get started", "上傳信用卡帳單以開始") }
    var transactionCount: String { s("transactions", "筆交易") }
    var importSuccess: String { s("Successfully imported", "匯入成功") }
    var noPasswordsYet: String { s("No passwords saved", "尚無儲存的密碼") }
    var noPasswordsDesc: String { s("Add your credit card statement passwords to enable auto-decrypt", "新增信用卡帳單密碼以啟用自動解密") }
    var statementsSidebar: String { s("Statements", "帳單") }
    var gmailPDFs: String { s("Gmail PDF Attachments", "Gmail PDF 附件") }
    var noGmailPDFs: String { s("No PDF attachments found", "未找到 PDF 附件") }
    var noGmailPDFsDesc: String { s("Sync your Gmail first to load email attachments", "請先同步 Gmail 以載入郵件附件") }
    var parse: String { s("Parse", "解析") }
    var imported: String { s("Imported", "已匯入") }
    var paymentSummaryTitle: String { s("Payment Summary", "繳款資訊") }
    var totalDue: String { s("Total Due", "應繳總額") }
    var minimumDue: String { s("Minimum Due", "最低應繳") }
    var paymentDueDate: String { s("Due Date", "繳款期限") }
    var statementPeriod: String { s("Period", "帳單期間") }
    var createCalendarReminder: String { s("Create Calendar Reminder", "建立日曆提醒") }
    var creatingReminder: String { s("Creating...", "建立中...") }
    var reminderCreated: String { s("Reminder Created", "已建立提醒") }

    // MARK: - LLM Model Settings
    var llmModels: String { s("LLM Models", "LLM 模型") }
    var llmModelsDesc: String { s("Configure AI models for different tasks", "設定不同任務使用的 AI 模型") }
    var classificationModelLabel: String { s("Classification", "分類") }
    var classificationModelDesc: String { s("Email intent classification (fast, cheap)", "郵件意圖分類（快速、便宜）") }
    var extractionModelLabel: String { s("Extraction", "擷取") }
    var extractionModelDesc: String { s("Transaction extraction from emails", "從郵件擷取交易資料") }
    var statementModelLabel: String { s("Statement Parsing", "帳單解析") }
    var statementModelDesc: String { s("Credit card PDF parsing (needs strong reasoning)", "信用卡 PDF 解析（需要強推理能力）") }
    var chatModelLabel: String { s("AI Chat", "AI 聊天") }
    var chatModelDesc: String { s("Financial advisor chat with tool calling", "財務顧問聊天（含工具呼叫）") }
    var resetToDefaults: String { s("Reset to Defaults", "恢復預設") }
}
