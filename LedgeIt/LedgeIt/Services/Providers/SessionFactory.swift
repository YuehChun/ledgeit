import Foundation
import AnyLanguageModel

enum SessionFactory {

    enum SessionError: LocalizedError {
        case endpointNotFound(UUID)
        case missingEndpointId(provider: AIProvider)
        case missingAPIKey(provider: String)
        case invalidEndpointURL(String)

        var errorDescription: String? {
            switch self {
            case .endpointNotFound(let id):
                return "Endpoint configuration not found: \(id)"
            case .missingEndpointId(let provider):
                return "Endpoint ID is required for provider: \(provider.rawValue)"
            case .missingAPIKey(let provider):
                return "API key not configured for \(provider)"
            case .invalidEndpointURL(let url):
                return "Invalid endpoint URL: \(url)"
            }
        }
    }

    /// Create a `LanguageModelSession` for the given assignment, with optional tools and instructions.
    static func makeSession(
        assignment: ModelAssignment,
        config: AIProviderConfiguration,
        tools: [any Tool] = [],
        instructions: String = ""
    ) throws -> LanguageModelSession {
        let model = try makeModel(assignment: assignment, config: config)
        return LanguageModelSession(model: model, tools: tools, instructions: instructions)
    }

    /// Create a bare `LanguageModel` (no session/transcript) for the given assignment.
    ///
    /// Use this when you need to construct a `LanguageModelSession` yourself
    /// (e.g. with a pre-existing `Transcript`).
    static func makeModel(
        assignment: ModelAssignment,
        config: AIProviderConfiguration
    ) throws -> any LanguageModel {
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
            guard let baseURL = URL(string: endpoint.baseURL) else {
                throw SessionError.invalidEndpointURL(endpoint.baseURL)
            }
            return OpenAILanguageModel(
                baseURL: baseURL,
                apiKey: apiKey ?? "",
                model: assignment.model,
                apiVariant: .chatCompletions
            )

        case .anthropic:
            guard let apiKey = KeychainService.load(key: .anthropicAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Anthropic")
            }
            return AnthropicLanguageModel(apiKey: apiKey, model: assignment.model)

        case .google:
            guard let apiKey = KeychainService.load(key: .googleAIAPIKey) else {
                throw SessionError.missingAPIKey(provider: "Google AI")
            }
            return GeminiLanguageModel(apiKey: apiKey, model: assignment.model)
        }
    }

}
