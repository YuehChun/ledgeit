import AppKit
import Foundation

enum GoogleAuthError: LocalizedError {
    case missingCredentials
    case authFailed(String)
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Google client ID or client secret not found in Keychain."
        case .authFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        case .refreshFailed(let reason):
            return "Token refresh failed: \(reason)"
        case .noRefreshToken:
            return "No refresh token available. Please sign in again."
        }
    }
}

@Observable
@MainActor
final class GoogleAuthService {
    private static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private static let scopes = "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/calendar.events"

    private(set) var tokenExpiresAt: Date?

    var isSignedIn: Bool {
        KeychainService.load(key: .googleRefreshToken) != nil
    }

    // MARK: - Sign In

    func signIn() async throws {
        guard let clientID = KeychainService.load(key: .googleClientID)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let clientSecret = KeychainService.load(key: .googleClientSecret)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientID.isEmpty, !clientSecret.isEmpty
        else {
            throw GoogleAuthError.missingCredentials
        }

        // Validate client ID format: should end with .apps.googleusercontent.com
        if !clientID.hasSuffix(".apps.googleusercontent.com") {
            throw GoogleAuthError.authFailed("Invalid client ID format. Expected: <id>.apps.googleusercontent.com")
        }

        let (code, redirectURI) = try await startLoopbackAuthFlow(clientID: clientID)
        try await exchangeCodeForTokens(code: code, clientID: clientID, clientSecret: clientSecret, redirectURI: redirectURI)
    }

    // MARK: - Sign Out

    func signOut() {
        KeychainService.delete(key: .googleAccessToken)
        KeychainService.delete(key: .googleRefreshToken)
        tokenExpiresAt = nil
    }

    // MARK: - Access Token

    nonisolated func getValidAccessToken() async throws -> String {
        let (expiresAt, existingToken) = await MainActor.run {
            (tokenExpiresAt, KeychainService.load(key: .googleAccessToken))
        }

        if let expiresAt,
           Date.now.addingTimeInterval(60) < expiresAt,
           let token = existingToken
        {
            return token
        }

        try await refreshAccessToken()

        guard let token = KeychainService.load(key: .googleAccessToken) else {
            throw GoogleAuthError.refreshFailed("Access token missing after refresh.")
        }

        return token
    }

    // MARK: - Refresh Token

    nonisolated func refreshAccessToken() async throws {
        guard let refreshToken = KeychainService.load(key: .googleRefreshToken) else {
            throw GoogleAuthError.noRefreshToken
        }

        guard let clientID = KeychainService.load(key: .googleClientID),
              let clientSecret = KeychainService.load(key: .googleClientSecret)
        else {
            throw GoogleAuthError.missingCredentials
        }

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
        ]

        let tokenResponse = try await performTokenRequest(body: body)

        try KeychainService.save(key: .googleAccessToken, value: tokenResponse.accessToken)
        await MainActor.run {
            tokenExpiresAt = Date.now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        }

        if let newRefreshToken = tokenResponse.refreshToken {
            try KeychainService.save(key: .googleRefreshToken, value: newRefreshToken)
        }
    }

    // MARK: - Loopback Auth Flow

    /// Starts a local HTTP server, opens the browser for Google OAuth, and waits for the callback.
    private func startLoopbackAuthFlow(clientID: String) async throws -> (code: String, redirectURI: String) {
        let server = LoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        guard var components = URLComponents(string: Self.authorizationEndpoint) else {
            throw GoogleAuthError.authFailed("Invalid authorization endpoint.")
        }

        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else {
            throw GoogleAuthError.authFailed("Could not construct authorization URL.")
        }

        print("[GoogleAuth] Authorization URL: \(authURL.absoluteString)")
        print("[GoogleAuth] Client ID prefix: \(clientID.prefix(20))...")
        NSWorkspace.shared.open(authURL)

        let code = try await server.waitForCode()
        return (code, redirectURI)
    }

    // MARK: - Token Exchange

    private func exchangeCodeForTokens(code: String, clientID: String, clientSecret: String, redirectURI: String) async throws {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
        ]

        let tokenResponse = try await performTokenRequest(body: body)

        try KeychainService.save(key: .googleAccessToken, value: tokenResponse.accessToken)
        tokenExpiresAt = Date.now.addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        if let refreshToken = tokenResponse.refreshToken {
            try KeychainService.save(key: .googleRefreshToken, value: refreshToken)
        }
    }

    // MARK: - Shared Token Request

    private nonisolated func performTokenRequest(body: [String: String]) async throws -> TokenResponse {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw GoogleAuthError.tokenExchangeFailed("Invalid token endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = Data(formBody.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAuthError.tokenExchangeFailed("Invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "No body"
            throw GoogleAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw GoogleAuthError.tokenExchangeFailed("Failed to decode token response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Token Response

private struct TokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Loopback HTTP Server

/// A minimal HTTP server that listens on 127.0.0.1 for the OAuth callback.
private final class LoopbackServer: @unchecked Sendable {
    private var socketFD: Int32 = -1
    private var port: UInt16 = 0
    private var continuation: CheckedContinuation<String, any Error>?

    func start() async throws -> UInt16 {
        socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw GoogleAuthError.authFailed("Failed to create socket.")
        }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Let the OS pick a port
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            close(socketFD)
            throw GoogleAuthError.authFailed("Failed to bind socket.")
        }

        // Get the assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socketFD, sockPtr, &addrLen)
            }
        }
        port = assignedAddr.sin_port.bigEndian

        guard listen(socketFD, 1) == 0 else {
            close(socketFD)
            throw GoogleAuthError.authFailed("Failed to listen on socket.")
        }

        return port
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont

            DispatchQueue.global(qos: .userInitiated).async { [self] in
                self.acceptConnection()
            }
        }
    }

    private func acceptConnection() {
        let clientFD = accept(socketFD, nil, nil)
        guard clientFD >= 0 else {
            continuation?.resume(throwing: GoogleAuthError.authFailed("Failed to accept connection."))
            close(socketFD)
            return
        }

        // Read the HTTP request
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(clientFD, &buffer, buffer.count)
        guard bytesRead > 0 else {
            continuation?.resume(throwing: GoogleAuthError.authFailed("Empty request from browser."))
            close(clientFD)
            close(socketFD)
            return
        }

        let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

        // Parse the auth code from "GET /?code=...&scope=... HTTP/1.1"
        var authCode: String?
        var errorMessage: String?

        if let firstLine = requestString.components(separatedBy: "\r\n").first,
           let urlPart = firstLine.split(separator: " ").dropFirst().first,
           let components = URLComponents(string: "http://localhost\(urlPart)")
        {
            authCode = components.queryItems?.first(where: { $0.name == "code" })?.value
            errorMessage = components.queryItems?.first(where: { $0.name == "error" })?.value
        }

        // Send response HTML
        let html: String
        if authCode != nil {
            html = """
            <!DOCTYPE html><html><body style="font-family:-apple-system,system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f7">
            <div style="text-align:center"><h1 style="color:#34c759">&#10003; Connected!</h1><p style="color:#666">You can close this tab and return to LedgeIt.</p></div>
            </body></html>
            """
        } else {
            html = """
            <!DOCTYPE html><html><body style="font-family:-apple-system,system-ui;display:flex;justify-content:center;align-items:center;height:100vh;margin:0;background:#f5f5f7">
            <div style="text-align:center"><h1 style="color:#ff3b30">&#10007; Error</h1><p style="color:#666">\(errorMessage ?? "Authentication failed.")</p></div>
            </body></html>
            """
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n\(html)"
        _ = response.withCString { ptr in
            write(clientFD, ptr, strlen(ptr))
        }

        close(clientFD)
        close(socketFD)

        if let code = authCode {
            continuation?.resume(returning: code)
        } else {
            continuation?.resume(throwing: GoogleAuthError.authFailed(errorMessage ?? "No authorization code received."))
        }
    }
}
