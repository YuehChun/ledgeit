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

    var onKeySaved: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Configure credentials, connect your Google account, and sync emails.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Two-column layout: credentials left, status right
                HStack(alignment: .top, spacing: 16) {
                    // Left column: API credentials
                    VStack(spacing: 16) {
                        SettingsSection(title: "Google Cloud Platform", icon: "cloud.fill", color: .blue) {
                            VStack(alignment: .leading, spacing: 10) {
                                FieldGroup(label: "Client ID") {
                                    TextField("your-client-id.apps.googleusercontent.com", text: $googleClientID)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                FieldGroup(label: "Client Secret") {
                                    SecureField("GOCSPX-...", text: $googleClientSecret)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text("Create a Desktop OAuth 2.0 client. Enable Gmail + Calendar APIs.")
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }

                        SettingsSection(title: "OpenRouter (AI)", icon: "brain.fill", color: .purple) {
                            VStack(alignment: .leading, spacing: 10) {
                                FieldGroup(label: "API Key") {
                                    SecureField("sk-or-...", text: $openRouterKey)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.callout)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text("Get your API key from openrouter.ai")
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right column: status + actions
                    VStack(spacing: 16) {
                        SettingsSection(title: "Connection Status", icon: "checkmark.circle.fill", color: .green) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: authService.isSignedIn ? "checkmark.seal.fill" : "xmark.circle")
                                        .font(.title3)
                                        .foregroundStyle(authService.isSignedIn ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(authService.isSignedIn ? "Google Connected" : "Not Connected")
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        Text(authService.isSignedIn
                                             ? "Account linked and ready."
                                             : "Save credentials and connect below.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Divider()

                                SyncStatRow(label: "Last Sync", value: syncState?.lastSyncDate ?? "Never")
                                SyncStatRow(label: "Emails Synced", value: "\(syncState?.totalEmailsSynced ?? 0)")
                                SyncStatRow(label: "Emails Processed", value: "\(syncState?.totalEmailsProcessed ?? 0)")
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
                                    Label("Sync & Process", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(isSyncing)

                                HStack(spacing: 8) {
                                    Button {
                                        processOnly()
                                    } label: {
                                        Label("Process Only", systemImage: "brain")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .controlSize(.regular)
                                    .disabled(isSyncing)

                                    Button {
                                        syncToCalendar()
                                    } label: {
                                        Label("Calendar Sync", systemImage: "calendar.badge.plus")
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
                                    Label("Disconnect", systemImage: "xmark.circle")
                                }
                                .font(.caption)
                            } else {
                                Button {
                                    saveConnectAndSync()
                                } label: {
                                    Label("Save & Connect Google", systemImage: "arrow.right.circle.fill")
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
                SettingsSection(title: "Permissions Requested", icon: "lock.shield.fill", color: .blue) {
                    HStack(spacing: 20) {
                        PermissionRow(icon: "envelope.fill", text: "Gmail — read-only access to your emails")
                        PermissionRow(icon: "calendar", text: "Google Calendar — create payment events")
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
                    try KeychainService.save(key: .openRouterAPIKey, value: openRouterKey)
                }
                if !googleClientID.isEmpty {
                    try KeychainService.save(key: .googleClientID, value: googleClientID)
                }
                if !googleClientSecret.isEmpty {
                    try KeychainService.save(key: .googleClientSecret, value: googleClientSecret)
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

        let openRouter = try OpenRouterService()
        let llmProcessor = LLMProcessor(openRouter: openRouter)
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
                let openRouter = try OpenRouterService()
                let llmProcessor = LLMProcessor(openRouter: openRouter)
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
