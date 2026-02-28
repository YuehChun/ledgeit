import SwiftUI

struct AdvisorSettingsView: View {
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    private var currentPersona: AdvisorPersona {
        AdvisorPersona.resolve(id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.aiAdvisor)
                        .font(.title2).fontWeight(.bold)
                    Text(l10n.aiAdvisorSubtitle)
                        .font(.callout).foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    personaCard(id: "conservative", icon: "shield.fill", color: .blue,
                                name: l10n.conservative, desc: l10n.conservativeDesc,
                                target: "30%")
                    personaCard(id: "moderate", icon: "scale.3d", color: .green,
                                name: l10n.moderate, desc: l10n.moderateDesc,
                                target: "20%")
                    personaCard(id: "aggressive", icon: "flame.fill", color: .orange,
                                name: l10n.aggressive, desc: l10n.aggressiveDesc,
                                target: "10%")
                    personaCard(id: "custom", icon: "slider.horizontal.3", color: .purple,
                                name: l10n.custom, desc: l10n.customDesc,
                                target: "\(Int(customSavingsTarget * 100))%")
                }

                if personaId == "custom" {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.savingsTargetLabel)
                            .font(.subheadline).fontWeight(.semibold)

                        HStack {
                            Slider(value: $customSavingsTarget, in: 0.05...0.50, step: 0.05)
                            Text("\(Int(customSavingsTarget * 100))%")
                                .font(.title3).fontWeight(.bold).monospacedDigit()
                                .frame(width: 50)
                        }

                        Text(l10n.riskLevel)
                            .font(.subheadline).fontWeight(.semibold)

                        Picker(l10n.riskLevel, selection: $customRiskLevel) {
                            Text(l10n.riskLow).tag("low")
                            Text(l10n.riskMedium).tag("medium")
                            Text(l10n.riskHigh).tag("high")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }
                    .padding(16)
                    .background(.background.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label(l10n.categoryBudgets, systemImage: "chart.bar.fill")
                        .font(.headline)

                    let sortedHints = currentPersona.categoryBudgetHints.sorted { $0.value > $1.value }
                    ForEach(sortedHints, id: \.key) { category, maxPct in
                        HStack {
                            Text(CategoryStyle.style(forRawCategory: category).displayName)
                                .font(.callout)
                            Spacer()
                            Text("\(Int(maxPct * 100))% \(l10n.ofIncome)")
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                .padding(16)
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
        }
        .navigationTitle(l10n.aiAdvisor)
    }

    private func personaCard(id: String, icon: String, color: Color, name: String, desc: String, target: String) -> some View {
        Button {
            personaId = id
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                    Text(target)
                        .font(.title3).fontWeight(.bold).monospacedDigit()
                        .foregroundStyle(color)
                }
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(personaId == id ? color.opacity(0.08) : Color.clear)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(personaId == id ? color : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
