import Testing
import Foundation
@testable import LedgeIt

struct LicenseManagerTests {
    struct MockLicenseDeps: LicenseManagerDependencies {
        var storedKey: String?
        var storedValidatedAt: Date?
        var validationResult: LicenseValidationResult = .valid
        var trialActive: Bool = false
        var now: Date = Date()

        func loadLicenseKey() -> String? { storedKey }
        func saveLicenseKey(_ key: String) {}
        func deleteLicenseKey() {}
        func loadValidatedAt() -> Date? { storedValidatedAt }
        func saveValidatedAt(_ date: Date) {}
        func validateRemote(key: String) async -> LicenseValidationResult { validationResult }
        func currentDate() -> Date { now }
        func isTrialActive() -> Bool { trialActive }
    }

    @Test func noKeyNoTrial_isCommunity() async {
        let deps = MockLicenseDeps(storedKey: nil, trialActive: false)
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == false)
        #expect(status == .community)
    }

    @Test func noKeyButTrialActive_isPro() async {
        let deps = MockLicenseDeps(storedKey: nil, trialActive: true)
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == true)
        #expect(status == .trial)
    }

    @Test func validKey_isPro() async {
        let deps = MockLicenseDeps(
            storedKey: "test-key-123",
            validationResult: .valid
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == true)
        #expect(status == .pro)
    }

    @Test func expiredKey_isNotPro() async {
        let deps = MockLicenseDeps(
            storedKey: "test-key-123",
            validationResult: .expired
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == false)
        #expect(status == .expired)
    }

    @Test func offlineWithRecentValidation_isPro() async {
        let now = Date()
        let deps = MockLicenseDeps(
            storedKey: "test-key-123",
            storedValidatedAt: now.addingTimeInterval(-3 * 24 * 3600),
            validationResult: .networkError,
            now: now
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == true)
        #expect(status == .proOffline)
    }

    @Test func offlineWithStaleValidation_isNotPro() async {
        let now = Date()
        let deps = MockLicenseDeps(
            storedKey: "test-key-123",
            storedValidatedAt: now.addingTimeInterval(-10 * 24 * 3600),
            validationResult: .networkError,
            now: now
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == false)
        #expect(status == .community)
    }
}
