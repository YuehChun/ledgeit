import SwiftUI

struct ProFeatureGate: ViewModifier {
    @State private var licenseManager = LicenseManager.shared
    let featureName: String
    let allowReadOnly: Bool

    func body(content: Content) -> some View {
        if licenseManager.isPro {
            content
        } else if allowReadOnly {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "eye.fill")
                    Text("Read-only — upgrade to Pro to edit")
                        .font(.caption)
                    Spacer()
                    Link("Upgrade", destination: URL(string: "https://ledgeit.lemonsqueezy.com")!)
                        .font(.caption.bold())
                }
                .padding(8)
                .background(.orange.opacity(0.1))

                content
                    .disabled(true)
                    .opacity(0.8)
            }
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
    func requiresPro(featureName: String = "", allowReadOnly: Bool = false) -> some View {
        modifier(ProFeatureGate(featureName: featureName, allowReadOnly: allowReadOnly))
    }
}
