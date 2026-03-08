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

// MARK: - P0-3 Multi-round Tool Definitions

struct LookupTool: Tool {
    let name = "lookupValue"
    let description = "Looks up a value by key from a database"

    @Generable
    struct Arguments {
        @Guide(description: "The key to look up")
        var key: String
    }

    func call(arguments: Arguments) async throws -> String {
        let db = ["balance": "15000.50", "currency": "TWD", "account": "savings"]
        return db[arguments.key] ?? "not_found"
    }
}

struct FormatTool: Tool {
    let name = "formatCurrency"
    let description = "Formats a currency amount with its currency code"

    @Generable
    struct Arguments {
        @Guide(description: "The numeric amount as string")
        var amount: String
        @Guide(description: "The currency code like TWD, USD")
        var currency: String
    }

    func call(arguments: Arguments) async throws -> String {
        "\(arguments.currency) \(arguments.amount)"
    }
}

// MARK: - P0-4 DynamicTool Definitions

/// A wrapper around GeneratedContent that provides dynamic property access.
/// This allows tools to accept arguments defined at runtime rather than compile time.
struct DynamicArguments: ConvertibleFromGeneratedContent, SendableMetatype {
    let content: GeneratedContent

    init(_ content: GeneratedContent) throws {
        self.content = content
    }

    func string(for key: String) -> String? {
        try? content.value(String.self, forProperty: key)
    }

    func int(for key: String) -> Int? {
        try? content.value(Int.self, forProperty: key)
    }

    func double(for key: String) -> Double? {
        try? content.value(Double.self, forProperty: key)
    }

    func bool(for key: String) -> Bool? {
        try? content.value(Bool.self, forProperty: key)
    }
}

/// A tool whose schema is defined at runtime using DynamicGenerationSchema.
/// This enables plugin-style tool registration without compile-time type definitions.
struct DynamicTool: Tool {
    typealias Arguments = DynamicArguments
    typealias Output = String

    let name: String
    let description: String
    private let schema: GenerationSchema
    private let handler: @Sendable (DynamicArguments) async throws -> String

    var parameters: GenerationSchema { schema }

    init(
        name: String,
        description: String,
        schema: GenerationSchema,
        handler: @escaping @Sendable (DynamicArguments) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.schema = schema
        self.handler = handler
    }

    func call(arguments: DynamicArguments) async throws -> String {
        try await handler(arguments)
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

    // P0-3: Multi-round tool calling (RED blocker)
    // The model must call lookupValue twice (for "balance" and "currency"),
    // then call formatCurrency with the results, demonstrating sequential tool use.
    @Test func pocMultiRoundToolCalling() async throws {
        let session = LanguageModelSession(
            model: model,
            tools: [LookupTool(), FormatTool()],
            instructions: """
                You have a lookup tool and a format tool.
                To answer balance questions:
                1. Use lookupValue with key "balance" to get the amount
                2. Use lookupValue with key "currency" to get the currency code
                3. Use formatCurrency to format the result
                Always use the tools, never guess values.
                """
        )
        let response = try await session.respond(to: "What is my account balance? Format it nicely.")
        print("P0-3 result: \(response.content)")
        #expect(
            response.content.contains("15000") || response.content.contains("15,000"),
            "Expected formatted balance but got: \(response.content)"
        )
    }

    // P0-4: DynamicTool with runtime-defined schema (YELLOW)
    // Validates that we can create tools whose argument schema is defined at runtime
    // using DynamicGenerationSchema, enabling plugin-style tool registration.
    @Test func pocDynamicToolCalling() async throws {
        // Build the schema at runtime using DynamicGenerationSchema
        let dynamicSchema = DynamicGenerationSchema(
            name: "ConvertTemperatureArguments",
            description: "Arguments for temperature conversion",
            properties: [
                .init(
                    name: "value",
                    description: "The temperature value as a string",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
                .init(
                    name: "fromUnit",
                    description: "The source unit: celsius or fahrenheit",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
                .init(
                    name: "toUnit",
                    description: "The target unit: celsius or fahrenheit",
                    schema: DynamicGenerationSchema(type: String.self)
                ),
            ]
        )

        let schema = try GenerationSchema(root: dynamicSchema, dependencies: [])

        let tool = DynamicTool(
            name: "convertTemperature",
            description: "Converts a temperature value between celsius and fahrenheit",
            schema: schema
        ) { args in
            let value = args.string(for: "value") ?? "0"
            let fromUnit = args.string(for: "fromUnit") ?? "celsius"
            let toUnit = args.string(for: "toUnit") ?? "fahrenheit"

            guard let numValue = Double(value) else {
                return "Error: invalid number '\(value)'"
            }

            let result: Double
            if fromUnit.lowercased().hasPrefix("c") && toUnit.lowercased().hasPrefix("f") {
                result = numValue * 9.0 / 5.0 + 32.0
            } else if fromUnit.lowercased().hasPrefix("f") && toUnit.lowercased().hasPrefix("c") {
                result = (numValue - 32.0) * 5.0 / 9.0
            } else {
                result = numValue
            }

            return String(format: "%.1f %@", result, toUnit)
        }

        let session = LanguageModelSession(
            model: model,
            tools: [tool],
            instructions: "Use the convertTemperature tool when asked about temperature conversion. Report the result to the user."
        )

        let response = try await session.respond(to: "Convert 100 degrees celsius to fahrenheit")
        print("P0-4 result: \(response.content)")
        #expect(
            response.content.contains("212") || response.content.contains("fahrenheit") || response.content.contains("Fahrenheit"),
            "Expected converted temperature (212 F) but got: \(response.content)"
        )
    }
}
