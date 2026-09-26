import AVFoundation
import CareCore
import SwiftUI

/// The family's shared conversation. Realtime refresh brings in messages from other devices.
struct MessagesScreen: View {
    @Environment(AppState.self) private var state
    var large = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var isHolding = false
    @State private var isRecording = false
    @State private var recorder = PhoneVoiceRecorder()
    @State private var recordLimit: Task<Void, Never>?
    @State private var player: AVAudioPlayer?
    @State private var playingID: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Messages")
                    .font(.system(size: large ? 32 : 28, weight: .bold))
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
                               message: "Type a note, or hold the microphone to talk. Everyone in \(state.snapshot.account.name) will see it.")
                    .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 22) {
                        ForEach(state.messages) { message in
                            MessageBubble(message: message, isMine: state.isFromCurrentUser(message),
                                          sender: state.senderName(for: message),
                                          senderColor: MessageMemberColor.color(for: message.senderProfileID),
                                          large: large,
                                          status: state.isFromCurrentUser(message) ? (state.isSeen(message) ? "Seen" : "Sent") : nil,
                                          isPlaying: playingID == message.id) {
                                play(message)
                            }
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
            }

            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 10) {
                    voiceButton
                    if isRecording {
                        Text("Listening… let go to send")
                            .font(.system(size: large ? 19 : 16, weight: .bold))
                            .foregroundStyle(CareTheme.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.hairline))
                    } else {
                        TextField("Message", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .font(.system(size: large ? 19 : 16))
                            .focused($inputFocused)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CareTheme.cardStroke))
                            .accessibilityIdentifier("messages.input")
                        Button(action: send) {
                            Image(systemName: isSending ? "ellipsis" : "arrow.up")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: controlSize, height: controlSize)
                                .background(canSend ? CareTheme.action : CareTheme.action.opacity(0.4), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .accessibilityLabel("Send message")
                        .accessibilityIdentifier("messages.send")
                    }
                }
                Text(large ? "Hold the microphone to talk. Let go to send." : "Hold the microphone to send a voice message.")
                    .font(.system(size: large ? 15 : 12, weight: .semibold))
                    .foregroundStyle(CareTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CareTheme.background)
        }
        .background(CareTheme.background)
        .task { await recorder.prepareHostMicrophone() }
        .task(id: state.unseenMessages.map(\.id).joined(separator: ",")) {
            await state.markMessagesRead(state.unseenMessages.map(\.id))
        }
    }

    private var controlSize: CGFloat { large ? 56 : 46 }

    private var voiceButton: some View {
        Button(action: {}) {
            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.system(size: large ? 22 : 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: controlSize, height: controlSize)
                .background(isRecording ? CareTheme.danger : CareTheme.action, in: Circle())
        }
        .buttonStyle(MessageHoldStyle { pressed in
            if pressed {
                guard !isSending, !isHolding else { return }
                isHolding = true
                beginVoice()
            } else if isHolding {
                isHolding = false
                finishVoice()
            }
        })
        .accessibilityLabel("Hold to record a voice message. Let go to send.")
        .accessibilityIdentifier("messages.voice")
    }

    private var canSend: Bool {
        !isSending && !isRecording && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginVoice() {
        recordLimit?.cancel()
        inputFocused = false
        Task {
            let allowed = await recorder.requestPermission()
            guard isHolding else { return }
            guard allowed else {
                isHolding = false
                state.showToast("Turn on the microphone for CareCompanion in Settings.")
                return
            }
            do {
                try recorder.start()
                isRecording = true
                recordLimit = Task {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, isHolding else { return }
                    isHolding = false
                    finishVoice()
                }
            } catch {
                isHolding = false
                isRecording = false
                state.showToast("Couldn't start the recording.")
            }
        }
    }

    private func finishVoice() {
        recordLimit?.cancel()
        guard isRecording || recorder.isRecording else { return }
        isRecording = false
        switch recorder.stop() {
        case .tooShort:
            state.showToast("Hold a little longer, then let go.")
        case .silence:
            #if targetEnvironment(simulator)
            state.showToast("No sound was recorded. Turn on Xcode under Mac Settings, Privacy & Security, Microphone, then try again.")
            #else
            state.showToast("The microphone didn't hear anything. Hold it closer and try again.")
            #endif
        case .clip(let data):
            Task {
                isSending = true
                await state.sendVoiceMessage(data)
                isSending = false
            }
        }
    }

    private func play(_ message: CareMessage) {
        guard let path = message.audioPath else { return }
        if playingID == message.id {
            player?.stop()
            playingID = nil
            return
        }
        Task {
            guard let data = await state.voiceAudio(path: path) else {
                state.showToast("Couldn't play that message.")
                return
            }
            guard data.count > 400 else {
                state.showToast("That recording has no sound.")
                return
            }
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("play-\(message.id).m4a")
            do {
                try data.write(to: url, options: .atomic)
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.volume = 1
                guard audio.duration > 0.2, audio.prepareToPlay(), audio.play() else {
                    state.showToast("That recording has no sound.")
                    return
                }
                player = audio
                playingID = message.id
            } catch {
                state.showToast("Couldn't play that message.")
            }
        }
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

private struct MessageHoldStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPress(pressed)
            }
    }
}

private enum VoiceCapture {
    case clip(Data)
    case tooShort
    case silence
}

@MainActor
private final class PhoneVoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var started: Date?
    private var meterTask: Task<Void, Never>?
    private var loudest: Float = -160
    var isRecording: Bool { recorder?.isRecording == true }

    /// Opens the microphone once Messages appears so the Mac can ask for access. The prompt names Xcode, not CareCompanion.
    func prepareHostMicrophone() async {
        guard await requestPermission() else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
    }

    func requestPermission() async -> Bool {
        let application = AVAudioApplication.shared
        if application.recordPermission == .granted { return true }
        if application.recordPermission == .denied { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) ?? session.availableInputs?.first {
            try session.setPreferredInput(mic)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
        fileURL = url
        started = Date()
        loudest = -160
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.sampleLevel()
            }
        }
    }

    private func sampleLevel() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        loudest = max(loudest, recorder.peakPower(forChannel: 0))
    }

    func stop() -> VoiceCapture {
        meterTask?.cancel()
        meterTask = nil
        sampleLevel()
        let elapsed = started.map { Date().timeIntervalSince($0) } ?? 0
        let heard = loudest
        recorder?.stop()
        recorder = nil
        defer {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            self.fileURL = nil
        }
        guard elapsed >= 0.4, let fileURL, let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return .tooShort }
        // Digital silence stays near -160 dB. Speech is much louder.
        guard heard > -50 else { return .silence }
        return .clip(data)
    }
}

/// One theme color per person, stable for that profile, readable in light and dark.
private enum MessageMemberColor {
    private static let palette: [Color] = [
        CareTheme.sageDark, CareTheme.coralDark, CareTheme.blue, CareTheme.goldDark, CareTheme.heading
    ]

    static func color(for profileID: String?) -> Color {
        let key = profileID ?? "member"
        var total = 0
        for byte in key.utf8 { total = (total + Int(byte)) % palette.count }
        return palette[total]
    }
}

private struct MessageBubble: View {
    let message: CareMessage
    let isMine: Bool
    let sender: String
    let senderColor: Color
    let large: Bool
    var status: String? = nil
    var isPlaying = false
    var onPlay: () -> Void = {}

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
                Text(sender)
                    .font(.system(size: large ? 17 : 15, weight: .bold))
                    .foregroundStyle(senderColor)
                if message.audioPath != nil {
                    Button(action: onPlay) {
                        Label(isPlaying ? "Playing" : "Voice message", systemImage: isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: large ? 19 : 16, weight: .bold))
                            .foregroundStyle(isMine ? .white : CareTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(isMine ? CareTheme.action : CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isMine ? .clear : CareTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPlaying ? "Stop voice message" : "Play voice message")
                } else {
                    Text(message.body)
                        .font(.system(size: large ? 19 : 16))
                        .foregroundStyle(isMine ? .white : CareTheme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isMine ? CareTheme.action : CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isMine ? .clear : CareTheme.cardStroke))
                }
                HStack(spacing: 6) {
                    Text(message.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    if let status {
                        Text(status)
                            .fontWeight(.bold)
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                }
                .font(.system(size: large ? 13 : 11, weight: .semibold))
                .foregroundStyle(CareTheme.secondaryText)
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.audioPath == nil ? "\(sender): \(message.body)" : "\(sender): voice message")
        .accessibilityValue(status ?? "")
    }
}
