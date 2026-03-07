import Foundation

/// Standalone service for fetching OpenRouter credit/usage information.
/// Extracted from the legacy OpenRouterService so credit display works
/// without depending on the general-purpose LLM completion actor.
enum OpenRouterCreditsService {

    struct CreditInfo: Sendable {
        let totalCredits: Double
        let usage: Double
        let remaining: Double
        let isFreeTier: Bool
    }

    enum CreditError: LocalizedError {
        case missingAPIKey
        case requestFailed(Int)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenRouter API key not found"
            case .requestFailed(let code):
                return "OpenRouter request failed with status \(code)"
            case .invalidResponse:
                return "Invalid response from OpenRouter"
            }
        }
    }

    /// Fetch credit information for the given API key.
    /// Tries the account-level `/credits` endpoint first, then falls back to `/key`.
    static func fetchCredits(apiKey: String) async throws -> CreditInfo {
        if let accountInfo = try? await fetchAccountCredits(apiKey: apiKey) {
            return accountInfo
        }
        return try await fetchKeyCredits(apiKey: apiKey)
    }

    // MARK: - Private

    private static func fetchAccountCredits(apiKey: String) async throws -> CreditInfo {
        guard let url = URL(string: "https://openrouter.ai/api/v1/credits") else {
            throw CreditError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CreditError.requestFailed(0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw CreditError.invalidResponse
        }

        let total = dataObj["total_credits"] as? Double ?? 0
        let used = dataObj["total_usage"] as? Double ?? 0

        return CreditInfo(
            totalCredits: total,
            usage: used,
            remaining: total - used,
            isFreeTier: total == 0
        )
    }

    private static func fetchKeyCredits(apiKey: String) async throws -> CreditInfo {
        guard let url = URL(string: "https://openrouter.ai/api/v1/key") else {
            throw CreditError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CreditError.requestFailed(0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any] else {
            throw CreditError.invalidResponse
        }

        let limit = dataObj["limit"] as? Double
        let limitRemaining = dataObj["limit_remaining"] as? Double
        let usage = dataObj["usage"] as? Double ?? 0
        let isFreeTier = dataObj["is_free_tier"] as? Bool ?? true

        let total = limit ?? (usage + (limitRemaining ?? 0))
        let remaining = limitRemaining ?? (total - usage)

        return CreditInfo(
            totalCredits: total,
            usage: usage,
            remaining: remaining,
            isFreeTier: isFreeTier
        )
    }
}
