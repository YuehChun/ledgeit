import SwiftUI

struct FeatureTourView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"

    @State private var currentPage = 0
    let onComplete: () -> Void

    private let cards = FeatureCard.allCards

    var body: some View {
        ZStack {
            // Deep blue gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.05, blue: 0.10),
                    Color(red: 0.05, green: 0.11, blue: 0.18),
                    Color(red: 0.07, green: 0.13, blue: 0.25),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("LedgeIt")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.29, green: 0.42, blue: 0.54))
                        .tracking(2)
                        .textCase(.uppercase)

                    Spacer()

                    // Language toggle
                    Button {
                        appLanguage = appLanguage == "zh-Hant" ? "en" : "zh-Hant"
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(appLanguage == "zh-Hant" ? "繁中" : "EN")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Color(red: 0.23, green: 0.35, blue: 0.48))
                    }
                    .buttonStyle(.plain)

                    // Skip button
                    Button(appLanguage == "zh-Hant" ? "略過" : "Skip") {
                        onComplete()
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.23, green: 0.35, blue: 0.48))
                    .buttonStyle(.plain)
                    .padding(.leading, 12)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Page content
                ZStack {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        if index == currentPage {
                            FeatureCardView(
                                card: card,
                                language: appLanguage,
                                isVisible: true,
                                isLastCard: index == cards.count - 1,
                                onGetStarted: onComplete
                            )
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity
                            ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50)
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            if value.translation.width < -threshold, currentPage < cards.count - 1 {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPage += 1
                                }
                            } else if value.translation.width > threshold, currentPage > 0 {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPage -= 1
                                }
                            }
                        }
                )

                // Custom page dots
                HStack(spacing: 8) {
                    ForEach(0..<cards.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? cards[index].accentColor : Color(red: 0.10, green: 0.16, blue: 0.26))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentPage)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentPage = index
                                }
                            }
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }
}
