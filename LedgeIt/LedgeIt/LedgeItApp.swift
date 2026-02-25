import SwiftUI

@main
struct LedgeItApp: App {
    @State private var database = AppDatabase.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(database)
        }
        Settings {
            SettingsView()
                .environment(database)
        }
    }
}
