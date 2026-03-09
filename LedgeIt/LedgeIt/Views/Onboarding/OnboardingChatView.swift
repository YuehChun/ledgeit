import SwiftUI

struct OnboardingChatView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var inputText = ""

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Chat area
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                ChatBubbleView(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isTyping {
                                TypingIndicatorView()
                                    .id("typing-indicator")
                            }

                            if viewModel.isProcessing {
                                processingIndicator
                                    .id("processing-indicator")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) {
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: viewModel.isTyping) {
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                // Get Started button or chat input
                if viewModel.currentStep == .complete {
                    getStartedButton
                } else {
                    chatInput
                }
            }

            // FormCard overlay
            if viewModel.showFormCard {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {} // Block taps on background

                FormCardView(viewModel: viewModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.showFormCard)
        .task {
            await viewModel.onAppear()
        }
    }

    // MARK: - Chat Input

    private var chatInput: some View {
        HStack(spacing: 8) {
            TextField(
                viewModel.selectedLanguage == "zh-Hant" ? "輸入訊息..." : "Type a message...",
                text: $inputText,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .lineLimit(1...5)
            .disabled(viewModel.isProcessing)
            .onSubmit {
                sendMessage()
            }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing
                            ? .secondary : Color.accentColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isProcessing)
        }
        .padding()
    }

    // MARK: - Get Started Button

    private var getStartedButton: some View {
        Button {
            viewModel.completeOnboarding()
        } label: {
            Text(viewModel.selectedLanguage == "zh-Hant" ? "開始使用" : "Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding()
    }

    // MARK: - Processing Indicator

    private var processingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.selectedLanguage == "zh-Hant" ? "處理中..." : "Processing...")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isProcessing else { return }
        let messageText = text
        inputText = ""
        Task {
            await viewModel.sendChatMessage(messageText)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if viewModel.isTyping {
            withAnimation {
                proxy.scrollTo("typing-indicator", anchor: .bottom)
            }
        } else if let last = viewModel.messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - ChatBubbleView

struct ChatBubbleView: View {
    let message: OnboardingMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            Text(.init(message.content))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .assistant:
            Color(.controlBackgroundColor)
        case .user:
            Color.accentColor.opacity(0.15)
        }
    }
}

// MARK: - TypingIndicatorView

struct TypingIndicatorView: View {
    @State private var dotCount = 1

    var body: some View {
        HStack {
            Text(String(repeating: "\u{25CF}", count: dotCount))
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(maxWidth: 500, alignment: .leading)

            Spacer(minLength: 60)
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in
                dotCount = (dotCount % 3) + 1
            }
        }
    }
}
