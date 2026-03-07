import Foundation

enum SessionFactory {

    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingAPIKey(provider: String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint configuration not found: \(id)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            }
        }
    }

    /// Create a session for completions based on the model assignment.
    ///
    /// All providers route through `OpenAICompatibleSession`. Users can access
    /// Anthropic, Google, and other providers via OpenAI-compatible endpoints
    /// such as OpenRouter.
    ///
    /// - Parameters:
    ///   - assignment: The model assignment specifying provider, endpoint, and model.
    ///   - config: The full AI provider configuration containing endpoint definitions.
    ///   - instructions: Optional system instructions prepended to every request.
    /// - Returns: An `OpenAICompatibleSession` configured for the target provider.
    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        instructions: String = ""
    ) throws -> OpenAICompatibleSession {
        guard let endpointId = assignment.endpointId,
              let endpoint = config.endpoints.first(where: { $0.id == endpointId }) else {
            throw SessionError.endpointNotFound(assignment.endpointId ?? UUID())
        }
        let apiKey = endpoint.requiresAPIKey
            ? KeychainService.loadEndpointAPIKey(endpointId: endpoint.id)
            : nil
        if endpoint.requiresAPIKey && apiKey == nil {
            throw SessionError.missingAPIKey(provider: endpoint.name)
        }
        return OpenAICompatibleSession(
            baseURL: endpoint.baseURL,
            apiKey: apiKey,
            model: assignment.model,
            instructions: instructions
        )
    }
}
