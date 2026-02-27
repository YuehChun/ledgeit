import SwiftUI
import GRDB

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case transactions = "Transactions"
    case emails = "Emails"
    case calendar = "Calendar"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.pie.fill"
        case .transactions: return "creditcard.fill"
        case .emails: return "envelope.fill"
        case .calendar: return "calendar"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @State private var selectedItem: SidebarItem? = .dashboard
    @State private var hasApiKeys = false
    @State private var autoSyncStatus: String?
    @State private var syncTimer: Timer?

    private let autoSyncInterval: TimeInterval = 15 * 60 // 15 minutes

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
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

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wallet.bifold.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("Welcome to LedgeIt")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Personal finance tracking powered by AI")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "envelope.open.fill", color: .blue,
                           title: "Gmail Integration",
                           subtitle: "Automatically scan financial emails")
                FeatureRow(icon: "brain.head.profile.fill", color: .purple,
                           title: "AI-Powered Extraction",
                           subtitle: "Extract transactions with Claude AI")
                FeatureRow(icon: "chart.pie.fill", color: .orange,
                           title: "Financial Dashboard",
                           subtitle: "Visualize spending patterns and trends")
                FeatureRow(icon: "calendar.badge.clock", color: .green,
                           title: "Payment Calendar",
                           subtitle: "Track upcoming bills and payments")
            }
            .frame(maxWidth: 380)

            Button(action: onGoToSettings) {
                Label("Get Started", systemImage: "arrow.right.circle.fill")
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
