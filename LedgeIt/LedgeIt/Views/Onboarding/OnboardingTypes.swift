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

    /// User-visible step number (skipping auto-advance steps)
    /// welcome=1, apiKey=2, apiKeyTest=2, gmailAuth=3, emailSync=4, emailReview=5,
    /// pdfPassword=6, financialReport=7, suggestions=8, complete=9
    static let totalVisibleSteps = 7

    var visibleStepIndex: Int {
        switch self {
        case .welcome: return 1
        case .apiKey, .apiKeyTest: return 2
        case .gmailAuth: return 3
        case .emailSync, .emailReview: return 4
        case .pdfPassword: return 5
        case .financialReport: return 6
        case .suggestions, .complete: return 7
        }
    }

    func stepTitle(language: String) -> String {
        let zh = language == "zh-Hant"
        switch self {
        case .welcome:
            return zh ? "語言設定" : "Language"
        case .apiKey, .apiKeyTest:
            return zh ? "AI 服務設定" : "AI Service"
        case .gmailAuth:
            return zh ? "Gmail 認證" : "Gmail Auth"
        case .emailSync, .emailReview:
            return zh ? "郵件同步與審核" : "Email Sync & Review"
        case .pdfPassword:
            return zh ? "PDF 密碼" : "PDF Password"
        case .financialReport:
            return zh ? "財務報告" : "Financial Report"
        case .suggestions, .complete:
            return zh ? "財務建議" : "Suggestions"
        }
    }

    var stepIcon: String {
        switch self {
        case .welcome: return "globe"
        case .apiKey, .apiKeyTest: return "key.fill"
        case .gmailAuth: return "envelope.fill"
        case .emailSync, .emailReview: return "arrow.triangle.2.circlepath"
        case .pdfPassword: return "lock.doc.fill"
        case .financialReport: return "chart.bar.fill"
        case .suggestions, .complete: return "lightbulb.fill"
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
