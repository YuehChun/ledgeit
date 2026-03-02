import SwiftUI

struct ChatView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var chatEngine = ChatEngine()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(l10n.chatTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if !messages.isEmpty {
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(l10n.clearChat)
                }
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                TextField(l10n.chatPlaceholder, text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming {
                            sendMessage()
                        }
                    }

                Button(action: sendMessage) {
                    Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
                                ? .secondary : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming)
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(l10n.chatEmptyTitle)
                .font(.title3)
                .fontWeight(.medium)
            Text(l10n.chatEmptyDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage.user(text)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true

        Task {
            let assistantId = UUID()
            let assistantMessage = ChatMessage(id: assistantId, role: .assistant, content: "", timestamp: Date())
            messages.append(assistantMessage)

            let stream = await chatEngine.send(message: text)

            for await event in stream {
                await MainActor.run {
                    switch event {
                    case .messageStarted:
                        break
                    case .textDelta(let delta):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            // Clear tool-call placeholder if present
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
                        break
                    case .error(let msg):
                        if let idx = messages.firstIndex(where: { $0.id == assistantId }) {
                            messages[idx] = .system("Error: \(msg)")
                        }
                    }
                }
            }

            await MainActor.run {
                isStreaming = false
            }
        }
    }

    private func clearChat() {
        messages = []
        Task { await chatEngine.clearHistory() }
    }
}
