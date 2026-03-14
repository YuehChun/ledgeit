import Foundation

@MainActor
final class TrialManager {
    static let trialDurationDays = 14
    static let existingUserTrialDays = 90

    private let nowProvider: @Sendable () -> Date
    private let loadTrialStart: @Sendable () -> Date?
    private let saveTrialStart: @Sendable (Date) -> Void
    private let isExistingUser: @Sendable () -> Bool
    private var _trialStartDate: Date?

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        loadTrialStart: @escaping @Sendable () -> Date? = {
            guard let str = KeychainService.load(key: .trialStartDate) else { return nil }
            return ISO8601DateFormatter().date(from: str)
        },
        saveTrialStart: @escaping @Sendable (Date) -> Void = { date in
            try? KeychainService.save(key: .trialStartDate, value: ISO8601DateFormatter().string(from: date))
        },
        isExistingUser: @escaping @Sendable () -> Bool = {
            // Check if app has pre-existing transactions (pre-monetization install)
            (try? AppDatabase.shared.db.read { db in
                try Transaction.fetchCount(db) > 0
            }) ?? false
        }
    ) {
        self.nowProvider = now
        self.loadTrialStart = loadTrialStart
        self.saveTrialStart = saveTrialStart
        self.isExistingUser = isExistingUser
        self._trialStartDate = loadTrialStart()
    }

    private var trialStartDate: Date {
        if let existing = _trialStartDate { return existing }
        let now = nowProvider()
        _trialStartDate = now
        saveTrialStart(now)
        return now
    }

    private var effectiveTrialDays: Int {
        isExistingUser() ? Self.existingUserTrialDays : Self.trialDurationDays
    }

    var isTrialActive: Bool {
        let elapsed = nowProvider().timeIntervalSince(trialStartDate)
        return elapsed < Double(effectiveTrialDays) * 24 * 3600
    }

    var daysRemaining: Int {
        #if DEBUG
        if let override = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--trial-days-remaining=") }) {
            let value = override.split(separator: "=").last.flatMap { Int($0) } ?? 0
            return value
        }
        #endif
        let elapsed = nowProvider().timeIntervalSince(trialStartDate)
        let remaining = Double(effectiveTrialDays) - (elapsed / (24 * 3600))
        return max(0, Int(remaining))
    }

    static let shared = TrialManager()
}
