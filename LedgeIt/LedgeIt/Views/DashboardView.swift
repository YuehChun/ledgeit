import SwiftUI
import Charts
import GRDB

struct DashboardView: View {
    @State private var summary: PersonalFinanceService.SpendingSummary?
    @State private var trends: [PersonalFinanceService.MonthlyTrend] = []
    @State private var recentTransactions: [Transaction] = []
    @State private var recurringPayments: [PersonalFinanceService.RecurringPayment] = []
    @State private var spendingVelocity: PersonalFinanceService.SpendingVelocity?
    @State private var spendingAnalysis: LLMProcessor.SpendingAnalysis?
    @State private var isAnalyzing = false
    @State private var analysisError: String?
    @State private var errorMessage: String?
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var primaryCurrency: String = ""

    var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCards(summary)

                    if let velocity = spendingVelocity, velocity.isAlert {
                        velocityAlertBanner(velocity)
                    }

                    // Charts row
                    HStack(alignment: .top, spacing: 12) {
                        if !summary.categoryBreakdown.isEmpty {
                            categoryChart(summary.categoryBreakdown)
                        }
                        if !trends.isEmpty {
                            trendChart
                        }
                    }

                    aiInsightsCard

                    // Lists row
                    HStack(alignment: .top, spacing: 12) {
                        if !recurringPayments.isEmpty {
                            recurringPaymentsSection
                        }
                        if !summary.topMerchants.isEmpty {
                            topMerchantsSection(summary.topMerchants)
                        }
                    }

                    if !recentTransactions.isEmpty {
                        recentTransactionsSection
                    }
                }
                .padding(20)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Error Loading Data",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.top, 60)
            } else {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "chart.pie",
                    description: Text("Connect your Google account and sync emails to see financial insights.")
                )
                .padding(.top, 60)
            }
        }
        .navigationTitle("Dashboard")
        .onAppear { startObservation() }
        .onDisappear { cancellable?.cancel() }
    }

    private func startObservation() {
        let observation = ValueObservation.tracking { db -> Int in
            try Transaction.fetchCount(db)
        }

        cancellable = observation.start(
            in: AppDatabase.shared.db,
            scheduling: .immediate
        ) { error in
            errorMessage = error.localizedDescription
        } onChange: { _ in
            loadData()
        }
    }

    private func loadData() {
        let service = PersonalFinanceService(database: AppDatabase.shared)
        let calendar = Calendar.current
        let now = Date()
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        do {
            summary = try service.getMonthlySummary(year: year, month: month)
            trends = try service.getMonthlyTrends(months: 6)
            recentTransactions = try service.getRecentTransactions(limit: 10)
            recurringPayments = try service.detectRecurringPayments()
            spendingVelocity = try service.getSpendingVelocity()

            if let topCurrency = recentTransactions.first?.currency {
                primaryCurrency = topCurrency
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Overview Cards

    private func overviewCards(_ summary: PersonalFinanceService.SpendingSummary) -> some View {
        HStack(spacing: 10) {
            StatCard(title: "Spending", value: fmt(summary.totalSpending), subtitle: primaryCurrency, icon: "arrow.down.circle.fill", color: .red)
            StatCard(title: "Income", value: fmt(summary.totalIncome), subtitle: primaryCurrency, icon: "arrow.up.circle.fill", color: .green)
            StatCard(title: "Transactions", value: "\(summary.transactionCount)", subtitle: "this month", icon: "list.bullet.rectangle.fill", color: .blue)
            StatCard(title: "Net", value: fmt(summary.totalIncome - summary.totalSpending), subtitle: primaryCurrency, icon: "equal.circle.fill", color: summary.totalIncome >= summary.totalSpending ? .green : .orange)
        }
    }

    // MARK: - Velocity Alert

    private func velocityAlertBanner(_ velocity: PersonalFinanceService.SpendingVelocity) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spending Alert")
                    .font(.callout).fontWeight(.semibold)
                Text("This week: \(fmt(velocity.currentWeekSpending)) \(primaryCurrency) (\(String(format: "+%.0f%%", velocity.percentageOverAverage)) vs \(fmt(velocity.weeklyAverage)) avg)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Category Chart

    private func categoryChart(_ categories: [PersonalFinanceService.CategoryAmount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spending by Category").font(.headline)

            Chart(categories) { item in
                SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.5), angularInset: 1.5)
                    .foregroundStyle(by: .value("Category", CategoryStyle.style(forRawCategory: item.category).displayName))
            }
            .chartForegroundStyleScale(
                domain: categories.map { CategoryStyle.style(forRawCategory: $0.category).displayName },
                range: categories.map { CategoryStyle.style(forRawCategory: $0.category).color }
            )
            .chartLegend(.hidden)
            .frame(height: 180)

            VStack(spacing: 4) {
                ForEach(categories.prefix(5)) { item in
                    HStack(spacing: 6) {
                        CategoryDot(category: item.category, size: 8)
                        Text(CategoryStyle.style(forRawCategory: item.category).displayName).font(.caption).lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", item.percentage)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Text(fmt(item.amount)).font(.caption).monospacedDigit().fontWeight(.medium)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Monthly Trends").font(.headline)
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(.red.opacity(0.7)).frame(width: 7, height: 7)
                        Text("Spending").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(.green.opacity(0.7)).frame(width: 7, height: 7)
                        Text("Income").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                ForEach(trends) { trend in
                    BarMark(x: .value("Month", trend.month), y: .value("Amount", trend.spending))
                        .foregroundStyle(.red.opacity(0.7))
                    BarMark(x: .value("Month", trend.month), y: .value("Amount", trend.income))
                        .foregroundStyle(.green.opacity(0.7))
                }
            }
            .frame(height: 180)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let str = value.as(String.self) {
                            Text(abbreviateMonth(str)).font(.caption2)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - AI Insights

    private var aiInsightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("AI Insights", systemImage: "brain").font(.headline)
                Spacer()
                if isAnalyzing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing...").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button { loadAIInsights() } label: {
                        Label("Analyze", systemImage: "sparkles").font(.callout)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }

            if let analysis = spendingAnalysis {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    Text(analysis.topInsight).font(.callout).fontWeight(.medium)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(analysis.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 20) {
                    if !analysis.anomalies.isEmpty || !analysis.budgetRecommendations.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(analysis.anomalies, id: \.self) { insightRow(icon: "exclamationmark.triangle.fill", color: .orange, text: $0) }
                            ForEach(analysis.budgetRecommendations, id: \.self) { insightRow(icon: "checkmark.circle.fill", color: .green, text: $0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !analysis.patterns.subscriptions.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Detected Subscriptions").font(.caption).foregroundStyle(.secondary).fontWeight(.medium)
                            ForEach(analysis.patterns.subscriptions, id: \.self) { insightRow(icon: "repeat", color: .blue, text: $0) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let analysisError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                    Text(analysisError).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Click \"Analyze\" to generate AI spending insights.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func insightRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadAIInsights() {
        guard let summary, !isAnalyzing else { return }
        isAnalyzing = true
        analysisError = nil
        Task {
            defer { isAnalyzing = false }
            do {
                let openRouter = try OpenRouterService()
                let processor = LLMProcessor(openRouter: openRouter)
                let summaryText = """
                    Total spending: \(String(format: "%.2f", summary.totalSpending)) \(primaryCurrency)
                    Total income: \(String(format: "%.2f", summary.totalIncome)) \(primaryCurrency)
                    Categories: \(summary.categoryBreakdown.map { "\($0.category): \(String(format: "%.2f", $0.amount)) (\(String(format: "%.1f", $0.percentage))%)" }.joined(separator: ", "))
                    Top merchants: \(summary.topMerchants.map { "\($0.merchant): \(String(format: "%.2f", $0.amount)) (\($0.count)x)" }.joined(separator: ", "))
                    """
                let trendsText = trends.map { "\($0.month): spending=\(String(format: "%.2f", $0.spending)), income=\(String(format: "%.2f", $0.income))" }.joined(separator: "\n")
                let txnText = recentTransactions.prefix(15).map { tx in
                    "\(tx.transactionDate ?? "?") | \(tx.merchant ?? "?") | \(String(format: "%.2f", tx.amount)) \(tx.currency) | \(tx.category ?? "?")"
                }.joined(separator: "\n")
                spendingAnalysis = try await processor.analyzeSpending(summary: summaryText, trends: trendsText, recentTransactions: txnText)
            } catch {
                analysisError = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Recurring Payments

    private var recurringPaymentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recurring Payments").font(.headline)
            ForEach(recurringPayments) { payment in
                HStack(spacing: 8) {
                    if let cat = payment.category {
                        CategoryIcon(category: cat, size: 24)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(payment.merchant).font(.callout).lineLimit(1)
                            if let cat = payment.category,
                               CategoryStyle.style(forRawCategory: cat).isFinancialObligation {
                                Text("BILL")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .foregroundStyle(.white)
                                    .background(CategoryStyle.style(forRawCategory: cat).color, in: Capsule())
                            }
                        }
                        Text("\(payment.distinctMonths) months, \(payment.frequency) charges").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("~\(fmt(payment.averageAmount)) \(payment.currency)").font(.callout).monospacedDigit().fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Top Merchants

    private func topMerchantsSection(_ merchants: [PersonalFinanceService.MerchantAmount]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Merchants").font(.headline)
            ForEach(merchants.prefix(8)) { merchant in
                HStack {
                    Text(merchant.merchant).font(.callout).lineLimit(1)
                    Spacer()
                    Text("\(merchant.count)x").font(.caption).foregroundStyle(.secondary)
                    Text(fmt(merchant.amount)).font(.callout).monospacedDigit().fontWeight(.medium)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions").font(.headline)
            ForEach(recentTransactions) { tx in
                HStack(spacing: 8) {
                    if let category = tx.category {
                        CategoryIcon(category: category, size: 22)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.merchant ?? "Unknown").font(.callout).lineLimit(1)
                        if let date = tx.transactionDate { Text(date).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let category = tx.category { CategoryBadge(category: category) }
                    AmountText(amount: tx.amount, currency: tx.currency, type: tx.type)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func fmt(_ value: Double) -> String { String(format: "%.0f", value) }

    private func abbreviateMonth(_ str: String) -> String {
        let parts = str.split(separator: "-")
        guard parts.count >= 2, let m = Int(parts[1]) else { return str }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return m >= 1 && m <= 12 ? months[m - 1] : str
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String = ""
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title2).fontWeight(.bold).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !subtitle.isEmpty { Text(subtitle).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
