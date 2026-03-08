import Foundation
import Testing
import AnyLanguageModel
@testable import LedgeIt

@Suite("SessionFactory")
struct SessionFactoryTests {

    // MARK: - Helpers

    private static let testEndpointId = UUID()

    private static func makeConfig(
        endpoints: [OpenAICompatibleEndpoint] = [],
        provider: AIProvider = .openAICompatible,
        endpointId: UUID? = testEndpointId,
        model: String = "test-model"
    ) -> (AIProviderConfiguration, ModelAssignment) {
        let assignment = ModelAssignment(
            provider: provider,
            endpointId: endpointId,
            model: model
        )
        let config = AIProviderConfiguration(
            endpoints: endpoints,
            classification: assignment,
            extraction: assignment,
            statement: assignment,
            chat: assignment
        )
        return (config, assignment)
    }

    // MARK: - Error Path Tests

    @Test func missingEndpointIdThrows() {
        let (config, _) = Self.makeConfig(endpointId: nil)
        let assignment = ModelAssignment(
            provider: .openAICompatible,
            endpointId: nil,
            model: "test"
        )

        #expect(throws: SessionFactory.SessionError.self) {
            _ = try SessionFactory.makeModel(assignment: assignment, config: config)
        }
    }

    @Test func endpointNotFoundThrows() {
        let (config, assignment) = Self.makeConfig(
            endpoints: [],  // no endpoints
            endpointId: Self.testEndpointId
        )

        #expect(throws: SessionFactory.SessionError.self) {
            _ = try SessionFactory.makeModel(assignment: assignment, config: config)
        }
    }

    @Test func missingAPIKeyThrows() {
        let endpoint = OpenAICompatibleEndpoint(
            id: Self.testEndpointId,
            name: "Test",
            baseURL: "https://example.com/v1",
            requiresAPIKey: true,
            defaultModel: "test"
        )
        let (config, assignment) = Self.makeConfig(
            endpoints: [endpoint],
            endpointId: Self.testEndpointId
        )

        // Keychain won't have a key for this random endpoint ID
        #expect(throws: SessionFactory.SessionError.self) {
            _ = try SessionFactory.makeModel(assignment: assignment, config: config)
        }
    }

    @Test func invalidEndpointURLThrows() {
        let endpoint = OpenAICompatibleEndpoint(
            id: Self.testEndpointId,
            name: "Bad URL",
            baseURL: "",
            requiresAPIKey: false,
            defaultModel: "test"
        )
        let (config, assignment) = Self.makeConfig(
            endpoints: [endpoint],
            endpointId: Self.testEndpointId
        )

        #expect(throws: SessionFactory.SessionError.self) {
            _ = try SessionFactory.makeModel(assignment: assignment, config: config)
        }
    }

    @Test func validEndpointNoKeyCreatesModel() throws {
        let endpoint = OpenAICompatibleEndpoint(
            id: Self.testEndpointId,
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            requiresAPIKey: false,
            defaultModel: "llama3"
        )
        let (config, assignment) = Self.makeConfig(
            endpoints: [endpoint],
            endpointId: Self.testEndpointId
        )

        let model = try SessionFactory.makeModel(assignment: assignment, config: config)
        #expect(model is OpenAILanguageModel)
    }

    @Test func makeSessionCreatesSession() throws {
        let endpoint = OpenAICompatibleEndpoint(
            id: Self.testEndpointId,
            name: "Ollama",
            baseURL: "http://localhost:11434/v1",
            requiresAPIKey: false,
            defaultModel: "llama3"
        )
        let (config, assignment) = Self.makeConfig(
            endpoints: [endpoint],
            endpointId: Self.testEndpointId
        )

        let session = try SessionFactory.makeSession(
            assignment: assignment,
            config: config,
            instructions: "You are a test bot."
        )
        #expect(session.transcript.count > 0) // instructions entry added
    }

    // MARK: - Error description coverage

    @Test func errorDescriptions() {
        let id = UUID()
        let errors: [(SessionFactory.SessionError, String)] = [
            (.endpointNotFound(id), "\(id)"),
            (.missingEndpointId(provider: .openAICompatible), "openAICompatible"),
            (.missingAPIKey(provider: "TestProvider"), "TestProvider"),
            (.invalidEndpointURL("bad url"), "bad url"),
        ]

        for (error, expectedSubstring) in errors {
            let desc = error.errorDescription ?? ""
            #expect(desc.contains(expectedSubstring), "Expected '\(expectedSubstring)' in: \(desc)")
        }
    }
}
