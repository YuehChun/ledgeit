import Foundation
import SwiftUI
import GRDB

/// Singleton that holds chat state across view lifecycle.
/// Survives sidebar navigation; persists messages to DB for app restarts.
@MainActor
final class ChatSessionManager: ObservableObject {
    static let shared = ChatSessionManager()

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming = false

    let chatEngine = ChatEngine()
    private var hasLoaded = false

    private init() {}

    // MARK: - Session Lifecycle

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            messages = try AppDatabase.shared.db.read { db in
                try ChatMessage
                    .order(ChatMessage.Columns.createdAt.asc)
                    .fetchAll(db)
            }
            // Restore ChatEngine conversation history
            Task {
                await chatEngine.clearHistory()
                for msg in messages where msg.role == .user || msg.role == .assistant {
                    await chatEngine.restoreMessage(
                        role: msg.role,
                        content: msg.content
                    )
                }
            }
        } catch {
            print("ChatSessionManager: failed to load session: \(error)")
        }
    }

    func newSession() {
        messages = []
        Task {
            await chatEngine.clearHistory()
            try? await AppDatabase.shared.db.write { db in
                try ChatMessage.deleteAll(db)
            }
        }
    }

    // MARK: - Send Message

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage.user(trimmed)
        messages.append(userMessage)
        persistInsert(userMessage)
        isStreaming = true

        Task {
            let assistantId = UUID()
            let assistantMessage = ChatMessage(id: assistantId, role: .assistant, content: "", createdAt: ISO8601DateFormatter().string(from: Date()))
            messages.append(assistantMessage)

            let stream = await chatEngine.send(message: trimmed)

            for await event in stream {
                await MainActor.run {
                    switch event {
                    case .messageStarted:
                        break
                    case .textDelta(let delta):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            if messages[idx].content.hasPrefix("Looking up ") {
                                messages[idx].content = ""
                            }
                            messages[idx].content += delta
                        }
                    case .toolCallStarted(let name):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            if messages[idx].content.isEmpty {
                                messages[idx].content = "Looking up \(name)..."
                            }
                        }
                    case .messageComplete:
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            persistInsert(messages[idx])
                        }
                    case .error(let msg):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx] = .system("Error: \(msg)")
                        }
                    }
                }
            }

            isStreaming = false
        }
    }

    // MARK: - DB Persistence

    private func persistInsert(_ message: ChatMessage) {
        Task {
            do {
                try await AppDatabase.shared.db.write { db in
                    try message.insert(db)
                }
            } catch {
                print("ChatSessionManager: failed to save message: \(error)")
            }
        }
    }
}
