import SwiftUI

struct TrialBannerView: View {
    let daysRemaining: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)

            Text("Pro Trial: \(daysRemaining) days left")
                .font(.caption.bold())

            Spacer()

            Link("Upgrade", destination: URL(string: "https://ledgeit.lemonsqueezy.com")!)
                .font(.caption.bold())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 8)
    }
}
