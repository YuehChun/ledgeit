import Foundation
import GRDB
import Observation

@Observable
final class AppDatabase: Sendable {
    let db: DatabaseQueue

    init(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory) {
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        db = try DatabaseQueue(path: path)

        var migrator = DatabaseMigrator()
        DatabaseMigrations.registerMigrations(&migrator)
        try migrator.migrate(db)
    }

    static let shared: AppDatabase = {
        do {
            return try makeDefault()
        } catch {
            fatalError("Failed to initialize AppDatabase: \(error)")
        }
    }()

    static func makeDefault() throws -> AppDatabase {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = appSupportURL.appendingPathComponent("LedgeIt", isDirectory: true)
        let databaseURL = directoryURL.appendingPathComponent("ledgeit.db")
        return try AppDatabase(path: databaseURL.path)
    }

    func resetDatabase() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM financial_goals")
            try db.execute(sql: "DELETE FROM financial_reports")
            try db.execute(sql: "DELETE FROM credit_card_bills")
            try db.execute(sql: "DELETE FROM calendar_events")
            try db.execute(sql: "DELETE FROM transactions")
            try db.execute(sql: "DELETE FROM attachments")
            try db.execute(sql: "DELETE FROM emails")
            try db.execute(sql: "DELETE FROM sync_state")
            try db.execute(sql: "INSERT INTO sync_state (id) VALUES (1)")
        }
    }
}
