import SwiftUI
import GRDB

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case chat = "Chat"
    case transactions = "Transactions"
    case review = "Review"
    case emails = "Emails"
    case calendar = "Calendar"
    case statements = "Statements"
    case analysis = "Analysis"
    case advisor = "Advisor"
    case goals = "Goals"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .transactions: return "creditcard.fill"
        case .review: return "checkmark.circle.fill"
        case .emails: return "envelope.fill"
        case .calendar: return "calendar"
        case .statements: return "doc.text.fill"
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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var autoSyncStatus: String?
    @State private var syncTimer: Timer?

    private let autoSyncInterval: TimeInterval = 15 * 60 // 15 minutes

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section(l10n.overview) {
                    sidebarRow(l10n.dashboard, icon: SidebarItem.dashboard.icon)
                        .tag(SidebarItem.dashboard)
                    sidebarRow(l10n.chat, icon: SidebarItem.chat.icon)
                        .tag(SidebarItem.chat)
                }
                Section(l10n.data) {
                    sidebarRow(l10n.transactions, icon: SidebarItem.transactions.icon)
                        .tag(SidebarItem.transactions)
                    sidebarRow(l10n.review, icon: SidebarItem.review.icon)
                        .tag(SidebarItem.review)
                    sidebarRow(l10n.emails, icon: SidebarItem.emails.icon)
                        .tag(SidebarItem.emails)
                    sidebarRow(l10n.calendar, icon: SidebarItem.calendar.icon)
                        .tag(SidebarItem.calendar)
                    sidebarRow(l10n.statementsSidebar, icon: SidebarItem.statements.icon)
                        .tag(SidebarItem.statements)
                }
                Section(l10n.analysisSection) {
                    sidebarRow(l10n.analysis, icon: SidebarItem.analysis.icon)
                        .tag(SidebarItem.analysis)
                    sidebarRow(l10n.goals, icon: SidebarItem.goals.icon)
                        .tag(SidebarItem.goals)
                }
                Section {
                    sidebarRow(l10n.settings, icon: SidebarItem.settings.icon)
                        .tag(SidebarItem.settings)
                    sidebarRow(l10n.aiAdvisorSidebar, icon: SidebarItem.advisor.icon)
                        .tag(SidebarItem.advisor)
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
                if !hasCompletedOnboarding {
                    OnboardingChatView()
                } else {
                    switch selectedItem {
                    case .dashboard:
                        DashboardView()
                    case .chat:
                        ChatView()
                    case .transactions:
                        TransactionListView()
                    case .review:
                        TransactionReviewView()
                    case .emails:
                        EmailListView()
                    case .calendar:
                        CalendarView()
                    case .statements:
                        StatementsView()
                    case .analysis:
                        AnalysisDashboardView()
                    case .advisor:
                        AdvisorSettingsView()
                    case .goals:
                        GoalsView(onNavigateToAdvisor: { selectedItem = .advisor })
                    case .settings:
                        SettingsView(onKeySaved: {
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
            triggerAutoSync()
            startSyncTimer()
        }
        .onDisappear {
            syncTimer?.invalidate()
        }
    }

    private func sidebarRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(title)
        }
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
            let providerConfig = AIProviderConfigStore.load()
            let llm = LLMProcessor(providerConfig: providerConfig)
            let pipeline = ExtractionPipeline(database: database, llmProcessor: llm)
            try await pipeline.processUnprocessedEmails()
        } catch {
            // Processing errors are non-fatal
        }

        autoSyncStatus = nil
    }
}
