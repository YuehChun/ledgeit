import SwiftUI
import Charts

struct AnalysisDashboardView: View {
    @State private var report: ReportGenerator.FullReport?
    @State private var isGenerating = false
    @State private var progress = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if let report {
                    healthScoreCard(report.advice)
                    adviceSection(report.advice)
                    if !report.monthlyReport.anomalies.isEmpty {
                        anomaliesSection(report.monthlyReport.anomalies)
                    }
                    categoryInsightsSection(report.advice.categoryInsights)
                    savingsTrendChart(report.trends)
                } else if !isGenerating {
                    emptyState
                }
            }
            .padding(20)
        }
        .navigationTitle("Financial Analysis")
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Financial Analysis")
                    .font(.title2).fontWeight(.bold)
                Text("AI-powered spending analysis and advice")
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
                    Label("Generate Report", systemImage: "sparkles")
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
                Text("Financial Health Score")
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

    // MARK: - Advice Section

    private func adviceSection(_ advice: FinancialAdvisor.SpendingAdvice) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !advice.positiveHabits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Positive Habits", systemImage: "hand.thumbsup.fill")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(.green)
                    ForEach(advice.positiveHabits, id: \.self) { habit in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                            Text(habit).font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.green.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Action Items", systemImage: "bolt.fill")
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(.blue)
                ForEach(advice.actionItems, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.blue).font(.caption)
                        Text(item).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !advice.concerns.isEmpty {
                    Divider()
                    ForEach(advice.concerns, id: \.self) { concern in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            Text(concern).font(.caption).fixedSize(horizontal: false, vertical: true)
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
            Label("Unusual Spending", systemImage: "exclamationmark.triangle.fill")
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
                        Text("\(String(format: "%.1f", anomaly.deviation))x avg")
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Category Insights").font(.headline)
            ForEach(insights, id: \.category) { insight in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(CategoryStyle.style(forRawCategory: insight.category).displayName)
                            .font(.callout).fontWeight(.medium)
                        Spacer()
                    }
                    Text(insight.assessment)
                        .font(.caption).foregroundStyle(.secondary)
                    if let suggestion = insight.suggestion {
                        Text(suggestion)
                            .font(.caption).foregroundStyle(.blue)
                    }
                }
                .padding(10)
                .background(.background.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Savings Trend

    private func savingsTrendChart(_ trends: [SpendingAnalyzer.MonthTrend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Savings Rate Trend").font(.headline)
            Chart(trends) { trend in
                LineMark(
                    x: .value("Month", trend.label),
                    y: .value("Rate", trend.savingsRate * 100)
                )
                .foregroundStyle(.green)
                .symbol(Circle())

                RuleMark(y: .value("Target", 20))
                    .foregroundStyle(.orange.opacity(0.5))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            .chartYAxisLabel("Savings Rate %")
            .frame(height: 180)

            Text("Dashed line = 20% savings target")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Analysis Yet",
            systemImage: "chart.bar.doc.horizontal",
            description: Text("Click \"Generate Report\" to create an AI-powered financial analysis.")
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

                report = try await generator.generateMonthlyReport(year: year, month: month)
                progressTask.cancel()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
