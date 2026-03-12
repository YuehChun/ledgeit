import Foundation

// MARK: - Model Catalog

enum ModelCatalog {
    struct ModelEntry: Identifiable, Hashable {
        let id: String      // model ID sent to API
        let label: String   // display name
    }

    struct ModelGroup: Identifiable {
        let id: String      // group key
        let label: String   // group display name
        let models: [ModelEntry]
    }

    // MARK: - Provider Model Groups

    static let claude: ModelGroup = ModelGroup(
        id: "claude",
        label: "Claude",
        models: [
            ModelEntry(id: "claude-sonnet-4-6", label: "Claude Sonnet 4.6"),
            ModelEntry(id: "claude-opus-4-6", label: "Claude Opus 4.6"),
            ModelEntry(id: "claude-haiku-4-5-20251001", label: "Claude Haiku 4.5"),
            ModelEntry(id: "claude-sonnet-4-5-20250929", label: "Claude Sonnet 4.5"),
            ModelEntry(id: "claude-opus-4-5-20251101", label: "Claude Opus 4.5"),
        ]
    )

    static let gpt: ModelGroup = ModelGroup(
        id: "gpt",
        label: "GPT",
        models: [
            ModelEntry(id: "gpt-4.1", label: "GPT-4.1"),
            ModelEntry(id: "gpt-4.1-mini", label: "GPT-4.1 Mini"),
            ModelEntry(id: "gpt-4.1-nano", label: "GPT-4.1 Nano"),
            ModelEntry(id: "gpt-4o", label: "GPT-4o"),
            ModelEntry(id: "gpt-4o-mini", label: "GPT-4o Mini"),
            ModelEntry(id: "o3", label: "o3"),
            ModelEntry(id: "o4-mini", label: "o4-mini"),
        ]
    )

    static let gemini: ModelGroup = ModelGroup(
        id: "gemini",
        label: "Gemini",
        models: [
            ModelEntry(id: "gemini-2.5-pro", label: "Gemini 2.5 Pro"),
            ModelEntry(id: "gemini-2.5-flash", label: "Gemini 2.5 Flash"),
            ModelEntry(id: "gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite"),
            ModelEntry(id: "gemini-3.1-pro-preview", label: "Gemini 3.1 Pro Preview"),
            ModelEntry(id: "gemini-3-flash-preview", label: "Gemini 3 Flash Preview"),
        ]
    )

    // MARK: - OpenRouter uses provider-prefixed model IDs

    static let openRouterClaude: ModelGroup = ModelGroup(
        id: "or-claude",
        label: "Claude",
        models: [
            ModelEntry(id: "anthropic/claude-sonnet-4-6", label: "Claude Sonnet 4.6"),
            ModelEntry(id: "anthropic/claude-opus-4-6", label: "Claude Opus 4.6"),
            ModelEntry(id: "anthropic/claude-haiku-4-5", label: "Claude Haiku 4.5"),
            ModelEntry(id: "anthropic/claude-sonnet-4-5", label: "Claude Sonnet 4.5"),
            ModelEntry(id: "anthropic/claude-opus-4-5", label: "Claude Opus 4.5"),
        ]
    )

    static let openRouterGPT: ModelGroup = ModelGroup(
        id: "or-gpt",
        label: "GPT",
        models: [
            ModelEntry(id: "openai/gpt-4.1", label: "GPT-4.1"),
            ModelEntry(id: "openai/gpt-4.1-mini", label: "GPT-4.1 Mini"),
            ModelEntry(id: "openai/gpt-4.1-nano", label: "GPT-4.1 Nano"),
            ModelEntry(id: "openai/gpt-4o", label: "GPT-4o"),
            ModelEntry(id: "openai/o3", label: "o3"),
            ModelEntry(id: "openai/o4-mini", label: "o4-mini"),
        ]
    )

    static let openRouterGemini: ModelGroup = ModelGroup(
        id: "or-gemini",
        label: "Gemini",
        models: [
            ModelEntry(id: "google/gemini-2.5-pro", label: "Gemini 2.5 Pro"),
            ModelEntry(id: "google/gemini-2.5-flash", label: "Gemini 2.5 Flash"),
            ModelEntry(id: "google/gemini-2.5-flash-lite", label: "Gemini 2.5 Flash Lite"),
        ]
    )

    // MARK: - Resolve groups for a given provider/endpoint

    static func groups(for provider: AIProvider, endpointName: String?) -> [ModelGroup] {
        switch provider {
        case .anthropic:
            return [claude]
        case .google:
            return [gemini]
        case .openAICompatible:
            switch endpointName {
            case "OpenRouter":
                return [openRouterClaude, openRouterGPT, openRouterGemini]
            case "OpenAI":
                return [gpt]
            case "VibeProxy":
                return [claude, gpt, gemini]
            case "Ollama":
                return [] // local models — always custom
            default:
                return [claude, gpt, gemini]
            }
        }
    }

    /// Flat list of all model entries for given groups
    static func allModels(for groups: [ModelGroup]) -> [ModelEntry] {
        groups.flatMap(\.models)
    }
}
