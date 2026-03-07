import SwiftUI
import Charts
import GRDB

struct DashboardView: View {
    @State private var summary: PersonalFinanceService.SpendingSummary?
    @State private var trends: [PersonalFinanceService.MonthlyTrend] = []
    @State private var recentTransactions: [Transaction] = []
    @State private var recurringPayments: [PersonalFinanceService.RecurringPayment] = []
    @State private var spendingVelocity: PersonalFinanceService.SpendingVelocity?
    @State private var upcomingBills: [CreditCardBill] = []
    @State private var spendingAnalysis: LLMProcessor.SpendingAnalysis?
    @State private var isAnalyzing = false
    @State private var analysisStep = 0
    @State private var analysisError: String?
    @State private var errorMessage: String?
    @State private var cancellable: AnyDatabaseCancellable?
    @State private var primaryCurrency: String = ""
    @State private var budgetSummary: PersonalFinanceService.BudgetSummary?
    @AppStorage("advisorPersonaId") private var personaId = "moderate"
    @AppStorage("customSavingsTarget") private var customSavingsTarget = 0.20
    @AppStorage("customRiskLevel") private var customRiskLevel = "medium"
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    var body: some View {
        ScrollView {
            if let summary {
                VStack(alignment: .leading, spacing: 16) {
                    overviewCards(summary)

                    spendingBudgetCard

                    if let velocity = spendingVelocity, velocity.isAlert {
                        velocityAlertBanner(velocity)
                    }

                    // Upcoming bills
                    if !upcomingBills.isEmpty {
                        upcomingBillsSection
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
            upcomingBills = try service.getUpcomingBills()

            let persona = AdvisorPersona.resolveWithVersions(
                id: personaId,
                customSavingsTarget: customSavingsTarget,
                customRiskLevel: customRiskLevel
            )
            budgetSummary = try service.getBudgetSummary(year: year, month: month, savingsTarget: persona.savingsTarget)

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

    // MARK: - Spending Budget

    @ViewBuilder
    private var spendingBudgetCard: some View {
        if let budget = budgetSummary {
            VStack(spacing: 14) {
                HStack {
                    Image(systemName: "wallet.bifold.fill")
                        .foregroundStyle(.blue)
                    Text(l10n.spendingBudget)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(budget.savingsTarget * 100))% \(l10n.savingsRate)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.1), in: Capsule())
                }

                HStack(spacing: 20) {
                    // Left: Disposable Balance
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.disposableBalance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(budget.currency) \(String(format: "%.0f", budget.disposableBalance))")
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(budget.disposableBalance >= 0 ? Color.primary : Color.red)
                        if budget.disposableBalance < 0 {
                            Text(l10n.overBudgetBy("\(budget.currency) \(String(format: "%.0f", abs(budget.disposableBalance)))"))
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else {
                            Text("\(l10n.ofBudget): \(budget.currency) \(String(format: "%.0f", budget.spendingBudget))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 50)

                    // Right: Daily Allowance
                    VStack(alignment: .leading, spacing: 6) {
                        Text(l10n.dailyAllowance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(budget.currency) \(String(format: "%.0f", budget.dailyAllowance))")
                            .font(.title)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(budgetHealthColor(budget))
                        Text(l10n.perDayForDays(budget.daysRemaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Budget usage progress bar
                VStack(spacing: 4) {
                    HStack {
                        Text(l10n.budgetUsed)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(String(format: "%.0f", budget.spentSoFar)) / \(String(format: "%.0f", budget.spendingBudget))")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        let usedRatio = budget.spendingBudget > 0
                            ? budget.spentSoFar / budget.spendingBudget : 0
                        let clampedRatio = min(max(usedRatio, 0), 1.0)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.quaternary)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(budgetBarColor(usedRatio))
                                .frame(width: geo.size.width * clampedRatio, height: 6)
                        }
                    }
                    .frame(height: 6)
                }

                // Month progress
                VStack(spacing: 4) {
                    HStack {
                        Text(l10n.monthProgress)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        let dayOfMonth = budget.daysInMonth - budget.daysRemaining + 1
                        Text("\(dayOfMonth) / \(budget.daysInMonth)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    GeometryReader { geo in
                        let dayOfMonth = budget.daysInMonth - budget.daysRemaining + 1
                        let ratio = Double(dayOfMonth) / Double(budget.daysInMonth)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.quaternary)
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.secondary.opacity(0.5))
                                .frame(width: geo.size.width * ratio, height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }
            .padding(14)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "wallet.bifold")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.spendingBudget)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(l10n.waitingForIncomeDesc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func budgetHealthColor(_ budget: PersonalFinanceService.BudgetSummary) -> Color {
        guard budget.spendingBudget > 0 else { return .red }
        let remainingRatio = budget.disposableBalance / budget.spendingBudget
        let timeRatio = Double(budget.daysRemaining) / Double(budget.daysInMonth)
        if remainingRatio >= timeRatio * 0.8 { return .green }
        if remainingRatio >= timeRatio * 0.4 { return .orange }
        return .red
    }

    private func budgetBarColor(_ usedRatio: Double) -> Color {
        if usedRatio <= 0.6 { return .green }
        if usedRatio <= 0.85 { return .orange }
        return .red
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
                    AIProgressView(
                        title: "AI Analysis",
                        steps: ["Loading transactions", "Analyzing patterns", "Generating insights"],
                        currentStep: analysisStep
                    )
                    .frame(width: 240)
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
        analysisStep = 0
        Task {
            defer { isAnalyzing = false; analysisStep = 0 }
            do {
                analysisStep = 0 // Loading transactions
                let providerConfig = AIProviderConfigStore.load()
                let processor = LLMProcessor(providerConfig: providerConfig)
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
                analysisStep = 1 // Analyzing patterns
                spendingAnalysis = try await processor.analyzeSpending(summary: summaryText, trends: trendsText, recentTransactions: txnText)
                analysisStep = 2 // Generating insights
            } catch {
                analysisError = "Analysis failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Upcoming Bills

    private var upcomingBillsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .foregroundStyle(.orange)
                Text("Upcoming Bills")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(upcomingBills) { bill in
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(Color(red: 0.78, green: 0.18, blue: 0.18))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.bankName)
                                .font(.system(size: 13, weight: .medium))
                            Text("Due \(formatDueDate(bill.dueDate))")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if bill.isPaid {
                            Text("PAID")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green, in: Capsule())
                        } else if let days = daysUntilDue(bill.dueDate) {
                            if days < 0 {
                                Text("OVERDUE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.red, in: Capsule())
                            } else {
                                Text("\(days)d")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(days <= 3 ? .red : days <= 7 ? .orange : .secondary)
                            }
                        }

                        Text("\(bill.currency) \(String(format: "%.0f", bill.amountDue))")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))

                        if !bill.isPaid {
                            Button {
                                if let id = bill.id {
                                    let service = PersonalFinanceService(database: AppDatabase.shared)
                                    try? service.markBillAsPaid(id)
                                    loadData()
                                }
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        !bill.isPaid && (daysUntilDue(bill.dueDate).map { $0 < 0 } ?? false)
                            ? Color.red.opacity(0.08) : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(14)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatDueDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateFormat = "MMM d"
        return display.string(from: date)
    }

    private func daysUntilDue(_ dateStr: String) -> Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let dueDate = formatter.date(from: dateStr) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: dueDate)
        return cal.dateComponents([.day], from: today, to: due).day
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
