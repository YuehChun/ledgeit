import Foundation

/// Unified protocol for all LLM provider sessions.
///
/// Conforming types: `OpenAICompatibleSession`, `AnthropicSession`, `GoogleSession`.
/// All methods accept `LLMMessage` arrays and return provider-agnostic types.
protocol LLMSession: Actor, Sendable {

    /// Non-streaming completion. Returns the full response text.
    func complete(
        messages: [LLMMessage],
        temperature: Double,
        maxTokens: Int?
    ) async throws -> String

    /// Streaming completion with optional tool definitions.
    /// Returns an async stream of `LLMStreamEvent` (text deltas, tool calls, done, errors).
    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition],
        temperature: Double,
        maxTokens: Int?
    ) -> AsyncStream<LLMStreamEvent>
}

/// Default parameter values via extension.
extension LLMSession {
    func complete(
        messages: [LLMMessage],
        temperature: Double = 0.1,
        maxTokens: Int? = nil
    ) async throws -> String {
        try await complete(messages: messages, temperature: temperature, maxTokens: maxTokens)
    }

    func streamComplete(
        messages: [LLMMessage],
        tools: [LLMToolDefinition] = [],
        temperature: Double = 0.3,
        maxTokens: Int? = nil
    ) -> AsyncStream<LLMStreamEvent> {
        streamComplete(messages: messages, tools: tools, temperature: temperature, maxTokens: maxTokens)
    }
}
