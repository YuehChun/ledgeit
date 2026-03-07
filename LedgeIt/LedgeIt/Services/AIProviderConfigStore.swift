import Foundation
import os.log

private let configLogger = Logger(subsystem: "com.ledgeit.app", category: "AIProviderConfigStore")

enum AIProviderConfigStore {
    private static let key = "aiProviderConfiguration"

    static func load() -> AIProviderConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(AIProviderConfiguration.self, from: data)
        } catch {
            configLogger.error("Failed to decode saved AI provider config: \(error.localizedDescription). Returning defaults.")
            return .default
        }
    }

    static func save(_ config: AIProviderConfiguration) {
        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            configLogger.error("Failed to encode AI provider config: \(error.localizedDescription)")
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
        do {
            try KeychainService.saveEndpointAPIKey(
                endpointId: openRouterEndpoint.id,
                value: openRouterKey
            )
        } catch {
            configLogger.error("Migration failed to save OpenRouter API key: \(error.localizedDescription)")
            return nil
        }

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
        configLogger.info("Successfully migrated legacy OpenRouter config")
        return config
    }
}
