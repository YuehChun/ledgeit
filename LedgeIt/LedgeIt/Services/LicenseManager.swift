import Foundation

enum LicenseStatus: Equatable, Sendable {
    case community
    case trial
    case pro
    case proOffline
    case expired
}

enum LicenseValidationResult: Sendable {
    case valid
    case expired
    case invalid
    case networkError
}

protocol LicenseManagerDependencies: Sendable {
    func loadLicenseKey() -> String?
    func saveLicenseKey(_ key: String)
    func deleteLicenseKey()
    func loadValidatedAt() -> Date?
    func saveValidatedAt(_ date: Date)
    func validateRemote(key: String) async -> LicenseValidationResult
    func currentDate() -> Date
    func isTrialActive() -> Bool
}

@MainActor
@Observable
final class LicenseManager {
    static let gracePeriodDays = 7
    static let shared = LicenseManager(deps: DefaultLicenseDeps())

    private(set) var status: LicenseStatus = .community
    private let deps: LicenseManagerDependencies

    var isPro: Bool {
        #if DEBUG
        if CommandLine.arguments.contains("--force-pro") { return true }
        #endif
        switch status {
        case .pro, .proOffline, .trial: return true
        case .community, .expired: return false
        }
    }

    init(deps: LicenseManagerDependencies) {
        self.deps = deps
    }

    func validate() async {
        guard let key = deps.loadLicenseKey() else {
            status = deps.isTrialActive() ? .trial : .community
            return
        }

        let result = await deps.validateRemote(key: key)
        switch result {
        case .valid:
            deps.saveValidatedAt(deps.currentDate())
            status = .pro
        case .expired:
            status = .expired
        case .invalid:
            deps.deleteLicenseKey()
            status = deps.isTrialActive() ? .trial : .community
        case .networkError:
            if let lastValidated = deps.loadValidatedAt() {
                let elapsed = deps.currentDate().timeIntervalSince(lastValidated)
                if elapsed < Double(Self.gracePeriodDays) * 24 * 3600 {
                    status = .proOffline
                } else {
                    status = .community
                }
            } else {
                status = deps.isTrialActive() ? .trial : .community
            }
        }
    }

    func activate(key: String) async -> Bool {
        deps.saveLicenseKey(key)
        await validate()
        return isPro
    }

    func deactivate() {
        deps.deleteLicenseKey()
        status = deps.isTrialActive() ? .trial : .community
    }
}

struct DefaultLicenseDeps: LicenseManagerDependencies {
    // Use a sendable closure to capture trial state without crossing actor boundaries
    private let trialActiveProvider: @Sendable () -> Bool

    init(trialActiveProvider: @escaping @Sendable () -> Bool = {
        // Access TrialManager.shared synchronously — safe because TrialManager only
        // reads Date values and we accept any data race on first access here.
        // In production this is always called from LicenseManager which is @MainActor.
        // For the default, we approximate using the stored trial start from Keychain.
        guard let str = KeychainService.load(key: .trialStartDate),
              let startDate = ISO8601DateFormatter().date(from: str) else {
            // No trial start recorded yet — trial begins now, so it's active
            return true
        }
        let elapsed = Date().timeIntervalSince(startDate)
        return elapsed < Double(14) * 24 * 3600
    }) {
        self.trialActiveProvider = trialActiveProvider
    }

    func loadLicenseKey() -> String? {
        KeychainService.load(key: .licenseKey)
    }

    func saveLicenseKey(_ key: String) {
        try? KeychainService.save(key: .licenseKey, value: key)
    }

    func deleteLicenseKey() {
        KeychainService.delete(key: .licenseKey)
    }

    func loadValidatedAt() -> Date? {
        guard let str = KeychainService.load(key: .licenseValidatedAt) else { return nil }
        return ISO8601DateFormatter().date(from: str)
    }

    func saveValidatedAt(_ date: Date) {
        try? KeychainService.save(key: .licenseValidatedAt, value: ISO8601DateFormatter().string(from: date))
    }

    func validateRemote(key: String) async -> LicenseValidationResult {
        guard let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate") else {
            return .networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["license_key": key])
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return .networkError }
            if httpResponse.statusCode >= 500 { return .networkError }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .invalid
            }

            let valid = json["valid"] as? Bool ?? false
            if valid { return .valid }

            let licenseStatus = (json["license_key"] as? [String: Any])?["status"] as? String
            if licenseStatus == "expired" { return .expired }
            return .invalid
        } catch {
            return .networkError
        }
    }

    func currentDate() -> Date { Date() }

    func isTrialActive() -> Bool { trialActiveProvider() }
}
