import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                        Text(message.content)
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Text(LocalizedStringKey(message.content))
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            message.role == .user
                                ? Color.accentColor
                                : Color(.controlBackgroundColor)
                        )
                        .foregroundStyle(message.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            if message.role != .user { Spacer(minLength: 60) }
        }
    }
}
