import Foundation

// MARK: - Provider Types

enum AIProvider: String, CaseIterable, Codable, Sendable {
    case openAICompatible
    case anthropic
    case google
}

// MARK: - OpenAI Compatible Endpoint Config

struct OpenAICompatibleEndpoint: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    var name: String          // User-defined label, e.g. "OpenRouter", "Ollama"
    var baseURL: String       // Custom endpoint
    var requiresAPIKey: Bool  // false for Ollama
    var defaultModel: String  // Default model ID

    static let builtInPresets: [OpenAICompatibleEndpoint] = [
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            requiresAPIKey: true,
            defaultModel: "gpt-4.1"
        ),
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            requiresAPIKey: true,
            defaultModel: "anthropic/claude-sonnet-4-6"
        ),
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            requiresAPIKey: false,
            defaultModel: "llama3.2"
        ),
        OpenAICompatibleEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "VibeProxy",
            baseURL: "http://127.0.0.1:8318/v1",
            requiresAPIKey: false,
            defaultModel: "claude-sonnet-4-6-20250514"
        ),
    ]
}

// MARK: - Per-Use-Case Model Assignment

struct ModelAssignment: Codable, Sendable, Equatable {
    var provider: AIProvider
    var endpointId: UUID?     // Only for .openAICompatible
    var model: String
}

// MARK: - Full Provider Configuration

struct AIProviderConfiguration: Codable, Sendable {
    var endpoints: [OpenAICompatibleEndpoint]
    var classification: ModelAssignment
    var extraction: ModelAssignment
    var statement: ModelAssignment
    var chat: ModelAssignment
    var advisor: ModelAssignment

    init(endpoints: [OpenAICompatibleEndpoint], classification: ModelAssignment, extraction: ModelAssignment, statement: ModelAssignment, chat: ModelAssignment, advisor: ModelAssignment) {
        self.endpoints = endpoints
        self.classification = classification
        self.extraction = extraction
        self.statement = statement
        self.chat = chat
        self.advisor = advisor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoints = try container.decode([OpenAICompatibleEndpoint].self, forKey: .endpoints)
        classification = try container.decode(ModelAssignment.self, forKey: .classification)
        extraction = try container.decode(ModelAssignment.self, forKey: .extraction)
        statement = try container.decode(ModelAssignment.self, forKey: .statement)
        chat = try container.decode(ModelAssignment.self, forKey: .chat)
        // Backward compatibility: fall back to extraction if advisor is missing
        advisor = try container.decodeIfPresent(ModelAssignment.self, forKey: .advisor) ?? extraction
    }

    static var `default`: AIProviderConfiguration {
        let openRouter = OpenAICompatibleEndpoint.builtInPresets[1]
        let defaultAssignment = ModelAssignment(
            provider: .openAICompatible,
            endpointId: openRouter.id,
            model: "anthropic/claude-sonnet-4-6"
        )
        return AIProviderConfiguration(
            endpoints: OpenAICompatibleEndpoint.builtInPresets,
            classification: ModelAssignment(
                provider: .openAICompatible,
                endpointId: openRouter.id,
                model: "anthropic/claude-haiku-4-5"
            ),
            extraction: defaultAssignment,
            statement: ModelAssignment(
                provider: .openAICompatible,
                endpointId: openRouter.id,
                model: "google/gemini-2.5-pro"
            ),
            chat: defaultAssignment,
            advisor: defaultAssignment
        )
    }
}
