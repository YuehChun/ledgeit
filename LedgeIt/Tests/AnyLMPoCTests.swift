import Foundation
import Testing
import AnyLanguageModel

// MARK: - P0-2 Tool Definition

struct GreetTool: Tool {
    let name = "greetPerson"
    let description = "Greets a person by name"

    @Generable
    struct Arguments {
        @Guide(description: "The name of the person to greet")
        var name: String
    }

    func call(arguments: Arguments) async throws -> String {
        "Hello, \(arguments.name)! Welcome to LedgeIt."
    }
}

// MARK: - PoC Tests

@Suite("AnyLanguageModel PoC")
struct AnyLMPoCTests {
    private var model: OpenAILanguageModel {
        OpenAILanguageModel(
            baseURL: URL(string: "https://vibe-proxy.ejehome.uk/v1")!,
            apiKey: "test",
            model: "claude-sonnet-4-20250514",
            apiVariant: .chatCompletions
        )
    }

    // P0-1: Custom baseURL with OpenAI-compatible endpoint
    @Test func pocCustomBaseURL() async throws {
        let session = LanguageModelSession(
            model: model,
            instructions: "You are a test bot. Reply with ONLY the word 'PONG' and nothing else."
        )
        let response = try await session.respond(to: "PING")
        print("P0-1 result: \(response.content)")
        #expect(response.content.lowercased().contains("pong"), "Expected 'PONG' but got: \(response.content)")
    }

    // P0-2: Static tool calling
    @Test func pocStaticToolCalling() async throws {
        let session = LanguageModelSession(
            model: model,
            tools: [GreetTool()],
            instructions: "Use the greetPerson tool when asked to greet someone. After the tool returns, relay the greeting message to the user."
        )
        let response = try await session.respond(to: "Please greet Eugene")
        print("P0-2 result: \(response.content)")
        #expect(response.content.contains("Eugene"), "Expected response to contain 'Eugene' but got: \(response.content)")
    }
}
