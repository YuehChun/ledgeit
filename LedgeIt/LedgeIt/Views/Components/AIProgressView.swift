import SwiftUI

struct AIProgressView: View {
    let title: String
    let steps: [String]
    let currentStep: Int

    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            // Indeterminate shimmer bar
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.15))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.3),
                                    Color.accentColor.opacity(0.8),
                                    Color.accentColor.opacity(0.3)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.3)
                        .offset(x: shimmerOffset * width * 0.85)
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())
            .onAppear {
                withAnimation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 1
                }
            }

            // Step list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 6) {
                        stepIcon(for: index)
                            .frame(width: 14, height: 14)

                        Text(stepLabel(for: index, step: step))
                            .font(.caption)
                            .foregroundStyle(stepColor(for: index))
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Step Rendering

    @ViewBuilder
    private func stepIcon(for index: Int) -> some View {
        if index < currentStep {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if index == currentStep {
            PulsingDot()
        } else {
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stepLabel(for index: Int, step: String) -> String {
        if index == currentStep {
            return step + "..."
        }
        return step
    }

    private func stepColor(for index: Int) -> some ShapeStyle {
        if index < currentStep {
            return AnyShapeStyle(.secondary)
        } else if index == currentStep {
            return AnyShapeStyle(.primary)
        } else {
            return AnyShapeStyle(.tertiary)
        }
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.caption)
            .foregroundStyle(.blue)
            .opacity(isPulsing ? 0.4 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}
