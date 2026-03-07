import SwiftUI
import GRDB

struct SettingsView: View {
    @State private var authService = GoogleAuthService()
    @State private var openRouterKey: String = ""
    @State private var googleClientID: String = ""
    @State private var googleClientSecret: String = ""
    @State private var authError: String?
    @State private var syncState: SyncState?
    @State private var isConnecting: Bool = false
    @State private var isSyncing: Bool = false
    @State private var statusMessage: String?
    @State private var creditInfo: OpenRouterCreditsService.CreditInfo?
    @State private var creditError: Bool = false
    @State private var isFetchingCredits: Bool = false
    @State private var creditLastUpdated: Date?
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    var onKeySaved: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.settings)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(l10n.settingsSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Two-column layout: credentials left, status right
                HStack(alignment: .top, spacing: 16) {
                    // Left column: API credentials
                    VStack(spacing: 16) {
                        SettingsSection(title: l10n.language, icon: "globe", color: .orange) {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker(l10n.language, selection: $appLanguage) {
                                    ForEach(AppLanguage.allCases) { lang in
                                        Text(lang.displayName).tag(lang.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text(l10n.languageDescription)
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }

                        SettingsSection(title: l10n.googleCloudPlatform, icon: "cloud.fill", color: .blue) {
                            VStack(alignment: .leading, spacing: 10) {
                                FieldGroup(label: l10n.clientID) {
                                    TextField("your-client-id.apps.googleusercontent.com", text: $googleClientID)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                FieldGroup(label: l10n.clientSecret) {
                                    SecureField("GOCSPX-...", text: $googleClientSecret)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text(l10n.googleCloudHint)
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }

                        SettingsSection(title: l10n.openRouterAI, icon: "brain.fill", color: .purple) {
                            VStack(alignment: .leading, spacing: 10) {
                                FieldGroup(label: l10n.apiKey) {
                                    SecureField("sk-or-...", text: $openRouterKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text(l10n.openRouterHint)
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }

                        // OpenRouter Credit Usage card
                        if isFetchingCredits {
                            SettingsSection(title: "OpenRouter", icon: "dollarsign.circle.fill", color: .green) {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text(l10n.openRouterFetchingCredits)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if let info = creditInfo {
                            OpenRouterCreditCard(
                                info: info,
                                l10n: l10n,
                                lastUpdated: creditLastUpdated,
                                onRefresh: { fetchOpenRouterCredits() }
                            )
                        } else if creditError {
                            SettingsSection(title: "OpenRouter", icon: "dollarsign.circle.fill", color: .green) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.orange)
                                    Text(l10n.openRouterCreditsError)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(l10n.openRouterRefresh) { fetchOpenRouterCredits() }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }


                    }
                    .frame(maxWidth: .infinity)

                    // Right column: status + actions
                    VStack(spacing: 16) {
                        SettingsSection(title: l10n.connectionStatus, icon: "checkmark.circle.fill", color: .green) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: authService.isSignedIn ? "checkmark.seal.fill" : "xmark.circle")
                                        .font(.title3)
                                        .foregroundStyle(authService.isSignedIn ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(authService.isSignedIn ? l10n.googleConnected : l10n.notConnected)
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        Text(authService.isSignedIn
                                             ? l10n.accountLinked
                                             : l10n.saveAndConnect)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                SyncStatRow(label: l10n.lastSync, value: syncState?.lastSyncDate ?? "Never")
                                SyncStatRow(label: l10n.emailsSynced, value: "\(syncState?.totalEmailsSynced ?? 0)")
                                SyncStatRow(label: l10n.emailsProcessed, value: "\(syncState?.totalEmailsProcessed ?? 0)")
                            }
                        }

                        // Status / error messages
                        if let statusMessage {
                            HStack(spacing: 6) {
                                if isConnecting || isSyncing {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.background.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        if let authError {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(authError)
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.red.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Action buttons
                        VStack(spacing: 8) {
                            if authService.isSignedIn {
                                Button {
                                    performSync()
                                } label: {
                                    Label(l10n.syncAndProcess, systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isSyncing)

                                HStack(spacing: 8) {
                                    Button {
                                        processOnly()
                                    } label: {
                                        Label(l10n.processOnly, systemImage: "brain")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .controlSize(.regular)
                                    .disabled(isSyncing)

                                    Button {
                                        syncToCalendar()
                                    } label: {
                                        Label(l10n.calendarSync, systemImage: "calendar.badge.plus")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .controlSize(.regular)
                                    .disabled(isSyncing)
                                }

                                Button(role: .destructive) {
                                    authService.signOut()
                                    statusMessage = nil
                                    authError = nil
                                } label: {
                                    Label(l10n.disconnect, systemImage: "xmark.circle")
                                }
                                .font(.caption)
                            } else {
                                Button {
                                    saveConnectAndSync()
                                } label: {
                                    Label(l10n.saveAndConnectGoogle, systemImage: "arrow.right.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(googleClientID.isEmpty || googleClientSecret.isEmpty || isConnecting)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                // Permissions info
                SettingsSection(title: l10n.permissionsRequested, icon: "lock.shield.fill", color: .blue) {
                    HStack(spacing: 20) {
                        PermissionRow(icon: "envelope.fill", text: l10n.gmailPermission)
                        PermissionRow(icon: "calendar", text: l10n.calendarPermission)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 600, minHeight: 420)
        .onAppear(perform: loadSettings)
    }

    // MARK: - Save, Connect & Sync

    private func saveConnectAndSync() {
        Task {
            isConnecting = true
            authError = nil

            statusMessage = "Saving credentials..."
            do {
                if !openRouterKey.isEmpty {
                    try KeychainService.save(key: .openRouterAPIKey, value: openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if !googleClientID.isEmpty {
                    try KeychainService.save(key: .googleClientID, value: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if !googleClientSecret.isEmpty {
                    try KeychainService.save(key: .googleClientSecret, value: googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                onKeySaved?()
            } catch {
                authError = "Failed to save credentials: \(error.localizedDescription)"
                statusMessage = nil
                isConnecting = false
                return
            }

            statusMessage = "Connecting Google account..."
            do {
                try await authService.signIn()
            } catch {
                authError = error.localizedDescription
                statusMessage = nil
                isConnecting = false
                return
            }

            isConnecting = false
            statusMessage = "Connected! Starting sync..."
            performSync()
        }
    }

    private func performSync() {
        Task {
            isSyncing = true
            authError = nil

            do {
                let database = AppDatabase.shared
                let syncService = SyncService(database: database)
                syncService.configure { [authService] in
                    try await authService.getValidAccessToken()
                }

                let state = try syncService.getSyncState()
                if state.totalEmailsSynced > 0 {
                    statusMessage = "Fetching new emails..."
                    try await syncService.performIncrementalSync()
                } else {
                    statusMessage = "Syncing emails (last 30 days)..."
                    try await syncService.performInitialSync()
                }
                loadSyncState()

                try await runProcessing(database: database)
            } catch {
                authError = "Failed: \(error.localizedDescription)"
                statusMessage = nil
            }

            isSyncing = false
        }
    }

    private func processOnly() {
        Task {
            isSyncing = true
            authError = nil

            do {
                try await runProcessing(database: AppDatabase.shared)
            } catch {
                authError = "Failed: \(error.localizedDescription)"
                statusMessage = nil
            }

            isSyncing = false
        }
    }

    private func runProcessing(database: AppDatabase) async throws {
        let unprocessedCount = try await database.db.read { db in
            try Email.filter(Email.Columns.isProcessed == false).fetchCount(db)
        }

        guard unprocessedCount > 0 else {
            statusMessage = "All emails already processed."
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { statusMessage = nil }
            return
        }

        statusMessage = "Classifying \(unprocessedCount) emails..."

        let providerConfig = AIProviderConfigStore.load()
        let llmProcessor = LLMProcessor(providerConfig: providerConfig)
        let pipeline = ExtractionPipeline(database: database, llmProcessor: llmProcessor)
        try await pipeline.processUnprocessedEmails()
        loadSyncState()

        let txnCount = try await database.db.read { db in
            try Transaction.fetchCount(db)
        }

        statusMessage = "Done! \(pipeline.processedCount) emails processed, \(txnCount) transactions found."

        // Auto-sync to calendar
        do {
            let calendarService = CalendarService { [authService] in
                try await authService.getValidAccessToken()
            }
            statusMessage = "Syncing transactions to calendar..."
            let synced = try await pipeline.syncTransactionsToCalendar(calendarService: calendarService)
            if synced > 0 {
                statusMessage = "Done! \(pipeline.processedCount) emails, \(txnCount) transactions, \(synced) calendar events."
            }
        } catch {
            // Calendar sync is best-effort
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { statusMessage = nil }
    }

    private func syncToCalendar() {
        Task {
            isSyncing = true
            authError = nil
            statusMessage = "Syncing transactions to calendar..."

            do {
                let database = AppDatabase.shared
                let providerConfig = AIProviderConfigStore.load()
                let llmProcessor = LLMProcessor(providerConfig: providerConfig)
                let pipeline = ExtractionPipeline(database: database, llmProcessor: llmProcessor)
                let calendarService = CalendarService { [authService] in
                    try await authService.getValidAccessToken()
                }

                let synced = try await pipeline.syncTransactionsToCalendar(calendarService: calendarService)
                statusMessage = synced > 0 ? "\(synced) events synced to calendar." : "All transactions already synced."
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { statusMessage = nil }
            } catch {
                authError = "Calendar sync failed: \(error.localizedDescription)"
                statusMessage = nil
            }

            isSyncing = false
        }
    }

    // MARK: - Data

    private func loadSettings() {
        openRouterKey = KeychainService.load(key: .openRouterAPIKey) ?? ""
        googleClientID = KeychainService.load(key: .googleClientID) ?? ""
        googleClientSecret = KeychainService.load(key: .googleClientSecret) ?? ""
        loadSyncState()
        fetchOpenRouterCredits()
    }

    private func fetchOpenRouterCredits() {
        // Resolve the OpenRouter API key: try the new per-endpoint keychain first,
        // then fall back to the legacy keychain key.
        let config = AIProviderConfigStore.load()
        let openRouterEndpointId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let key: String? = KeychainService.loadEndpointAPIKey(endpointId: openRouterEndpointId)
            ?? KeychainService.load(key: .openRouterAPIKey)
        guard let apiKey = key, !apiKey.isEmpty else { return }
        // Only show credits when an OpenRouter endpoint is actually configured
        let hasOpenRouter = config.endpoints.contains(where: { $0.id == openRouterEndpointId })
        guard hasOpenRouter else { return }

        isFetchingCredits = true
        creditError = false
        Task {
            do {
                let info = try await OpenRouterCreditsService.fetchCredits(apiKey: apiKey)
                creditInfo = info
                creditLastUpdated = Date()
            } catch {
                creditError = true
            }
            isFetchingCredits = false
        }
    }

    private func loadSyncState() {
        do {
            syncState = try AppDatabase.shared.db.read { db in
                try SyncState.fetchOne(db)
            }
        } catch {
            print("Failed to load sync state: \(error)")
        }
    }
}

// MARK: - Reusable Components

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct FieldGroup<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            content
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.caption)
        }
    }
}

private struct SyncStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)
    }
}

private struct OpenRouterCreditCard: View {
    let info: OpenRouterCreditsService.CreditInfo
    let l10n: L10n
    let lastUpdated: Date?
    let onRefresh: () -> Void

    private var usagePercent: Double {
        guard info.totalCredits > 0 else { return 0 }
        return min(info.usage / info.totalCredits, 1.0)
    }

    private var barColor: Color {
        if usagePercent > 0.9 { return .red }
        if usagePercent > 0.7 { return .orange }
        return .green
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm:ss a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row: title + last updated + refresh
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenRouter")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let date = lastUpdated {
                        Text("\(l10n.openRouterLastUpdated): \(Self.timeFormatter.string(from: date))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button(l10n.openRouterRefresh) { onRefresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            // Three stat cards in a row
            HStack(spacing: 10) {
                CreditStatCard(
                    label: l10n.openRouterTotalCredits,
                    value: formatUSD(info.totalCredits),
                    color: .green
                )
                CreditStatCard(
                    label: l10n.openRouterUsed,
                    value: formatUSD(info.usage),
                    color: .red
                )
                CreditStatCard(
                    label: l10n.openRouterRemaining,
                    value: formatUSD(info.remaining),
                    color: .mint
                )
            }

            // Credit Usage progress bar
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.openRouterCreditUsage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(barColor.gradient)
                            .frame(width: max(0, geo.size.width * usagePercent))
                    }
                }
                .frame(height: 10)

                Text(l10n.openRouterUsedPercent(String(format: "%.1f%%", usagePercent * 100)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(12)
            .background(.background.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatUSD(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

private struct CreditStatCard: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.tertiary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

