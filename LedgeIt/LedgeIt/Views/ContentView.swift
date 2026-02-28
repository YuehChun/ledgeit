import SwiftUI
import GRDB

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transactions = "Transactions"
    case emails = "Emails"
    case calendar = "Calendar"
    case analysis = "Analysis"
    case advisor = "Advisor"
    case goals = "Goals"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .transactions: return "creditcard.fill"
        case .emails: return "envelope.fill"
        case .calendar: return "calendar"
        case .analysis: return "chart.bar.doc.horizontal.fill"
        case .advisor: return "brain.head.profile.fill"
        case .goals: return "target"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .dashboard
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }
    @State private var hasApiKeys = false
    @State private var autoSyncStatus: String?
    @State private var syncTimer: Timer?

    private let autoSyncInterval: TimeInterval = 15 * 60 // 15 minutes

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section(l10n.overview) {
                    Label(l10n.dashboard, systemImage: SidebarItem.dashboard.icon)
                        .tag(SidebarItem.dashboard)
                }
                Section(l10n.data) {
                    Label(l10n.transactions, systemImage: SidebarItem.transactions.icon)
                        .tag(SidebarItem.transactions)
                    Label(l10n.emails, systemImage: SidebarItem.emails.icon)
                        .tag(SidebarItem.emails)
                    Label(l10n.calendar, systemImage: SidebarItem.calendar.icon)
                        .tag(SidebarItem.calendar)
                }
                Section(l10n.analysisSection) {
                    Label(l10n.analysis, systemImage: SidebarItem.analysis.icon)
                        .tag(SidebarItem.analysis)
                    Label(l10n.aiAdvisorSidebar, systemImage: SidebarItem.advisor.icon)
                        .tag(SidebarItem.advisor)
                    Label(l10n.goals, systemImage: SidebarItem.goals.icon)
                        .tag(SidebarItem.goals)
                }
                Section {
                    Label(l10n.settings, systemImage: SidebarItem.settings.icon)
                        .tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)

            if let status = autoSyncStatus {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        } detail: {
            Group {
                if !hasApiKeys && selectedItem != .settings {
                    OnboardingView(onGoToSettings: { selectedItem = .settings })
                } else {
                    switch selectedItem {
                    case .dashboard:
                        DashboardView()
                    case .transactions:
                        TransactionListView()
                    case .emails:
                        EmailListView()
                    case .calendar:
                        CalendarView()
                    case .analysis:
                        AnalysisDashboardView()
                    case .advisor:
                        AdvisorSettingsView()
                    case .goals:
                        GoalsView()
                    case .settings:
                        SettingsView(onKeySaved: {
                            checkApiKeys()
                            triggerAutoSync()
                        })
                    case nil:
                        Text("Select an item from the sidebar")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            checkApiKeys()
            triggerAutoSync()
            startSyncTimer()
        }
        .onDisappear {
            syncTimer?.invalidate()
        }
    }

    private func checkApiKeys() {
        let clientId = KeychainService.load(key: .googleClientID) ?? ""
        let clientSecret = KeychainService.load(key: .googleClientSecret) ?? ""
        hasApiKeys = !clientId.isEmpty && !clientSecret.isEmpty
    }

    private func startSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: autoSyncInterval, repeats: true) { _ in
            Task { @MainActor in
                triggerAutoSync()
            }
        }
    }

    private func triggerAutoSync() {
        let authService = GoogleAuthService()
        guard authService.isSignedIn else { return }

        Task {
            await performAutoSync(authService: authService)
        }
    }

    private func performAutoSync(authService: GoogleAuthService) async {
        let database = AppDatabase.shared

        // 1. Incremental sync
        do {
            autoSyncStatus = "Syncing emails..."
            let syncService = SyncService(database: database)
            syncService.configure {
                try await authService.getValidAccessToken()
            }
            try await syncService.performIncrementalSync()
        } catch {
            autoSyncStatus = nil
            return
        }

        // 2. Process unprocessed emails
        do {
            let unprocessed = try await database.db.read { db in
                try Email.filter(Email.Columns.isProcessed == false).fetchCount(db)
            }
            guard unprocessed > 0 else {
                autoSyncStatus = nil
                return
            }

            autoSyncStatus = "Processing \(unprocessed) emails..."
            let openRouter = try OpenRouterService()
            let llm = LLMProcessor(openRouter: openRouter)
            let pipeline = ExtractionPipeline(database: database, llmProcessor: llm)
            try await pipeline.processUnprocessedEmails()
        } catch {
            // Processing errors are non-fatal
        }

        autoSyncStatus = nil
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    var onGoToSettings: () -> Void
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text(l10n.welcomeTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(l10n.welcomeSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "envelope.open.fill", color: .blue,
                           title: l10n.gmailIntegration,
                           subtitle: l10n.gmailIntegrationDesc)
                FeatureRow(icon: "brain.head.profile.fill", color: .purple,
                           title: l10n.aiExtraction,
                           subtitle: l10n.aiExtractionDesc)
                FeatureRow(icon: "chart.pie.fill", color: .orange,
                           title: l10n.financialDashboard,
                           subtitle: l10n.financialDashboardDesc)
                FeatureRow(icon: "calendar.badge.clock", color: .green,
                           title: l10n.paymentCalendar,
                           subtitle: l10n.paymentCalendarDesc)
            }
            .frame(maxWidth: 380)

            Button(action: onGoToSettings) {
                Label(l10n.getStarted, systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
