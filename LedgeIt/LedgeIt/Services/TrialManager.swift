import Foundation

@MainActor
final class TrialManager {
    static let trialDurationDays = 14

    private let nowProvider: @Sendable () -> Date
    private let loadTrialStart: @Sendable () -> Date?
    private let saveTrialStart: @Sendable (Date) -> Void
    private var _trialStartDate: Date?

    init(
        now: @escaping @Sendable () -> Date = { Date() },
        loadTrialStart: @escaping @Sendable () -> Date? = {
            guard let str = KeychainService.load(key: .trialStartDate) else { return nil }
            return ISO8601DateFormatter().date(from: str)
        },
        saveTrialStart: @escaping @Sendable (Date) -> Void = { date in
            try? KeychainService.save(key: .trialStartDate, value: ISO8601DateFormatter().string(from: date))
        }
    ) {
        self.nowProvider = now
        self.loadTrialStart = loadTrialStart
        self.saveTrialStart = saveTrialStart
        self._trialStartDate = loadTrialStart()
    }

    private var trialStartDate: Date {
        if let existing = _trialStartDate { return existing }
        let now = nowProvider()
        _trialStartDate = now
        saveTrialStart(now)
        return now
    }

    var isTrialActive: Bool {
        let elapsed = nowProvider().timeIntervalSince(trialStartDate)
        return elapsed < Double(Self.trialDurationDays) * 24 * 3600
    }

    var daysRemaining: Int {
        #if DEBUG
        if let override = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--trial-days-remaining=") }) {
            let value = override.split(separator: "=").last.flatMap { Int($0) } ?? 0
            return value
        }
        #endif
        let elapsed = nowProvider().timeIntervalSince(trialStartDate)
        let remaining = Double(Self.trialDurationDays) - (elapsed / (24 * 3600))
        return max(0, Int(remaining))
    }

    static let shared = TrialManager()
}
