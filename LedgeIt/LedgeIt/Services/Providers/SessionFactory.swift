import Foundation

enum SessionFactory {

    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingEndpointId(provider: AIProvider)
        case missingAPIKey(provider: String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint configuration not found: \(id)"
            case .missingEndpointId(let provider):
                return "Endpoint ID is required for provider: \(provider.rawValue)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            }
        }
    }

    /// Create a session for completions based on the model assignment.
    ///
    /// Returns the appropriate session type for the configured provider:
    /// - `.openAICompatible` → `OpenAICompatibleSession` (OpenAI, OpenRouter, Ollama, Groq)
    /// - `.anthropic` → `AnthropicSession` (direct Anthropic API)
    /// - `.google` → `GoogleSession` (Google Gemini API)
    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        instructions: String = ""
    ) throws -> any LLMSession {
        switch assignment.provider {
        case .openAICompatible:
            guard let endpointId = assignment.endpointId else {
                throw SessionError.missingEndpointId(provider: assignment.provider)
            }
            guard let endpoint = config.endpoints.first(where: { $0.id == endpointId }) else {
                throw SessionError.endpointNotFound(endpointId)
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
            return AnthropicSession(
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )

        case .google:
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            return GoogleSession(
                apiKey: apiKey,
                model: assignment.model,
                instructions: instructions
            )
        }
    }
}
