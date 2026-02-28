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
    var noGoalsDescription: String { s("Generate a Financial Analysis first to get AI-suggested goals.", "請先產生財務分析以獲得 AI 建議的目標。") }
    var noFilteredGoals: String { s("Try switching to a different filter to see your goals.", "請嘗試切換不同的篩選條件以查看目標。") }
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
    var applyButton: String { s("Apply & Regenerate", "套用並重新產生") }
    var applying: String { s("Applying changes...", "正在套用變更...") }
    var versionHistory: String { s("Version History", "版本歷史") }
    var initialPreset: String { s("Initial preset", "初始預設") }
    var revert: String { s("Revert", "還原") }
    var activeVersion: String { s("Active", "使用中") }

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
    var noUnreviewedTransactions: String { s("All Caught Up", "全部完成") }
    var noUnreviewedDescription: String { s("No transactions need review right now.", "目前沒有需要審核的交易。") }
    var unknownSender: String { s("Unknown sender", "未知寄件者") }
    var noSubject: String { s("No subject", "無主旨") }
    func transactionsFromEmail(_ count: Int) -> String {
        s("\(count) transaction\(count == 1 ? "" : "s")", "\(count) 筆交易")
    }

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
}
