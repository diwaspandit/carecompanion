import AVFoundation
import CareCore
import SwiftUI
import WatchKit

struct WatchRootView: View {
    @Environment(WatchSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        WatchCanvas { _ in
            switch session.phase {
            case .notConfigured:
                WatchMessage(title: "Not ready", detail: "Add the account settings, then rebuild.")
                    .scrollDisabled(true)
            case .launching, .loading:
                ProgressView("Loading")
                    .tint(WatchColor.sage)
                    .scrollDisabled(true)
            case .waitingForPhone:
                WatchMessage(title: "Open iPhone", detail: "Sign in as the senior on the iPhone paired with this watch.")
                    .scrollDisabled(true)
            case .needsPhoneSetup(let message):
                WatchMessage(title: "Finish on iPhone", detail: message)
                    .scrollDisabled(true)
            case .failed(let message):
                WatchMessage(title: "Couldn't load", detail: message, retry: { await session.retry() })
                    .scrollDisabled(true)
            case .ready:
                if let state = session.appState {
                    WatchCareView()
                        .environment(state)
                }
            }
        }
        .preferredColorScheme(WatchAppearance.shared.forced)
        .task { await session.start() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await session.refreshIfReady() }
        }
        .overlay { WatchDoseAlert() }
    }
}

private enum WatchPage {
    case home, mood, upcoming, talk, inbox, sos
}

private struct WatchCareView: View {
    @Environment(WatchSession.self) private var session
    @Environment(AppState.self) private var state
    @State private var page: WatchPage = .home
    @State private var moodNudge = Int(Date().timeIntervalSince1970) % 3
    @State private var didShowHome = false
    @State private var moodPrompt = MoodPromptAlert.shared

    var body: some View {
        ZStack {
            switch page {
            case .home: home
            case .mood: WatchMoodPage { page = .home }
            case .upcoming: WatchUpcomingPage { page = .home }
            case .talk: WatchTalkPage(openInbox: { page = .inbox }) { page = .home }
            case .inbox: WatchInboxPage { page = .talk }
            case .sos: WatchSOSPage { page = .home }
            }
            if moodPrompt.isShowing {
                WatchMoodPrompt()
            }
            if let toast = state.toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WatchColor.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(WatchColor.card, in: Capsule())
                }
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if state.toastMessage == toast { state.clearToast() }
                }
            }
        }
        .scrollDisabled(page != .inbox)
        .simultaneousGesture(backSwipe)
        .onChange(of: session.homeRequest) { _, _ in
            page = .home
        }
        .onChange(of: state.snapshot) { _, _ in
            Task { await MedicationReminderCenter.shared.sync(from: state) }
        }
    }

    /// A rightward swipe from the left edge returns to the page this one opened from.
    private var backSwipe: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard !moodPrompt.isShowing, page != .home else { return }
                let fromEdge = value.startLocation.x < 36
                let swipedBack = value.translation.width > 48
                let sideways = abs(value.translation.width) > abs(value.translation.height)
                guard fromEdge, swipedBack, sideways else { return }
                switch page {
                case .inbox: page = .talk
                case .mood, .upcoming, .talk, .sos: page = .home
                case .home: break
                }
            }
    }

    private var home: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 10
            let header: CGFloat = 38
            let tileW = (proxy.size.width - gap) / 2
            let tileH = max(56, (proxy.size.height - header - gap - 6) / 2)
            let side = min(tileW, tileH)
            VStack(spacing: 6) {
                VStack(spacing: 1) {
                    Text(personName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WatchColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Button {
                        if !state.hasEmergency { page = .mood }
                    } label: {
                        Text(moodLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WatchColor.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watch.mood.status")
                }
                .frame(maxWidth: .infinity)
                .frame(height: header)
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        homeTile("face.smiling", WatchColor.sage, "Mood", "watch.mood", emoji: moodEmoji, chosen: state.currentMood != nil) { page = .mood }
                        homeTile("bell.fill", WatchColor.gold, "New", "watch.new", dot: !state.unseenMessages.isEmpty) { page = .upcoming }
                    }
                    HStack(spacing: gap) {
                        homeTile("mic.fill", WatchColor.blue, "Talk", "watch.talk", dot: !state.unseenMessages.isEmpty) { page = .talk }
                        homeTile(state.hasEmergency ? "checkmark" : "exclamationmark", state.hasEmergency ? WatchColor.sage : WatchColor.coral, state.hasEmergency ? "Sent" : "SOS", "watch.sos", alert: !state.hasEmergency) { page = .sos }
                    }
                }
                .frame(width: side * 2 + gap, height: side * 2 + gap)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onAppear {
            if didShowHome { moodNudge = (moodNudge + 1) % 3 }
            didShowHome = true
        }
    }

    /// Same faces as the senior's iPhone home screen.
    private var moodEmoji: String {
        switch state.currentMood {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        case nil: "🙂"
        }
    }

    private func homeTile(_ symbol: String, _ tint: Color, _ title: String, _ identifier: String, emoji: String? = nil, chosen: Bool = false, dot: Bool = false, alert: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                if let emoji {
                    Text(emoji)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(alert ? WatchColor.coralDark : WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(chosen ? WatchColor.sagePale : WatchColor.card, in: Circle())
            .overlay {
                Circle()
                    .stroke(chosen ? WatchColor.sage : WatchColor.hairline, lineWidth: chosen ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if dot {
                    Circle()
                        .fill(WatchColor.coral)
                        .frame(width: 8, height: 8)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityIdentifier(identifier)
    }

    private var personName: String {
        let name = state.linkedSenior?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "there" : name
    }

    private var moodLine: String {
        if state.hasEmergency { return "Family has your SOS" }
        let index = moodNudge % 3
        switch state.currentMood {
        case .great:
            return ["Feeling good", "Still feeling good?", "Feeling good today?"][index]
        case .okay:
            return ["Feeling okay", "Still feeling okay?", "Feeling okay today?"][index]
        case .low:
            return ["Not feeling great", "Still not feeling great?", "Not great today?"][index]
        case nil:
            return ["How are you?", "Tap Mood", "Tell your family"][index]
        }
    }
}

private struct WatchMoodPage: View {
    @Environment(AppState.self) private var state
    var back: () -> Void
    @State private var isSaving = false

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 10
            let chrome: CGFloat = 62
            let tile = min((proxy.size.width - gap) / 2, max(52, (proxy.size.height - chrome - gap) / 2))
            VStack(spacing: 6) {
                WatchBackButton(action: back)
                    .frame(height: 28)
                Text("How are you?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        moodButton("😊", "Good", mood: .great)
                        moodButton("😐", "Okay", mood: .okay)
                    }
                    HStack(spacing: gap) {
                        moodButton("😔", "Not great", mood: .low)
                    }
                }
                .frame(width: tile * 2 + gap, height: tile * 2 + gap)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func moodButton(_ emoji: String, _ title: String, mood: Mood) -> some View {
        let selected = state.currentMood == mood
        return Button {
            guard !isSaving else { return }
            Task {
                isSaving = true
                if await state.recordMood(mood) { back() }
                isSaving = false
            }
        } label: {
            VStack(spacing: 1) {
                Text(emoji)
                    .font(.system(size: 28))
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(selected ? WatchColor.sagePale : WatchColor.card, in: Circle())
            .overlay {
                Circle()
                    .stroke(selected ? WatchColor.sage : WatchColor.hairline, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("watch.mood.\(mood.rawValue.lowercased())")
    }
}

private struct WatchUpcomingPage: View {
    @Environment(AppState.self) private var state
    var back: () -> Void
    @State private var shownMessage: CareMessage?
    @State private var isSavingDose = false

    private enum NewEntry: Identifiable {
        case message(CareMessage)
        case medicine(Medication)
        case visit(Appointment)

        var id: String {
            switch self {
            case .message(let message): "message-\(message.id)"
            case .medicine(let medication): "medicine-\(medication.id)"
            case .visit(let visit): "visit-\(visit.id)"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 8) {
                WatchBackButton(action: back)
                if entries.isEmpty {
                    Spacer(minLength: 0)
                    Text("Nothing new")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(WatchColor.ink)
                    Text("A new message, medicine, or visit shows here.")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WatchColor.secondary)
                        .multilineTextAlignment(.center)
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(entries) { entry in
                                newCard(entry)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .task {
            if shownMessage == nil { shownMessage = state.unseenMessages.last }
            if let shownMessage { await state.markMessagesRead([shownMessage.id]) }
        }
    }

    private var entries: [NewEntry] {
        var rows: [NewEntry] = []
        if let shownMessage { rows.append(.message(shownMessage)) }
        rows.append(contentsOf: scheduledEntries)
        return rows
    }

    /// The next medicine and the next visit, sooner first. One of each.
    private var scheduledEntries: [NewEntry] {
        var dated: [(Date, NewEntry)] = []
        if let medicine = nextMedicine { dated.append((doseDate(medicine), .medicine(medicine))) }
        if let visit = nextVisit { dated.append((visit.date, .visit(visit))) }
        return dated.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private var nextMedicine: Medication? {
        let zone = TimeZone(identifier: state.selectedSenior?.timeZoneIdentifier ?? "") ?? .current
        return state.medications.filter { medication in
            !medication.taken && CareSchedule.medicationIsDue(medication, on: Date(), timeZone: zone)
        }.min { doseDate($0) < doseDate($1) }
    }

    private var nextVisit: Appointment? {
        let zone = TimeZone(identifier: state.selectedSenior?.timeZoneIdentifier ?? "") ?? .current
        return state.appointments.compactMap { visit -> Appointment? in
            guard let next = CareSchedule.nextOccurrence(of: visit, after: Date(), timeZone: zone) else { return nil }
            var showing = visit
            showing.date = next
            return showing
        }.min { $0.date < $1.date }
    }

    @ViewBuilder
    private func newCard(_ entry: NewEntry) -> some View {
        switch entry {
        case .message(let message):
            infoCard(label: "Message", title: state.senderName(for: message),
                     detail: message.audioPath == nil ? message.body : "Voice message")
        case .medicine(let medication):
            medicineCard(medication)
        case .visit(let visit):
            kindCard(label: "Visit", icon: "calendar", title: visit.title, detail: visitDetail(visit),
                     fill: WatchColor.bluePale, stroke: WatchColor.blue, labelColor: WatchColor.blue)
        }
    }

    private func kindCard(label: String, icon: String, title: String, detail: String, fill: Color, stroke: Color, labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(labelColor)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stroke, lineWidth: 1.5)
        }
        .accessibilityIdentifier("watch.new.\(label.lowercased())")
    }

    private func infoCard(label: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchColor.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(WatchColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WatchColor.hairline, lineWidth: 1)
        }
    }

    private func medicineCard(_ medication: Medication) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Medicine", systemImage: "pills.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WatchColor.goldDark)
                Text(medication.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                let detail = medicineDetail(medication)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WatchColor.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { markTaken(medication) } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WatchColor.sageDark)
                    .opacity(isSavingDose ? 1 : 0)
                    .frame(width: 36, height: 36)
                    .background(WatchColor.tickFill, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(WatchColor.tickStroke, lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isSavingDose)
            .accessibilityLabel("Mark \(medication.name) taken")
            .accessibilityIdentifier("watch.new.taken")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(WatchColor.goldPale, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WatchColor.gold, lineWidth: 1.5)
        }
        .accessibilityIdentifier("watch.new.medicine")
    }

    private func markTaken(_ medication: Medication) {
        Task {
            isSavingDose = true
            await MedicationReminderCenter.shared.markDoseTaken(id: medication.id, name: medication.name, dosage: medication.dosage)
            isSavingDose = false
        }
    }

    private func medicineDetail(_ medication: Medication) -> String {
        [medication.scheduledTime, medication.dosage].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func visitDetail(_ visit: Appointment) -> String {
        let zone = TimeZone(identifier: state.linkedSenior?.timeZoneIdentifier ?? "") ?? .current
        let when = visit.date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day().hour().minute())
        return [when, visit.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func doseDate(_ medication: Medication) -> Date {
        let zone = TimeZone(identifier: state.linkedSenior?.timeZoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let clock = Self.clockMinutes(medication.scheduledTime)
        var parts = calendar.dateComponents([.year, .month, .day], from: Date())
        parts.hour = clock / 60
        parts.minute = clock % 60
        return calendar.date(from: parts) ?? Date()
    }

    private static func clockMinutes(_ scheduledTime: String) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: scheduledTime.uppercased()) else { return 24 * 60 }
        let parts = formatter.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 24) * 60 + (parts.minute ?? 0)
    }
}

private struct WatchTalkPage: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    var openInbox: () -> Void
    var back: () -> Void
    @State private var recorder = WatchVoiceRecorder()
    @State private var phase: Phase = .ready
    @State private var isHolding = false
    @State private var failedClip: Data?
    @State private var limit: Task<Void, Never>?

    private enum Phase { case asking, ready, recording, sending, sent, tooShort, denied, failed }

    var body: some View {
        GeometryReader { proxy in
            let circle = min(proxy.size.width * 0.4, max(48, proxy.size.height - (caregiver == nil ? 72 : 156)))
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    WatchBackButton(action: back)
                }
                Text(headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WatchColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 10) {
                    messageButton(diameter: circle * 0.72)
                    recordButton(diameter: circle)
                }
                if let caregiver {
                    VStack(spacing: 6) {
                        if let url = Self.phoneURL(caregiver.phone) {
                            contactButton("Call", "phone.fill", url, identifier: "watch.talk.call")
                        }
                        if let url = Self.faceTimeURL(caregiver.phone) {
                            contactButton("FaceTime", "video.fill", url, identifier: "watch.talk.facetime")
                        }
                    }
                }
                Spacer(minLength: 0)
                if phase == .failed, failedClip != nil {
                    Button("Send again") { Task { await send(failedClip) } }
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WatchColor.sageDark)
                        .accessibilityIdentifier("watch.talk.retry")
                } else {
                    Text(hint)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WatchColor.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task { await askForMicrophone() }
    }

    private func messageButton(diameter: CGFloat) -> some View {
        Button {
            openInbox()
            WatchPhoneOpener.openMessages()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: diameter * 0.42, weight: .semibold))
                    .foregroundStyle(WatchColor.sageDark)
                    .frame(width: diameter, height: diameter)
                    .overlay {
                        Circle()
                            .stroke(WatchColor.sageDark, lineWidth: 2)
                    }
                if !state.unseenMessages.isEmpty {
                    Circle()
                        .fill(WatchColor.coral)
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.unseenMessages.isEmpty ? "Messages" : "New messages")
        .accessibilityIdentifier("watch.talk.inbox")
    }

    private func recordButton(diameter: CGFloat) -> some View {
        Button(action: {}) {
            Circle()
                .fill(phase == .recording ? WatchColor.coralDark : WatchColor.sageDark)
                .overlay {
                    Image(systemName: phase == .recording ? "waveform" : "mic.fill")
                        .font(.system(size: diameter * 0.34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(WatchHoldStyle { pressed in
            if pressed {
                guard phase != .sending, phase != .asking, !isHolding else { return }
                isHolding = true
                begin()
            } else if isHolding {
                isHolding = false
                finish()
            }
        })
        .accessibilityLabel("Hold to record, let go to send")
        .accessibilityIdentifier("watch.talk.record")
    }

    /// The earliest family member with a phone number. Members arrive oldest first.
    private var caregiver: AccountMember? {
        state.snapshot.members.first {
            $0.role == .family && $0.profileID != state.currentProfileID && Self.faceTimeURL($0.phone) != nil
        }
    }

    private func contactButton(_ title: String, _ icon: String, _ url: URL, identifier: String) -> some View {
        let busy = phase == .recording || phase == .sending
        return Button {
            guard !busy else { return }
            openURL(url)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WatchColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(WatchColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WatchColor.hairline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private static func phoneURL(_ phone: String) -> URL? {
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard allowed.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(allowed)")
    }

    private static func faceTimeURL(_ phone: String) -> URL? {
        let allowed = phone.filter { $0.isNumber || $0 == "+" }
        guard allowed.contains(where: \.isNumber) else { return nil }
        return URL(string: "facetime:\(allowed)")
    }

    private var headline: String {
        switch phase {
        case .asking: "Allow microphone"
        case .ready: "Hold to talk"
        case .recording: "Listening"
        case .sending: "Sending"
        case .sent: "Sent"
        case .tooShort: "Hold longer"
        case .denied: "Microphone off"
        case .failed: "Not sent"
        }
    }

    private var hint: String {
        switch phase {
        case .asking: "The watch will ask before it can hear you."
        case .ready, .sent: "Let go and it goes to your family."
        case .recording: "Let go to send."
        case .sending: "One moment."
        case .tooShort: "Press and hold, then let go."
        case .denied:
            #if targetEnvironment(simulator)
            "This simulator has no microphone, so your Mac cannot allow it."
            #else
            "Turn it on in the Watch app on your iPhone."
            #endif
        case .failed: "Hold to try again."
        }
    }

    private func askForMicrophone() async {
        phase = .asking
        let allowed = await recorder.requestPermission()
        if phase == .asking { phase = allowed ? .ready : .denied }
    }

    private func begin() {
        limit?.cancel()
        Task {
            let allowed = await recorder.requestPermission()
            guard isHolding else { return }
            guard allowed else {
                phase = .denied
                isHolding = false
                return
            }
            do {
                try recorder.start()
                phase = .recording
                limit = Task {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled, isHolding else { return }
                    isHolding = false
                    finish()
                }
            } catch {
                phase = .failed
                isHolding = false
            }
        }
    }

    private func finish() {
        limit?.cancel()
        guard phase == .recording || recorder.isRecording else { return }
        guard let data = recorder.stop() else {
            phase = .tooShort
            return
        }
        Task { await send(data) }
    }

    private func send(_ data: Data?) async {
        guard let data, phase != .sending else { return }
        phase = .sending
        if await state.sendVoiceMessage(data) {
            failedClip = nil
            phase = .sent
            try? await Task.sleep(for: .seconds(1.2))
            if phase == .sent { back() }
        } else {
            failedClip = data
            phase = .failed
        }
    }
}

private struct WatchInboxPage: View {
    @Environment(AppState.self) private var state
    var back: () -> Void
    @State private var shown: [CareMessage] = []
    @State private var player: AVAudioPlayer?
    @State private var playingID: String?

    var body: some View {
        VStack(spacing: 6) {
            WatchBackButton(title: "Talk", action: back)
            Text(shown.isEmpty ? "No messages" : "Messages")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(WatchColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if shown.isEmpty {
                Spacer(minLength: 0)
                Text("Notes from your family show here.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchColor.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(shown) { message in
                            inboxCard(message)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            if shown.isEmpty { shown = Array(state.messages.suffix(5).reversed()) }
            await state.markMessagesRead(shown.map(\.id))
        }
    }

    private func inboxCard(_ message: CareMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.senderName(for: message))
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WatchColor.sageDark)
                .lineLimit(1)
            if message.audioPath != nil {
                Text("Voice message")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                Button {
                    Task { await play(message) }
                } label: {
                    Label(playingID == message.id ? "Stop" : "Play", systemImage: playingID == message.id ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(WatchColor.sageDark, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playingID == message.id ? "Stop voice message" : "Play voice message")
                .accessibilityIdentifier("watch.inbox.play.\(message.id)")
            } else {
                Text(message.body)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            Text(message.date.formatted(.dateTime.hour().minute()))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WatchColor.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(WatchColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WatchColor.cardStroke, lineWidth: 1.5)
        }
    }

    private func play(_ message: CareMessage) async {
        guard let path = message.audioPath else { return }
        if playingID == message.id {
            player?.stop()
            playingID = nil
            return
        }
        guard let data = await state.voiceAudio(path: path), data.count > 400 else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-play-\(message.id).m4a")
        do {
            try data.write(to: url, options: .atomic)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.volume = 1
            guard audio.prepareToPlay(), audio.play() else { return }
            player = audio
            playingID = message.id
        } catch {
            playingID = nil
        }
    }
}

private struct WatchSOSPage: View {
    @Environment(AppState.self) private var state
    var back: () -> Void
    @State private var isSending = false
    @State private var didSend = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 6) {
                WatchBackButton(action: back)
                Text(didSend || state.hasEmergency ? "Family alerted" : "Need help?")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WatchColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                Text(didSend || state.hasEmergency ? "Your family has your SOS." : "Or say: Send SOS in CareCompanion.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WatchColor.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if !didSend {
                    Button {
                        guard !isSending else { return }
                        Task {
                            isSending = true
                            didSend = await state.triggerSOS()
                            isSending = false
                        }
                    } label: {
                        Text(isSending ? "Sending" : (state.hasEmergency ? "Send again" : "Send SOS"))
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(WatchColor.coralDark, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .accessibilityIdentifier("watch.sos.send")
                }
                Button(didSend || state.hasEmergency ? "Home" : "Cancel", action: back)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WatchColor.ink)
                    .accessibilityIdentifier("watch.sos.cancel")
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}

private struct WatchHoldStyle: ButtonStyle {
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPress(pressed)
            }
    }
}

private struct WatchBackButton: View {
    var title: String = "Home"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "chevron.left")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WatchColor.sageDark)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("watch.back")
    }
}

private struct WatchMessage: View {
    let title: String
    let detail: String
    var retry: (() async -> Void)?
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(WatchColor.ink)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WatchColor.secondary)
                .multilineTextAlignment(.center)
            if retry != nil {
                Button(isRetrying ? "Trying" : "Try again") {
                    guard !isRetrying, let retry else { return }
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                }
                .font(.system(size: 16, weight: .black))
                .buttonStyle(.borderedProminent)
                .tint(WatchColor.sage)
                .accessibilityIdentifier("watch.retry")
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class WatchVoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var started: Date?
    var isRecording: Bool { recorder?.isRecording == true }

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
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        guard recorder.record() else { throw CocoaError(.fileWriteUnknown) }
        self.recorder = recorder
        fileURL = url
        started = Date()
    }

    func stop() -> Data? {
        let elapsed = started.map { Date().timeIntervalSince($0) } ?? 0
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            self.fileURL = nil
        }
        guard elapsed >= 0.4, let fileURL, let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        return data
    }
}

/// Fills the square watch face and keeps the controls inside the rounded corners.
private struct WatchCanvas<Content: View>: View {
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        let bounds = WKInterfaceDevice.current().screenBounds.size
        let inset = EdgeInsets(top: 18, leading: 14, bottom: 16, trailing: 14)
        let inner = CGSize(
            width: bounds.width - inset.leading - inset.trailing,
            height: bounds.height - inset.top - inset.bottom
        )
        content(inner)
            .frame(width: inner.width, height: inner.height)
            .padding(inset)
            .frame(width: bounds.width, height: bounds.height)
            .background(WatchColor.background)
            .clipped()
            .ignoresSafeArea()
    }
}

@MainActor
private enum WatchColor {
    static var background: Color { pick(rgb(250, 250, 247), rgb(28, 28, 26)) }
    static var card: Color { pick(.white, rgb(44, 44, 41)) }
    static var ink: Color { pick(rgb(43, 43, 43), rgb(245, 244, 240)) }
    static var secondary: Color { pick(rgb(132, 132, 132), rgb(176, 174, 168)) }
    static var sage: Color { pick(rgb(112, 160, 124), rgb(138, 186, 150)) }
    static var sageDark: Color { pick(rgb(91, 137, 105), rgb(186, 220, 194)) }
    static var sagePale: Color { pick(rgb(220, 242, 225), rgb(36, 58, 44)) }
    static var coral: Color { pick(rgb(231, 125, 105), rgb(232, 140, 122)) }
    static var coralDark: Color { pick(rgb(176, 78, 62), rgb(245, 186, 176)) }
    static var coralPale: Color { pick(rgb(255, 229, 223), rgb(62, 36, 32)) }
    static var cardStroke: Color { pick(Color.black.opacity(0.16), Color.white.opacity(0.16)) }
    static var hairline: Color { pick(Color.black.opacity(0.08), Color.white.opacity(0.12)) }
    static var tickFill: Color { pick(rgb(248, 248, 246), rgb(58, 58, 56)) }
    static var tickStroke: Color { pick(rgb(198, 214, 202), rgb(120, 150, 130)) }
    static var gold: Color { pick(rgb(240, 178, 74), rgb(232, 186, 96)) }
    static var goldDark: Color { pick(rgb(107, 85, 43), rgb(245, 220, 160)) }
    static let onGold = Color(red: 107 / 255, green: 85 / 255, blue: 43 / 255)
    static var goldPale: Color { pick(rgb(255, 244, 218), rgb(58, 46, 28)) }
    static var blue: Color { pick(rgb(86, 159, 205), rgb(126, 186, 220)) }
    static var bluePale: Color { pick(rgb(221, 241, 255), rgb(28, 46, 58)) }

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    private static func pick(_ light: Color, _ dark: Color) -> Color {
        WatchAppearance.shared.scheme == .dark ? dark : light
    }
}

/// Mood check with no way out except choosing one. Choosing clears the prompt on the phone too.
private struct WatchMoodPrompt: View {
    @Environment(AppState.self) private var state
    @State private var prompt = MoodPromptAlert.shared
    @State private var isSaving = false

    var body: some View {
        if prompt.isShowing {
            VStack(spacing: 6) {
                Text("How are you?")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                choice("😊", "Good", .great)
                choice("😐", "Okay", .okay)
                choice("😔", "Not great", .low)
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchColor.background)
        }
    }

    private func choice(_ emoji: String, _ title: String, _ mood: Mood) -> some View {
        Button {
            guard !isSaving else { return }
            Task {
                isSaving = true
                _ = await state.recordMood(mood)
                isSaving = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(emoji).font(.system(size: 22))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WatchColor.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(WatchColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(title)
    }
}

/// One screen for a dose. No scrolling and no way to leave except Taken or Snooze.
private struct WatchDoseAlert: View {
    @Environment(WatchSession.self) private var session
    @State private var alert = MedicationAlert.shared
    @State private var isBusy = false

    var body: some View {
        if alert.medicationID != nil {
            VStack(spacing: 6) {
                Text(alert.name)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WatchColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if !alert.dosage.isEmpty {
                    Text(alert.dosage)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WatchColor.ink.opacity(0.7))
                        .lineLimit(1)
                }
                Button { act(snooze: false) } label: {
                    Label("Taken", systemImage: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(WatchColor.sageDark, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.dose.taken")
                Button { act(snooze: true) } label: {
                    Label("Snooze", systemImage: "clock")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WatchColor.ink)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(WatchColor.card, in: Capsule())
                        .overlay(Capsule().stroke(WatchColor.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.dose.snooze")
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WatchColor.background.ignoresSafeArea())
            .disabled(isBusy)
        }
    }

    private func act(snooze: Bool) {
        Task {
            isBusy = true
            if snooze {
                await MedicationReminderCenter.shared.snoozePresentedDose()
            } else {
                await MedicationReminderCenter.shared.takePresentedDose()
            }
            isBusy = false
            session.returnHome()
        }
    }
}
