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

    private func makeHeaders() -> [(String, String)] {
        [
            ("Content-Type", "application/json"),
            ("apikey", anonKey),
            ("Authorization", "Bearer \(anonKey)"),
        ]
    }

    /// Upsert a single email to Supabase.
    func upsertEmail(_ email: Email) async throws {
        let payload = emailToDict(email)
        let data = try JSONSerialization.data(withJSONObject: payload)

        let url = baseURL.appendingPathComponent("rest/v1/emails")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in makeHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: respData, encoding: .utf8) ?? ""
            logger.error("Supabase upsert failed: HTTP \(statusCode) - \(body)")
            throw SupabaseServiceError.requestFailed(statusCode, body)
        }
    }

    /// Upsert a batch of emails to Supabase.
    func upsertEmails(_ emails: [Email]) async throws {
        guard !emails.isEmpty else { return }

        let payload = emails.map { emailToDict($0) }
        let data = try JSONSerialization.data(withJSONObject: payload)

        let url = baseURL.appendingPathComponent("rest/v1/emails")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (key, value) in makeHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = data

        let (respData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: respData, encoding: .utf8) ?? ""
            logger.error("Supabase batch upsert failed: HTTP \(statusCode) - \(body)")
            throw SupabaseServiceError.requestFailed(statusCode, body)
        }

        logger.info("Upserted \(emails.count) emails to Supabase")
    }

    /// Check if connection and emails table are accessible.
    func testConnection() async throws -> (Bool, String) {
        // Query emails table with limit=0 to check both auth and table existence
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/emails"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "0"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        for (key, value) in makeHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return (false, "No response from Supabase")
        }

        let body = String(data: data, encoding: .utf8) ?? ""

        switch httpResponse.statusCode {
        case 200...299:
            return (true, "Connected")
        case 401:
            return (false, "Invalid Anon Key (HTTP 401)")
        case 404:
            return (false, "Table 'emails' not found. Create it in Supabase SQL Editor.")
        default:
            // PostgREST returns JSON with "message" field on errors
            if body.contains("relation") && body.contains("does not exist") {
                return (false, "Table 'emails' not found. Create it in Supabase SQL Editor.")
            }
            return (false, "HTTP \(httpResponse.statusCode): \(String(body.prefix(300)))")
        }
    }

    // MARK: - Helpers

    /// Convert Email to a dictionary for JSON serialization.
    /// All keys must always be present (PostgREST requires matching keys in batch upserts).
    private func emailToDict(_ email: Email) -> [String: Any] {
        func val(_ s: String?) -> Any { s ?? NSNull() }
        return [
            "id": email.id,
            "thread_id": val(email.threadId),
            "subject": val(email.subject),
            "sender": val(email.sender),
            "date": val(email.date),
            "snippet": val(email.snippet),
            "body_text": val(email.bodyText),
            "body_html": val(email.bodyHtml),
            "labels": val(email.labels),
            "is_financial": email.isFinancial,
            "is_processed": email.isProcessed,
            "classification_result": val(email.classificationResult),
            "created_at": val(email.createdAt),
        ]
    }
}

enum SupabaseServiceError: LocalizedError {
    case missingURL
    case missingAnonKey
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingURL:
            return "Supabase URL is not configured."
        case .missingAnonKey:
            return "Supabase Anon Key is not configured."
        case .requestFailed(let code, let body):
            let detail = body.prefix(300)
            return "Supabase HTTP \(code): \(detail)"
        }
    }
}
