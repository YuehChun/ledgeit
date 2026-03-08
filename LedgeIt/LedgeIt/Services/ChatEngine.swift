import Foundation
import Synchronization
import AnyLanguageModel
import os.log

private let chatLogger = Logger(subsystem: "com.ledgeit.app", category: "ChatEngine")

actor ChatEngine {
    private let queryService: FinancialQueryService
    private let embeddingService: EmbeddingService

    /// Persistent session that accumulates conversation transcript.
    /// Recreated on `clearHistory()` or when provider config changes.
    private var session: LanguageModelSession?

    /// Delegate that forwards tool-call events to the active stream continuation.
    private let toolDelegate = ChatToolExecutionDelegate()

    init(
        queryService: FinancialQueryService = FinancialQueryService(),
        embeddingService: EmbeddingService = EmbeddingService()
    ) {
        self.queryService = queryService
        self.embeddingService = embeddingService
    }

    // MARK: - Public API

    func send(message: String) -> AsyncStream<ChatStreamEvent> {
        let messageId = UUID()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.yield(.error("ChatEngine deallocated"))
                    continuation.finish()
                    return
                }
                await self.processMessage(message, messageId: messageId, continuation: continuation)
            }
        }
    }

    func clearHistory() {
        session = nil
    }

    /// Restore a previously-saved message into the transcript.
    ///
    /// Call this when loading persisted chat history so the session sees
    /// prior conversation context.
    func restoreMessage(role: ChatMessage.ChatRole, content: String) {
        let currentSession = getOrCreateSession()

        let entry: Transcript.Entry
        switch role {
        case .user:
            entry = .prompt(
                Transcript.Prompt(
                    segments: [.text(.init(content: content))],
                    options: GenerationOptions(),
                    responseFormat: nil
                )
            )
        case .assistant:
            entry = .response(
                Transcript.Response(
                    assetIDs: [],
                    segments: [.text(.init(content: content))]
                )
            )
        case .system:
            return
        }

        // Append the entry directly to the session's internal transcript.
        // LanguageModelSession exposes transcript as read-only, so we rebuild.
        rebuildSessionWithAdditionalEntry(currentSession, entry: entry)
    }

    // MARK: - Message Processing

    private func processMessage(
        _ message: String,
        messageId: UUID,
        continuation: AsyncStream<ChatStreamEvent>.Continuation
    ) async {
        do {
            chatLogger.debug("User: \(message)")

            let currentSession = getOrCreateSession()

            // Wire up the delegate to emit tool-call events into our continuation
            toolDelegate.setContinuation(continuation)
            currentSession.toolExecutionDelegate = toolDelegate

            continuation.yield(.messageStarted(messageId))

            // Stream the response — AnyLanguageModel handles the tool-calling
            // loop internally (multi-round tool calls are resolved automatically).
            let stream: LanguageModelSession.ResponseStream<String> = currentSession.streamResponse(
                to: Prompt(message),
                generating: String.self
            )

            var previousContent = ""
            for try await snapshot in stream {
                let current: String = snapshot.content
                if current.count > previousContent.count {
                    let delta = String(current.dropFirst(previousContent.count))
                    continuation.yield(.textDelta(delta))
                }
                previousContent = current
            }

            continuation.yield(.messageComplete)
            continuation.finish()
        } catch {
            chatLogger.error("Chat error: \(error.localizedDescription)")
            continuation.yield(.error(error.localizedDescription))
            continuation.finish()
        }
    }

    // MARK: - Session Management

    /// Get the existing session or create a new one with tools and instructions.
    private func getOrCreateSession() -> LanguageModelSession {
        if let existing = session {
            return existing
        }

        let newSession = createSession()
        session = newSession
        return newSession
    }

    private func createSession() -> LanguageModelSession {
        do {
            let config = AIProviderConfigStore.load()
            let tools = buildTools()
            // Build system prompt synchronously (financial snapshot is fetched lazily
            // via tools, so instructions only contain the static part here).
            let instructions = Self.buildStaticInstructions()

            let newSession = try SessionFactory.makeSession(
                assignment: config.chat,
                config: config,
                tools: tools,
                instructions: instructions
            )
            return newSession
        } catch {
            chatLogger.error("Failed to create session: \(error.localizedDescription)")
            // Return a fallback session that will surface errors on use.
            // This should rarely happen in practice (only if keychain is unavailable).
            fatalError("Cannot create chat session: \(error.localizedDescription)")
        }
    }

    /// Rebuild the session with the same model/tools/instructions but with an
    /// extra transcript entry appended. Used for restoring persisted history.
    private func rebuildSessionWithAdditionalEntry(
        _ currentSession: LanguageModelSession,
        entry: Transcript.Entry
    ) {
        // Build a new transcript from the existing one plus the new entry
        var entries: [Transcript.Entry] = []
        for existingEntry in currentSession.transcript {
            entries.append(existingEntry)
        }
        entries.append(entry)
        let newTranscript = Transcript(entries: entries)

        do {
            let config = AIProviderConfigStore.load()
            let model = try SessionFactory.makeModel(
                assignment: config.chat,
                config: config
            )
            let tools = buildTools()
            let instructions = Self.buildStaticInstructions()

            // Create a new session with the rebuilt transcript.
            // The init(model:tools:instructions:) will add instructions to transcript,
            // but they're already in our existing transcript, so use the transcript init.
            let newSession = LanguageModelSession(
                model: model,
                tools: tools,
                transcript: newTranscript
            )
            session = newSession
        } catch {
            chatLogger.error("Failed to rebuild session: \(error.localizedDescription)")
        }
    }

    // MARK: - Tools

    private func buildTools() -> [any Tool] {
        [
            GetTransactionsTool(queryService: queryService),
            GetSpendingSummaryTool(queryService: queryService),
            GetCategoryBreakdownTool(queryService: queryService),
            GetTopMerchantsTool(queryService: queryService),
            GetUpcomingPaymentsTool(queryService: queryService),
            GetGoalsTool(queryService: queryService),
            SearchTransactionsTool(queryService: queryService),
            GetAccountOverviewTool(queryService: queryService),
            SemanticSearchTool(queryService: queryService, embeddingService: embeddingService),
        ]
    }

    // MARK: - Instructions

    /// Build the static portion of the system instructions.
    ///
    /// The financial snapshot data (income, expenses, etc.) is fetched via tools
    /// at runtime, so instructions only include behavioral guidelines.
    private static func buildStaticInstructions() -> String {
        """
        You are a helpful financial assistant for LedgeIt, a personal finance app.

        ## Interaction Guidelines
        1. **Understand intent first**: When the user asks a question, briefly confirm your understanding \
        of what they want before diving into data. For example: "Let me look up your dining spending this \
        month..." or "I'll check your upcoming payments..."
        2. **Rephrase when ambiguous**: If the user's request is vague or could mean multiple things, \
        rephrase their intent and ask for confirmation before querying data.
        3. **Summarize findings**: After retrieving data, provide a clear summary with key insights, \
        not just raw numbers.
        4. **Proactive suggestions**: When you notice patterns (overspending, upcoming bills, goal progress), \
        mention them.

        ## Formatting
        - Use the available tools to query detailed data when needed.
        - Be concise and helpful.
        - Format currency amounts with 2 decimal places.
        - Respond in the same language the user uses.

        ## Tool Selection
        - Use `semanticSearch` when the user asks about specific merchants, brands, products, or \
        conceptual spending categories. It uses hybrid search (vector + keyword).
        - CRITICAL: Transaction data is stored in BOTH English and Chinese. When searching, ALWAYS provide \
        BOTH the original term AND its translation in the `queries` array. Examples:
          - User asks "寶可夢" → queries: ["寶可夢", "Pokémon", "Pokemon"]
          - User asks "星巴克" → queries: ["星巴克", "Starbucks"]
          - User asks "日本旅遊" → queries: ["日本", "Japan", "JR", "虎航", "Tigerair"]
          - User asks "Uber Eats" → queries: ["Uber Eats", "外送"]
        - Use `getTransactions` or `searchTransactions` when the user specifies exact filters \
        (date range, amount range, transaction type).
        - You can combine both: use semanticSearch first to discover relevant transactions, \
        then getTransactions for precise filtering.
        - Use `getAccountOverview` to get a high-level financial snapshot (income, expenses, \
        upcoming payments, goals) when needed for context.
        """
    }
}

// MARK: - ChatToolExecutionDelegate

/// Bridges AnyLanguageModel's tool execution events to `ChatStreamEvent` via an
/// `AsyncStream.Continuation`. This allows the ChatEngine to emit
/// `.toolCallStarted` events as the model invokes tools.
private final class ChatToolExecutionDelegate: ToolExecutionDelegate, @unchecked Sendable {
    private let _continuation: Mutex<AsyncStream<ChatStreamEvent>.Continuation?> = Mutex(nil)

    func setContinuation(_ continuation: AsyncStream<ChatStreamEvent>.Continuation?) {
        _continuation.withLock { $0 = continuation }
    }

    func didGenerateToolCalls(
        _ toolCalls: [Transcript.ToolCall],
        in session: LanguageModelSession
    ) async {
        let cont = _continuation.withLock { $0 }

        for call in toolCalls {
            chatLogger.debug("Tool call: \(call.toolName)")
            cont?.yield(.toolCallStarted(call.toolName))
        }
    }
}
