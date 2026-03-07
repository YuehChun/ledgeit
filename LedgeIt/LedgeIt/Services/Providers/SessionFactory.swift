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
    /// For now, all providers return an `OpenAICompatibleSession`.
    /// GoogleSession and a native Anthropic adapter will be integrated later
    /// once the session protocol is unified.
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
        switch assignment.provider {
        case .openAICompatible:
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

        case .anthropic:
            guard let apiKey = KeychainService.load(key: .anthropicAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Anthropic")
            }
            // Anthropic's OpenAI-compatible endpoint
            return OpenAICompatibleSession(
                baseURL: "https://api.anthropic.com/v1",
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )

        case .google:
            // Google uses its own session adapter (GoogleSession), but for now
            // we return OpenAICompatibleSession as a placeholder until
            // the session protocol is unified.
            // TODO: Return GoogleSession when protocol unification is done
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            return OpenAICompatibleSession(
                baseURL: "https://generativelanguage.googleapis.com/v1beta",
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )
        }
    }
}
