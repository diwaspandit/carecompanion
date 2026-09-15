import CareCore
import SwiftUI

/// Senior mood check with an optional note, shared with the family.
struct EnhancedMoodView: View {
    @Environment(AppState.self) private var state
    @State private var selectedMood: Mood?
    @State private var note = ""
    @State private var isSaving = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { state.seniorTab = .home } label: {
                    Label("Home", systemImage: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CareTheme.sageDark)
                        .frame(minHeight: 44)
                }
                .padding(.top, 12)
                .accessibilityIdentifier("mood.back")

                Text("How are you feeling\ntoday?")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CareTheme.ink)
                    .padding(.top, 24)
                Text("Tap one face. You can add a note for your family.")
                    .font(.system(size: 19))
                    .foregroundStyle(CareTheme.secondaryText)
                    .padding(.top, 14)
                    .padding(.bottom, 28)

                VStack(spacing: 16) {
                    moodButton("😊", title: "Good", mood: .great)
                    moodButton("😐", title: "Okay", mood: .okay)
                    moodButton("😔", title: "Not great", mood: .low)
                }

                if let selectedMood {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Add a note (optional)", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 19))
                            .focused($noteFocused)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(CareTheme.cardStroke))
                            .accessibilityIdentifier("mood.note")
                        PrimaryActionButton(title: "Share with family", isLoading: isSaving) {
                            Task {
                                isSaving = true
                                await state.recordMood(selectedMood, note: note)
                                isSaving = false
                            }
                        }
                        .accessibilityIdentifier("mood.save")
                    }
                    .padding(.top, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedMood)
    }

    private func moodButton(_ emoji: String, title: String, mood: Mood) -> some View {
        let selected = selectedMood == mood
        return Button {
            selectedMood = mood
        } label: {
            HStack(spacing: 24) {
                Text(emoji).font(.system(size: 42))
                Text(title).font(.system(size: 28, weight: .black)).foregroundStyle(CareTheme.ink)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 30)).foregroundStyle(CareTheme.sage)
                }
            }
            .padding(.horizontal, 28)
            .frame(height: 100)
            .background(selected ? CareTheme.sagePale : .white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(selected ? CareTheme.sage : CareTheme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mood.\(mood.rawValue.lowercased())")
    }
}
