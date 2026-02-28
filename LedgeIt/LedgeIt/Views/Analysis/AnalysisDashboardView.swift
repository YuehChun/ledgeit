import SwiftUI
import Charts

struct AnalysisDashboardView: View {
    @State private var report: ReportGenerator.FullReport?
    @State private var isGenerating = false
    @State private var progress = ""
    @State private var errorMessage: String?
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
    private var l10n: L10n { L10n(appLanguage) }
    private var persona: AdvisorPersona {
        AdvisorPersona.resolve(id: personaId, customSavingsTarget: customSavingsTarget, customRiskLevel: customRiskLevel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                if let report {
                    healthScoreCard(report.advice)
                    adviceSection(report.advice)
                    if !report.monthlyReport.anomalies.isEmpty {
                        anomaliesSection(report.monthlyReport.anomalies)
                    }
                    categoryInsightsSection(report.advice.categoryInsights)
                    savingsTrendChart(report.trends)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title).foregroundStyle(.red)
                        Text(l10n.analysisFailed)
                            .font(.headline)
                        Text(errorMessage)
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(l10n.tryAgain) { generateReport() }
                            .buttonStyle(.bordered)
                    }
                    .padding(.top, 40)
                } else if !isGenerating {
                    emptyState
                }
            }
            .padding(20)
        }
        .navigationTitle(l10n.financialAnalysis)
        .onAppear { restoreReport() }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.financialAnalysis)
                    .font(.title2).fontWeight(.bold)
                Text(l10n.analysisSubtitle)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button { generateReport() } label: {
                    Label(report != nil ? l10n.refreshReport : l10n.generateReport, systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    // MARK: - Health Score

    private func healthScoreCard(_ advice: FinancialAdvisor.SpendingAdvice) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(advice.healthScore) / 100.0)
                    .stroke(healthScoreColor(advice.healthScore), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(advice.healthScore)")
                        .font(.title).fontWeight(.bold).monospacedDigit()
                    Text("/ 100")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.financialHealthScore)
                    .font(.headline)
                Text(advice.overallAssessment)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func healthScoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func budgetStatusColor(category: String) -> Color {
        guard let report,
              let budgetPct = persona.categoryBudgetHints[category] else { return .secondary }
        let income = report.monthlyReport.totalIncome
        guard income > 0 else { return .secondary }
        let budgetLimit = income * budgetPct
        let actual = report.monthlyReport.categoryBreakdown.first { $0.category == category }?.amount ?? 0
        if actual <= budgetLimit * 0.8 { return .green }
        if actual <= budgetLimit { return .yellow }
        return .red
    }

    // MARK: - Advice Section

    private func adviceSection(_ advice: FinancialAdvisor.SpendingAdvice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !advice.positiveHabits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(l10n.positiveHabits, systemImage: "hand.thumbsup.fill")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    ForEach(advice.positiveHabits, id: \.self) { habit in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.callout)
                            Text(habit).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(l10n.actionItems, systemImage: "bolt.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                ForEach(advice.actionItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue).font(.callout)
                        Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !advice.concerns.isEmpty {
                    Divider()
                    ForEach(advice.concerns, id: \.self) { concern in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
                            Text(concern).font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Anomalies

    private func anomaliesSection(_ anomalies: [SpendingAnalyzer.AnomalyAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(l10n.unusualSpending, systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            ForEach(anomalies) { anomaly in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(anomaly.merchant).font(.callout).fontWeight(.medium)
                        Text(anomaly.date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(anomaly.currency) \(String(format: "%.0f", anomaly.amount))")
                            .font(.callout).fontWeight(.semibold).monospacedDigit()
                        Text("\(String(format: "%.1f", anomaly.deviation))\(l10n.avgSuffix)")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Category Insights

    private func categoryInsightsSection(_ insights: [FinancialAdvisor.CategoryInsight]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l10n.categoryInsights, systemImage: "chart.pie.fill")
                .font(.headline)
            ForEach(insights, id: \.category) { insight in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                            .font(.callout).fontWeight(.semibold)
                        Spacer()
                        if let budgetPct = persona.categoryBudgetHints[insight.category] {
                            Text("\(Int(budgetPct * 100))% max")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(budgetStatusColor(category: insight.category).opacity(0.15))
                                .foregroundStyle(budgetStatusColor(category: insight.category))
                                .clipShape(Capsule())
                        }
                    }
                    Text(insight.assessment)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let suggestion = insight.suggestion {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill").foregroundStyle(.yellow).font(.caption)
                            Text(suggestion)
                                .font(.callout).foregroundStyle(.blue)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Savings Trend

    private func savingsTrendChart(_ trends: [SpendingAnalyzer.MonthTrend]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(l10n.savingsRateTrend, systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)
            Chart(trends) { trend in
                LineMark(
                    x: .value("Month", trend.label),
                    y: .value("Rate", trend.savingsRate * 100)
                )
                .foregroundStyle(.green)
                .symbol(Circle())
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Month", trend.label),
                    y: .value("Rate", trend.savingsRate * 100)
                )
                .foregroundStyle(.green)
                .annotation(position: .top) {
                    Text("\(String(format: "%.0f", trend.savingsRate * 100))%")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                RuleMark(y: .value("Target", persona.savingsTarget * 100))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .chartYAxisLabel("Savings Rate %")
            .frame(height: 240)

            Text(l10n.savingsTarget)
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            l10n.noAnalysisYet,
            systemImage: "chart.bar.doc.horizontal",
            description: Text(l10n.noAnalysisDescription)
        )
        .padding(.top, 40)
    }

    // MARK: - Generate

    private func generateReport() {
        isGenerating = true
        errorMessage = nil
        Task {
            defer { isGenerating = false; progress = "" }
            do {
                let openRouter = try OpenRouterService()
                let generator = ReportGenerator(database: AppDatabase.shared, openRouter: openRouter)
                let calendar = Calendar.current
                let now = Date()
                let year = calendar.component(.year, from: now)
                let month = calendar.component(.month, from: now)

                // Observe progress
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        progress = generator.progress
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }

                report = try await generator.generateMonthlyReport(year: year, month: month, language: appLanguage, persona: persona)
                progressTask.cancel()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreReport() {
        guard report == nil, !isGenerating else { return }
        Task {
            do {
                let db = AppDatabase.shared
                let saved = try await db.db.read { db in
                    try FinancialReport
                        .order(FinancialReport.Columns.createdAt.desc)
                        .fetchOne(db)
                }
                guard let saved,
                      let adviceData = saved.adviceJSON.data(using: .utf8) else { return }

                let decoder = JSONDecoder()
                let advice = try decoder.decode(FinancialAdvisor.SpendingAdvice.self, from: adviceData)

                let components = saved.periodStart.split(separator: "-")
                guard components.count >= 2,
                      let year = Int(components[0]),
                      let month = Int(components[1]) else { return }

                let analyzer = SpendingAnalyzer(database: db)
                let monthlyReport = try analyzer.monthlyBreakdown(year: year, month: month)
                let trends = try analyzer.spendingTrend(months: 6)

                report = ReportGenerator.FullReport(
                    monthlyReport: monthlyReport,
                    trends: trends,
                    advice: advice,
                    goals: GoalPlanner.GoalSuggestions(shortTerm: [], longTerm: [])
                )
            } catch {
                print("AnalysisDashboardView: failed to restore report: \(error)")
            }
        }
    }
}
