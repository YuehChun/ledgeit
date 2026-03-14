import SwiftUI

struct LicenseSettingsView: View {
    @State private var licenseManager = LicenseManager.shared
    @State private var licenseKeyInput = ""
    @State private var isActivating = false
    @State private var activationMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status
            HStack {
                statusIcon
                VStack(alignment: .leading) {
                    Text(statusTitle).font(.headline)
                    Text(statusSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // License key input
            if !licenseManager.isPro || licenseManager.status == .trial {
                VStack(alignment: .leading, spacing: 8) {
                    Text("License Key")
                        .font(.subheadline.bold())

                    HStack {
                        SecureField("Paste your license key", text: $licenseKeyInput)
                            .textFieldStyle(.roundedBorder)

                        Button(isActivating ? "Activating..." : "Activate") {
                            Task { await activate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(licenseKeyInput.isEmpty || isActivating)
                    }

                    if !activationMessage.isEmpty {
                        Text(activationMessage)
                            .font(.caption)
                            .foregroundStyle(licenseManager.isPro ? .green : .red)
                    }
                }

                Link("Get Pro License — $49/year", destination: URL(string: "https://ledgeit.lemonsqueezy.com")!)
                    .buttonStyle(.link)
            } else {
                Button("Deactivate License") {
                    licenseManager.deactivate()
                    licenseKeyInput = ""
                    activationMessage = ""
                }
                .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text("Support LedgeIt")
                    .font(.subheadline)
                Spacer()
                Link("GitHub Sponsors", destination: URL(string: "https://github.com/sponsors/YuehChun")!)
                    .font(.subheadline)
            }
        }
        .padding()
    }

    private func activate() async {
        isActivating = true
        activationMessage = ""
        let success = await licenseManager.activate(key: licenseKeyInput)
        if success {
            activationMessage = "License activated successfully!"
        } else {
            activationMessage = "Invalid or expired license key."
        }
        isActivating = false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch licenseManager.status {
        case .pro, .proOffline:
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)
        case .trial:
            Image(systemName: "clock.fill")
                .font(.title)
                .foregroundStyle(.orange)
        case .expired:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
        case .community:
            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }

    private var statusTitle: String {
        switch licenseManager.status {
        case .pro: return "LedgeIt Pro"
        case .proOffline: return "LedgeIt Pro (Offline)"
        case .trial: return "Pro Trial"
        case .expired: return "Subscription Expired"
        case .community: return "Community (Free)"
        }
    }

    private var statusSubtitle: String {
        switch licenseManager.status {
        case .pro: return "All Pro features are unlocked."
        case .proOffline: return "Offline mode. Will re-validate when online."
        case .trial: return "Trial active. Upgrade to keep Pro features."
        case .expired: return "Renew your subscription to restore Pro features."
        case .community: return "Upgrade to Pro for AI advisor, chat, goals, and more."
        }
    }
}
