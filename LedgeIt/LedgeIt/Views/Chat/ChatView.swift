import SwiftUI

struct ChatView: View {
    @AppStorage("appLanguage") private var appLanguage = "en"
    private var l10n: L10n { L10n(appLanguage) }

    @ObservedObject private var session = ChatSessionManager.shared
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(l10n.chatTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    session.newSession()
                } label: {
                    Label(l10n.newSession, systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(l10n.newSessionHelp)
            }
            .padding()

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if session.messages.isEmpty {
                            emptyState
                        } else {
                            ForEach(session.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: session.messages.count) {
                    if let last = session.messages.last {
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
                        if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming {
                            session.send(text: inputText)
                            inputText = ""
                        }
                    }

                Button {
                    session.send(text: inputText)
                    inputText = ""
                } label: {
                    Image(systemName: session.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming
                                ? .secondary : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming)
            }
            .padding()
        }
        .onAppear { session.loadIfNeeded() }
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
}
