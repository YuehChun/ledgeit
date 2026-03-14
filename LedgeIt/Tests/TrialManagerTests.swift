import Foundation
import Testing
@testable import LedgeIt

struct TrialManagerTests {
    @Test func newUserTrialIsActive() async {
        let manager = await TrialManager(
            now: { Date(timeIntervalSince1970: 1000000) },
            loadTrialStart: { nil },
            saveTrialStart: { _ in },
            isExistingUser: { false }
        )
        await #expect(manager.isTrialActive == true)
    }

    @Test func trialExpiredAfter14Days() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(15 * 24 * 3600) // 15 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in },
            isExistingUser: { false }
        )
        await #expect(manager.isTrialActive == false)
    }

    @Test func trialActiveWithin14Days() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(10 * 24 * 3600) // 10 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in },
            isExistingUser: { false }
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
            saveTrialStart: { box.value = $0 },
            isExistingUser: { false }
        )
        _ = await manager.isTrialActive
        #expect(box.value != nil)
    }

    // Existing user migration tests
    @Test func existingUserGets90DayTrial() async {
        let manager = await TrialManager(
            now: { Date(timeIntervalSince1970: 1000000) },
            loadTrialStart: { nil },
            saveTrialStart: { _ in },
            isExistingUser: { true }
        )
        await #expect(manager.isTrialActive == true)
        await #expect(manager.daysRemaining == 90)
    }

    @Test func existingUser60DaysIn_still30DaysLeft() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(60 * 24 * 3600) // 60 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in },
            isExistingUser: { true }
        )
        await #expect(manager.isTrialActive == true)
        await #expect(manager.daysRemaining == 30)
    }

    @Test func existingUserTrialExpiredAfter90Days() async {
        let startDate = Date(timeIntervalSince1970: 1000000)
        let now = startDate.addingTimeInterval(91 * 24 * 3600) // 91 days later
        let manager = await TrialManager(
            now: { now },
            loadTrialStart: { startDate },
            saveTrialStart: { _ in },
            isExistingUser: { true }
        )
        await #expect(manager.isTrialActive == false)
    }
}
