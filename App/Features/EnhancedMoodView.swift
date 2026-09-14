import SwiftUI
import CareCore

/// Enhanced mood recording with optional notes
struct EnhancedMoodView: View {
    @Environment(AppState.self) private var state
    @State private var selectedMood: Mood?
    @State private var note = ""
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 100)

            Text("How are you feeling\ntoday?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .lineSpacing(1)
                .foregroundStyle(CareTheme.ink)

            Text("Tap one face, add a note if you like.")
                .font(.system(size: 18))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 18)
                .padding(.bottom, 32)

            VStack(spacing: 16) {
                moodButton("😊", title: "Great", mood: .great)
                moodButton("😐", title: "Okay", mood: .okay)
                moodButton("😔", title: "Not great", mood: .low)
            }

            if selectedMood != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a note (optional)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CareTheme.secondaryText)

                    TextField("How are things going?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                        .focused($noteFieldFocused)

                    Button {
                        Task {
                            await state.recordMood(selectedMood!, note: note.isEmpty ? nil : note)
                            state.switchToFamily()
                        }
                    } label: {
                        Text("Save Mood")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(CareTheme.background)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedMood)
    }

    private func moodButton(_ emoji: String, title: String, mood: Mood) -> some View {
        Button {
            if selectedMood == mood {
                // If already selected and no note, record immediately
                if note.isEmpty {
                    Task {
                        await state.recordMood(mood)
                        state.switchToFamily()
                    }
                }
            } else {
                selectedMood = mood
                noteFieldFocused = true
            }
        } label: {
            HStack(spacing: 26) {
                Text(emoji).font(.system(size: 42))
                Text(title).font(.system(size: 28, weight: .black))
                Spacer()
                if selectedMood == mood {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(CareTheme.sage)
                }
            }
            .padding(.horizontal, 30)
            .frame(height: 100)
            .background(selectedMood == mood ? CareTheme.sagePale : .white,
                       in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selectedMood == mood ? CareTheme.sage : CareTheme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Family view of mood history with notes
struct MoodHistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var moodEntries: [MoodEntry] {
        state.snapshot.moods
            .filter { $0.seniorID == state.selectedSeniorID }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if moodEntries.isEmpty {
                    ContentUnavailableView(
                        "No Mood Entries",
                        systemImage: "face.smiling",
                        description: Text("Mood entries will appear here")
                    )
                } else {
                    ForEach(moodEntries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.mood.rawValue)
                                    .font(.system(size: 17, weight: .bold))
                                Spacer()
                                Text(entry.date, style: .date)
                                    .font(.system(size: 14))
                                    .foregroundStyle(CareTheme.secondaryText)
                            }

                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 15))
                                    .foregroundStyle(CareTheme.secondaryText)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Mood History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
