import Foundation

// MARK: - Gmail API Response Types

struct GmailMessageList: Codable, Sendable {
    let messages: [GmailMessageRef]?
    let nextPageToken: String?
    let resultSizeEstimate: Int?
}

struct GmailMessageRef: Codable, Sendable {
    let id: String
    let threadId: String
}

struct GmailMessage: Codable, Sendable {
    let id: String
    let threadId: String
    let labelIds: [String]?
    let snippet: String?
    let payload: GmailPayload?
    let internalDate: String?
}

struct GmailPayload: Codable, Sendable {
    let partId: String?
    let mimeType: String?
    let filename: String?
    let headers: [GmailHeader]?
    let body: GmailBody?
    let parts: [GmailPayload]?
}

struct GmailHeader: Codable, Sendable {
    let name: String
    let value: String
}

struct GmailBody: Codable, Sendable {
    let attachmentId: String?
    let size: Int?
    let data: String?
}

struct GmailProfile: Codable, Sendable {
    let emailAddress: String
    let messagesTotal: Int?
    let threadsTotal: Int?
    let historyId: String?
}

struct GmailAttachmentResponse: Codable, Sendable {
    let attachmentId: String?
    let size: Int?
    let data: String?
}

// MARK: - Errors

enum GmailError: LocalizedError {
    case unauthorized
    case requestFailed(Int)
    case decodingFailed
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Gmail authorization failed. Please re-authenticate."
        case .requestFailed(let statusCode):
            return "Gmail API request failed with status code \(statusCode)."
        case .decodingFailed:
            return "Failed to decode Gmail API response."
        case .invalidURL:
            return "Invalid Gmail API URL."
        }
    }
}

// MARK: - GmailService

actor GmailService {
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"
    private let accessTokenProvider: @Sendable () async throws -> String

    init(accessTokenProvider: @escaping @Sendable () async throws -> String) {
        self.accessTokenProvider = accessTokenProvider
    }

    // MARK: - API Methods

    func listMessages(query: String? = nil, maxResults: Int = 100, pageToken: String? = nil) async throws -> GmailMessageList {
        let components = URLComponents(string: "\(baseURL)/messages")
        guard var components else { throw GmailError.invalidURL }

        var queryItems: [URLQueryItem] = []
        if let query {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        queryItems.append(URLQueryItem(name: "maxResults", value: String(maxResults)))
        if let pageToken {
            queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw GmailError.invalidURL }
        return try await makeRequest(url: url)
    }

    func getMessage(id: String) async throws -> GmailMessage {
        let components = URLComponents(string: "\(baseURL)/messages/\(id)")
        guard var components else { throw GmailError.invalidURL }
        components.queryItems = [URLQueryItem(name: "format", value: "full")]

        guard let url = components.url else { throw GmailError.invalidURL }
        return try await makeRequest(url: url)
    }

    func getAttachment(messageId: String, attachmentId: String) async throws -> Data {
        let urlString = "\(baseURL)/messages/\(messageId)/attachments/\(attachmentId)"
        guard let url = URL(string: urlString) else { throw GmailError.invalidURL }

        let response: GmailAttachmentResponse = try await makeRequest(url: url)
        guard let base64URLData = response.data else {
            throw GmailError.decodingFailed
        }

        guard let decoded = decodeBase64URL(base64URLData) else {
            throw GmailError.decodingFailed
        }
        return decoded
    }

    func getProfile() async throws -> GmailProfile {
        guard let url = URL(string: "\(baseURL)/profile") else { throw GmailError.invalidURL }
        return try await makeRequest(url: url)
    }

    // MARK: - Helpers

    func extractBody(from payload: GmailPayload) -> (text: String?, html: String?) {
        var text: String?
        var html: String?
        extractBodyRecursive(from: payload, text: &text, html: &html)
        return (text, html)
    }

    func extractHeaders(from headers: [GmailHeader]) -> (subject: String?, sender: String?, date: String?) {
        var subject: String?
        var sender: String?
        var date: String?

        for header in headers {
            switch header.name.lowercased() {
            case "subject":
                subject = header.value
            case "from":
                sender = header.value
            case "date":
                date = header.value
            default:
                break
            }
        }

        return (subject, sender, date)
    }

    // MARK: - Private

    private func makeRequest<T: Decodable>(url: URL) async throws -> T {
        let token = try await accessTokenProvider()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GmailError.requestFailed(0)
        }

        if httpResponse.statusCode == 401 {
            throw GmailError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GmailError.requestFailed(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GmailError.decodingFailed
        }
    }

    private func extractBodyRecursive(from payload: GmailPayload, text: inout String?, html: inout String?) {
        if let mimeType = payload.mimeType {
            if mimeType == "text/plain", text == nil, let bodyData = payload.body?.data {
                if let decoded = decodeBase64URL(bodyData) {
                    text = String(data: decoded, encoding: .utf8)
                }
            }
            if mimeType == "text/html", html == nil, let bodyData = payload.body?.data {
                if let decoded = decodeBase64URL(bodyData) {
                    html = String(data: decoded, encoding: .utf8)
                }
            }
        }

        if let parts = payload.parts {
            for part in parts {
                extractBodyRecursive(from: part, text: &text, html: &html)
                if text != nil && html != nil { return }
            }
        }
    }

    private func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        return Data(base64Encoded: base64)
    }
}
