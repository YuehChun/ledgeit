import Testing
import Foundation
@testable import LedgeIt

struct ProFeatureGateTests {
    @Test func proStatus_allowsAccess() async {
        let deps = LicenseManagerTests.MockLicenseDeps(
            storedKey: "key",
            validationResult: .valid
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        #expect(isPro == true)
    }

    @Test func communityStatus_blocksAccess() async {
        let deps = LicenseManagerTests.MockLicenseDeps(
            storedKey: nil,
            trialActive: false
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == false)
        #expect(status == .community)
    }

    @Test func expiredStatus_blocksAccess() async {
        let deps = LicenseManagerTests.MockLicenseDeps(
            storedKey: "key",
            validationResult: .expired
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == false)
        #expect(status == .expired)
    }

    @Test func trialStatus_allowsAccess() async {
        let deps = LicenseManagerTests.MockLicenseDeps(
            storedKey: nil,
            trialActive: true
        )
        let manager = await LicenseManager(deps: deps)
        await manager.validate()
        let isPro = await manager.isPro
        let status = await manager.status
        #expect(isPro == true)
        #expect(status == .trial)
    }
}
