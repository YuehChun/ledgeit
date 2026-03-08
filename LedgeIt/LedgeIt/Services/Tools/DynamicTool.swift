import Foundation
import AnyLanguageModel

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
