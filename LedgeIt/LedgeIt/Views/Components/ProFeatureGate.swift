import SwiftUI

struct ProFeatureGate: ViewModifier {
    @State private var licenseManager = LicenseManager.shared
    let featureName: String

    func body(content: Content) -> some View {
        if licenseManager.isPro {
            content
        } else {
            upgradePrompt
        }
    }

    private var upgradePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Pro Feature")
                .font(.title2.bold())

            Text("\(featureName) requires LedgeIt Pro.")
                .foregroundStyle(.secondary)

            if case .expired = licenseManager.status {
                Text("Your subscription has expired.")
                    .foregroundStyle(.orange)
            }

            Link("Upgrade to Pro — $49/year", destination: URL(string: "https://ledgeit.lemonsqueezy.com")!)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Button("Enter License Key") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension View {
    func requiresPro(featureName: String = "") -> some View {
        modifier(ProFeatureGate(featureName: featureName))
    }
}
