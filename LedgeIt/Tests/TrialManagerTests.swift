import Foundation
import Testing
@testable import LedgeIt

struct TrialManagerTests {
    @Test func newUserTrialIsActive() async {
        let manager = await TrialManager(
            now: { Date(timeIntervalSince1970: 1000000) },
            loadTrialStart: { nil },
            saveTrialStart: { _ in }
        )
        await #expect(manager.isTrialActive == true)
    }

    @Test func trialExpiredAfter14Days() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(15 * 24 * 3600) // 15 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in }
        )
        await #expect(manager.isTrialActive == false)
    }

    @Test func trialActiveWithin14Days() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(10 * 24 * 3600) // 10 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in }
        )
        await #expect(manager.isTrialActive == true)
        await #expect(manager.daysRemaining == 4)
    }

    @Test func trialStartDateSavedOnFirstAccess() async {
        final class Box: @unchecked Sendable { var value: Date? }
        let box = Box()
        let manager = await TrialManager(
            now: { Date(timeIntervalSince1970: 1000000) },
            loadTrialStart: { nil },
            saveTrialStart: { box.value = $0 }
        )
        _ = await manager.isTrialActive
        #expect(box.value != nil)
    }
}
