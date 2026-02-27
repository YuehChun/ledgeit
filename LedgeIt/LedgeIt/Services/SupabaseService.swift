import Foundation
import os

/// Lightweight Supabase REST API client using URLSession (no SDK dependency).
/// Upserts emails to the `emails` table for cloud backup.
struct SupabaseService: Sendable {
    let baseURL: URL
    let anonKey: String

    private let logger = Logger(subsystem: "com.ledgeit", category: "SupabaseService")

    init() throws {
        guard let urlString = KeychainService.load(key: .supabaseURL),
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            throw SupabaseServiceError.missingURL
        }
        guard let key = KeychainService.load(key: .supabaseAnonKey),
              !key.isEmpty else {
            throw SupabaseServiceError.missingAnonKey
        }
        self.baseURL = url
        self.anonKey = key
    }

    /// Upsert a single email to Supabase.
    func upsertEmail(_ email: Email) async throws {
        let url = baseURL.appendingPathComponent("rest/v1/emails")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        // Upsert: on conflict with primary key (id), merge the new data
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(email)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Supabase upsert failed: HTTP \(statusCode)")
            throw SupabaseServiceError.upsertFailed(statusCode)
        }
    }

    /// Upsert a batch of emails to Supabase.
    func upsertEmails(_ emails: [Email]) async throws {
        guard !emails.isEmpty else { return }

        let url = baseURL.appendingPathComponent("rest/v1/emails")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(emails)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Supabase batch upsert failed: HTTP \(statusCode)")
            throw SupabaseServiceError.upsertFailed(statusCode)
        }

        logger.info("Upserted \(emails.count) emails to Supabase")
    }

    /// Check if connection is valid by querying the emails table (limit 0).
    func testConnection() async throws -> Bool {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/emails"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "0"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        return (200...299).contains(httpResponse.statusCode)
    }
}

enum SupabaseServiceError: LocalizedError {
    case missingURL
    case missingAnonKey
    case upsertFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Supabase URL is not configured."
        case .missingAnonKey:
            return "Supabase Anon Key is not configured."
        case .upsertFailed(let code):
            return "Supabase upsert failed with HTTP \(code)."
        }
    }
}
