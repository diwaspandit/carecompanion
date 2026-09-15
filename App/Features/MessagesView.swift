import CareCore
import SwiftUI

/// The family's shared conversation. Realtime refresh brings in messages from other devices.
struct MessagesScreen: View {
    @Environment(AppState.self) private var state
    var large = false
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Messages")
                    .font(.system(size: large ? 32 : 28, weight: .black, design: large ? .rounded : .default))
                    .accessibilityAddTraits(.isHeader)
                Text(state.snapshot.account.name)
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 10)

            if state.messages.isEmpty {
                Spacer()
                EmptyStateCard(icon: "bubble.left.and.bubble.right", title: "No messages yet",
                               message: "Say hello. Everyone in \(state.snapshot.account.name) will see it.")
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.messages) { message in
                            MessageBubble(message: message, isMine: state.isFromCurrentUser(message),
                                          sender: state.senderName(for: message), large: large)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: large ? 19 : 16))
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CareTheme.cardStroke))
                    .accessibilityIdentifier("messages.input")
                Button(action: send) {
                    Image(systemName: isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(canSend ? CareTheme.sage : CareTheme.sage.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("messages.send")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CareTheme.background)
        }
        .background(CareTheme.background)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft
        Task {
            isSending = true
            if await state.sendMessage(text) { draft = "" }
            isSending = false
        }
    }
}

private struct MessageBubble: View {
    let message: CareMessage
    let isMine: Bool
    let sender: String
    let large: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if !isMine {
                    Text(sender).font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
                }
                Text(message.body)
                    .font(.system(size: large ? 19 : 16))
                    .foregroundStyle(isMine ? .white : CareTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isMine ? CareTheme.sage : .white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isMine ? .clear : CareTheme.cardStroke))
                Text(message.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 11))
                    .foregroundStyle(CareTheme.secondaryText)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sender): \(message.body)")
    }
}
