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

    // MARK: - Dashboard

    var spendingOverview: String { s("Spending Overview", "消費概覽") }
    var thisMonth: String { s("This Month", "本月") }
    var income: String { s("Income", "收入") }
    var spending: String { s("Spending", "支出") }
    var savingsRate: String { s("Savings Rate", "儲蓄率") }

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
