import Foundation

enum AIProviderConfigStore {
    private static let key = "aiProviderConfiguration"

    static func load() -> AIProviderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let config = try? JSONDecoder().decode(AIProviderConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    static func save(_ config: AIProviderConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Migrate from legacy OpenRouter-only config.
    /// Returns the migrated config if migration was performed, nil otherwise.
    @discardableResult
    static func migrateFromLegacy() -> AIProviderConfiguration? {
        // Skip if already migrated
        if UserDefaults.standard.data(forKey: key) != nil {
            return nil
        }

        // Check if legacy OpenRouter key exists
        guard let openRouterKey = KeychainService.load(key: .openRouterAPIKey) else {
            return nil
        }

        var config = AIProviderConfiguration.default
        let openRouterEndpoint = config.endpoints.first(where: { $0.name == "OpenRouter" })!

        // Save the OpenRouter API key to the endpoint keychain slot
        try? KeychainService.saveEndpointAPIKey(
            endpointId: openRouterEndpoint.id,
            value: openRouterKey
        )

        // Map existing model selections from legacy UserDefaults keys
        let legacyKeys: [(String, WritableKeyPath<AIProviderConfiguration, ModelAssignment>)] = [
            ("llmClassificationModel", \.classification),
            ("llmExtractionModel", \.extraction),
            ("llmStatementModel", \.statement),
            ("llmChatModel", \.chat),
        ]

        for (legacyKey, keyPath) in legacyKeys {
            if let model = UserDefaults.standard.string(forKey: legacyKey), !model.isEmpty {
                config[keyPath: keyPath].model = model
            }
        }

        save(config)
        return config
    }
}
