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
