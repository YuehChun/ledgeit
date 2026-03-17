import SwiftUI

// MARK: - Data Model

struct FeatureCard: Identifiable {
    let id = UUID()
    let index: Int
    let titleEN: String
    let titleZH: String
    let descriptionEN: String
    let descriptionZH: String
    let accentColor: Color
    let iconName: String

    static let allCards: [FeatureCard] = [
        FeatureCard(
            index: 0,
            titleEN: "Smart Extraction",
            titleZH: "\u{667A}\u{6167}\u{64F7}\u{53D6}",
            descriptionEN: "Automatically extract transactions from Gmail receipts and bank notifications.",
            descriptionZH: "\u{81EA}\u{52D5}\u{5F9E} Gmail \u{6536}\u{64DA}\u{8207}\u{9280}\u{884C}\u{901A}\u{77E5}\u{4E2D}\u{64F7}\u{53D6}\u{4EA4}\u{6613}\u{8CC7}\u{6599}\u{3002}",
            accentColor: Color(red: 0.145, green: 0.388, blue: 0.922), // #2563eb
            iconName: "envelope.fill"
        ),
        FeatureCard(
            index: 1,
            titleEN: "Dashboard",
            titleZH: "\u{8CA1}\u{52D9}\u{7E3D}\u{89BD}",
            descriptionEN: "See your complete financial picture at a glance with rich visualizations.",
            descriptionZH: "\u{900F}\u{904E}\u{8C50}\u{5BCC}\u{7684}\u{8996}\u{89BA}\u{5316}\u{5716}\u{8868}\u{FF0C}\u{4E00}\u{76EE}\u{4E86}\u{7136}\u{60A8}\u{7684}\u{8CA1}\u{52D9}\u{72C0}\u{6CC1}\u{3002}",
            accentColor: Color(red: 0.961, green: 0.620, blue: 0.043), // #f59e0b
            iconName: "chart.bar.fill"
        ),
        FeatureCard(
            index: 2,
            titleEN: "Spending Diary",
            titleZH: "\u{6D88}\u{8CBB}\u{65E5}\u{8A18}",
            descriptionEN: "Track daily spending with a beautiful calendar-based diary view.",
            descriptionZH: "\u{4EE5}\u{7CBE}\u{7F8E}\u{7684}\u{65E5}\u{66C6}\u{65E5}\u{8A18}\u{6A21}\u{5F0F}\u{8FFD}\u{8E64}\u{6BCF}\u{65E5}\u{6D88}\u{8CBB}\u{3002}",
            accentColor: Color(red: 0.220, green: 0.741, blue: 0.973), // #38bdf8
            iconName: "calendar.badge.clock"
        ),
        FeatureCard(
            index: 3,
            titleEN: "AI Advisory",
            titleZH: "AI \u{7406}\u{8CA1}\u{9867}\u{554F}",
            descriptionEN: "Get personalized financial advice powered by AI that understands your habits.",
            descriptionZH: "\u{7372}\u{5F97} AI \u{6839}\u{64DA}\u{60A8}\u{7684}\u{6D88}\u{8CBB}\u{7FD2}\u{6163}\u{63D0}\u{4F9B}\u{7684}\u{500B}\u{4EBA}\u{5316}\u{7406}\u{8CA1}\u{5EFA}\u{8B70}\u{3002}",
            accentColor: Color(red: 0.925, green: 0.286, blue: 0.600), // #ec4899
            iconName: "bubble.left.and.bubble.right.fill"
        ),
        FeatureCard(
            index: 4,
            titleEN: "Financial Analysis",
            titleZH: "\u{8CA1}\u{52D9}\u{5206}\u{6790}",
            descriptionEN: "Deep insights into your spending patterns with detailed breakdowns.",
            descriptionZH: "\u{6DF1}\u{5165}\u{5206}\u{6790}\u{60A8}\u{7684}\u{6D88}\u{8CBB}\u{6A21}\u{5F0F}\u{FF0C}\u{63D0}\u{4F9B}\u{8A73}\u{7D30}\u{7684}\u{5206}\u{985E}\u{660E}\u{7D30}\u{3002}",
            accentColor: Color(red: 0.545, green: 0.361, blue: 0.965), // #8b5cf6
            iconName: "chart.pie.fill"
        ),
        FeatureCard(
            index: 5,
            titleEN: "Goal Tracking",
            titleZH: "\u{8CA1}\u{52D9}\u{76EE}\u{6A19}",
            descriptionEN: "Set savings goals and track your progress with smart milestones.",
            descriptionZH: "\u{8A2D}\u{5B9A}\u{5132}\u{84C4}\u{76EE}\u{6A19}\u{4E26}\u{900F}\u{904E}\u{667A}\u{6167}\u{91CC}\u{7A0B}\u{7891}\u{8FFD}\u{8E64}\u{9032}\u{5EA6}\u{3002}",
            accentColor: Color(red: 0.133, green: 0.773, blue: 0.369), // #22c55e
            iconName: "target"
        ),
    ]
}

// MARK: - FeatureCardView

struct FeatureCardView: View {
    let card: FeatureCard
    let language: String
    let isVisible: Bool
    let isLastCard: Bool
    let onGetStarted: () -> Void

    @State private var animateIn = false

    private var title: String {
        language == "zh-Hant" ? card.titleZH : card.titleEN
    }

    private var description: String {
        language == "zh-Hant" ? card.descriptionZH : card.descriptionEN
    }

    var body: some View {
        VStack(spacing: 24) {
            // Illustration area
            ZStack {
                // Radial glow background
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                card.accentColor.opacity(0.3),
                                card.accentColor.opacity(0.0),
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .scaleEffect(animateIn ? 1.0 : 0.5)
                    .opacity(animateIn ? 1.0 : 0.0)

                // Floating accent elements
                floatingElements

                // Main icon
                Image(systemName: card.iconName)
                    .font(.system(size: 64))
                    .foregroundStyle(card.accentColor)
                    .scaleEffect(animateIn ? 1.0 : 0.3)
                    .opacity(animateIn ? 1.0 : 0.0)
            }
            .frame(height: 260)

            // Title
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Color(red: 0.910, green: 0.929, blue: 0.961)) // #e8edf5
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 20)

            // Description
            Text(description)
                .font(.system(size: 16))
                .foregroundColor(Color(red: 0.478, green: 0.545, blue: 0.659)) // #7a8ba8
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: 320)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 20)

            // Get Started button (last card only)
            if isLastCard {
                Button(action: onGetStarted) {
                    Text(language == "zh-Hant" ? "\u{958B}\u{59CB}\u{4F7F}\u{7528} \u{2192}" : "Get Started \u{2192}")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.114, green: 0.306, blue: 0.847), // #1d4ed8
                                    Color(red: 0.145, green: 0.388, blue: 0.922), // #2563eb
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(animateIn ? 1.0 : 0.0)
                .scaleEffect(animateIn ? 1.0 : 0.8)
            }
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                animateIn = false
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    animateIn = true
                }
            } else {
                animateIn = false
            }
        }
        .onAppear {
            if isVisible {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                    animateIn = true
                }
            }
        }
    }

    // MARK: - Floating Elements

    @ViewBuilder
    private var floatingElements: some View {
        switch card.index {
        case 0:
            // Transaction chips
            chipView(emoji: "\u{2615}", amount: "$45")
                .offset(x: -80, y: -60)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: animateIn)

            chipView(emoji: "\u{1F354}", amount: "$189")
                .offset(x: 80, y: -30)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.35), value: animateIn)

            chipView(emoji: "\u{1F6D2}", amount: "$520")
                .offset(x: -60, y: 70)
                .opacity(animateIn ? 1.0 : 0.0)
                .offset(y: animateIn ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5), value: animateIn)

        case 1:
            // Bar chart bars
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let heights: [CGFloat] = [40, 65, 50, 80, 55]
                    RoundedRectangle(cornerRadius: 4)
                        .fill(card.accentColor.opacity(0.7))
                        .frame(width: 14, height: animateIn ? heights[i] : 0)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.6).delay(0.2 + Double(i) * 0.08),
                            value: animateIn
                        )
                }
            }
            .offset(x: 70, y: 50)

        case 2:
            // Pen icon
            Image(systemName: "pencil.line")
                .font(.system(size: 28))
                .foregroundStyle(card.accentColor.opacity(0.8))
                .offset(x: 75, y: -50)
                .rotationEffect(.degrees(animateIn ? -15 : -45))
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: animateIn)

            // Diary snippet
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .frame(width: 90, height: 50)
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(card.accentColor.opacity(0.5))
                            .frame(width: 60, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 45, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 55, height: 4)
                    }
                )
                .offset(x: -70, y: 65)
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4), value: animateIn)

        case 3:
            // Chat bubbles
            chatBubble(text: "How can I save?", isLeft: true)
                .offset(x: -55, y: -65)
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: animateIn)

            chatBubble(text: "Cut dining 20%", isLeft: false)
                .offset(x: 55, y: -25)
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.4), value: animateIn)

            chatBubble(text: "Set a budget!", isLeft: true)
                .offset(x: -50, y: 60)
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6), value: animateIn)

        case 4:
            // Pie segments using trim animation
            pieSegment(startAngle: 0, endAngle: 120, color: card.accentColor)
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: animateIn)

            pieSegment(startAngle: 120, endAngle: 220, color: card.accentColor.opacity(0.7))
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.35), value: animateIn)

            pieSegment(startAngle: 220, endAngle: 360, color: card.accentColor.opacity(0.4))
                .opacity(animateIn ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.5), value: animateIn)

        case 5:
            // Progress bar filling to 72%
            VStack(spacing: 6) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 160, height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [card.accentColor.opacity(0.8), card.accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animateIn ? 115 : 0, height: 12) // 72% of 160
                        .animation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.3), value: animateIn)
                }

                Text("72%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(card.accentColor)
                    .opacity(animateIn ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.3).delay(0.6), value: animateIn)
            }
            .offset(y: 80)

        default:
            EmptyView()
        }
    }

    // MARK: - Helper Views

    private func chipView(emoji: String, amount: String) -> some View {
        HStack(spacing: 6) {
            Text(emoji)
                .font(.system(size: 14))
            Text(amount)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
        )
    }

    private func chatBubble(text: String, isLeft: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isLeft ? card.accentColor.opacity(0.3) : Color.white.opacity(0.1))
            )
    }

    private func pieSegment(startAngle: Double, endAngle: Double, color: Color) -> some View {
        PieSlice(startAngle: .degrees(startAngle - 90), endAngle: .degrees(endAngle - 90))
            .fill(color)
            .frame(width: 70, height: 70)
            .offset(x: 75, y: -60)
    }
}

// MARK: - Pie Slice Shape

private struct PieSlice: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}
