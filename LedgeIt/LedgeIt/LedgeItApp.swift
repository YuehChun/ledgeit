import SwiftUI

@main
struct LedgeItApp: App {
    @State private var database = AppDatabase.shared

    init() {
        // Single Keychain read at startup to avoid multiple macOS password prompts
        KeychainService.preload()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(database)
                .task {
                    let embeddingService = EmbeddingService()
                    do {
                        try await embeddingService.indexUnembeddedTransactions { current, total in
                            print("[EmbeddingService] Indexing \(current)/\(total) transactions...")
                        }
                    } catch {
                        print("[EmbeddingService] Batch indexing failed: \(error)")
                    }
                }
        }
        Settings {
            SettingsView()
                .environment(database)
        }
    }
}
