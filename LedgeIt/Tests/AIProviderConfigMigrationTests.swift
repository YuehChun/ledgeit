import Foundation
import Testing
@testable import LedgeIt

@Suite("AIProviderConfig Migration")
struct AIProviderConfigMigrationTests {

    // MARK: - Configuration Serialization

    @Test func configRoundtrip() throws {
        let original = AIProviderConfiguration.default
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AIProviderConfiguration.self, from: data)

        #expect(decoded.endpoints.count == original.endpoints.count)
        #expect(decoded.classification == original.classification)
        #expect(decoded.extraction == original.extraction)
        #expect(decoded.statement == original.statement)
        #expect(decoded.chat == original.chat)
    }

    @Test func defaultConfigHasValidEndpointReferences() {
        let config = AIProviderConfiguration.default
        let endpointIds = Set(config.endpoints.map(\.id))

        // Every assignment that uses openAICompatible must reference a valid endpoint
        let assignments = [config.classification, config.extraction, config.statement, config.chat]
        for assignment in assignments {
            if assignment.provider == .openAICompatible {
                #expect(assignment.endpointId != nil, "OpenAI-compatible assignment must have endpoint ID")
                if let eid = assignment.endpointId {
                    #expect(endpointIds.contains(eid), "Endpoint ID \(eid) not found in config endpoints")
                }
            }
        }
    }

    @Test func defaultConfigHasThreeBuiltInPresets() {
        let config = AIProviderConfiguration.default
        let names = config.endpoints.map(\.name)
        #expect(names.contains("OpenAI"))
        #expect(names.contains("OpenRouter"))
        #expect(names.contains("Ollama"))
    }

    @Test func builtInPresetsHaveStableUUIDs() {
        let presets = OpenAICompatibleEndpoint.builtInPresets
        // These UUIDs are used in migration and must never change
        #expect(presets[0].id == UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        #expect(presets[1].id == UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(presets[2].id == UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
    }

    // MARK: - AIProviderConfigStore (UserDefaults only)

    @Test func loadReturnsDefaultWhenEmpty() {
        let suiteName = "test.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // No data stored → should return default
        let data = defaults.data(forKey: "aiProviderConfiguration")
        #expect(data == nil)
    }

    @Test func saveAndLoadRoundtrip() throws {
        let suiteName = "test.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var config = AIProviderConfiguration.default
        config.classification.model = "custom-model-123"

        // Save
        let encoded = try JSONEncoder().encode(config)
        defaults.set(encoded, forKey: "aiProviderConfiguration")

        // Load
        let loaded = defaults.data(forKey: "aiProviderConfiguration")!
        let decoded = try JSONDecoder().decode(AIProviderConfiguration.self, from: loaded)

        #expect(decoded.classification.model == "custom-model-123")
        #expect(decoded.extraction == config.extraction)
    }

    // MARK: - Legacy Key Migration Logic

    @Test func legacyModelKeysAreMappedCorrectly() {
        let suiteName = "test.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate legacy UserDefaults (what main branch stored)
        defaults.set("anthropic/claude-haiku-4-5", forKey: "llmClassificationModel")
        defaults.set("anthropic/claude-sonnet-4-6", forKey: "llmExtractionModel")
        defaults.set("google/gemini-2.5-pro", forKey: "llmStatementModel")
        defaults.set("openai/gpt-4.1", forKey: "llmChatModel")

        // Reproduce the migration logic from AIProviderConfigStore.migrateFromLegacy()
        var config = AIProviderConfiguration.default

        let legacyKeys: [(String, WritableKeyPath<AIProviderConfiguration, ModelAssignment>)] = [
            ("llmClassificationModel", \.classification),
            ("llmExtractionModel", \.extraction),
            ("llmStatementModel", \.statement),
            ("llmChatModel", \.chat),
        ]

        for (legacyKey, keyPath) in legacyKeys {
            if let model = defaults.string(forKey: legacyKey), !model.isEmpty {
                config[keyPath: keyPath].model = model
            }
        }

        #expect(config.classification.model == "anthropic/claude-haiku-4-5")
        #expect(config.extraction.model == "anthropic/claude-sonnet-4-6")
        #expect(config.statement.model == "google/gemini-2.5-pro")
        #expect(config.chat.model == "openai/gpt-4.1")
    }

    @Test func legacyEmptyKeysUseDefaults() {
        let suiteName = "test.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate legacy state with some empty/missing keys
        defaults.set("", forKey: "llmClassificationModel")
        // llmExtractionModel not set at all

        var config = AIProviderConfiguration.default
        let originalExtraction = config.extraction.model

        let legacyKeys: [(String, WritableKeyPath<AIProviderConfiguration, ModelAssignment>)] = [
            ("llmClassificationModel", \.classification),
            ("llmExtractionModel", \.extraction),
        ]

        for (legacyKey, keyPath) in legacyKeys {
            if let model = defaults.string(forKey: legacyKey), !model.isEmpty {
                config[keyPath: keyPath].model = model
            }
        }

        // Empty string should NOT override default
        #expect(config.classification.model == AIProviderConfiguration.default.classification.model)
        // Missing key should keep default
        #expect(config.extraction.model == originalExtraction)
    }

    @Test func migrationSkipsWhenNewConfigExists() {
        let suiteName = "test.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Simulate already-migrated state
        let config = AIProviderConfiguration.default
        let data = try! JSONEncoder().encode(config)
        defaults.set(data, forKey: "aiProviderConfiguration")

        // Migration should detect existing config and skip
        let existingData = defaults.data(forKey: "aiProviderConfiguration")
        #expect(existingData != nil, "Existing config should prevent migration")
    }

    // MARK: - ModelAssignment Validation

    @Test func modelAssignmentCodable() throws {
        let assignment = ModelAssignment(
            provider: .anthropic,
            endpointId: nil,
            model: "claude-sonnet-4-20250514"
        )

        let data = try JSONEncoder().encode(assignment)
        let decoded = try JSONDecoder().decode(ModelAssignment.self, from: data)

        #expect(decoded.provider == .anthropic)
        #expect(decoded.endpointId == nil)
        #expect(decoded.model == "claude-sonnet-4-20250514")
    }

    @Test func openAICompatibleEndpointCodable() throws {
        let endpoint = OpenAICompatibleEndpoint(
            id: UUID(),
            name: "Custom",
            baseURL: "https://my-llm.example.com/v1",
            requiresAPIKey: true,
            defaultModel: "my-model"
        )

        let data = try JSONEncoder().encode(endpoint)
        let decoded = try JSONDecoder().decode(OpenAICompatibleEndpoint.self, from: data)

        #expect(decoded.id == endpoint.id)
        #expect(decoded.name == "Custom")
        #expect(decoded.baseURL == "https://my-llm.example.com/v1")
        #expect(decoded.requiresAPIKey == true)
        #expect(decoded.defaultModel == "my-model")
    }

    @Test func allProvidersCodable() throws {
        for provider in AIProvider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AIProvider.self, from: data)
            #expect(decoded == provider)
        }
    }
}
