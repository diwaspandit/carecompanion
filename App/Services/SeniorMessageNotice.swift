import AVFoundation
import CareCore
import Intents
import UIKit
import UserNotifications

/// A family message on the senior's iPhone. The alert shows that person's picture and their latest
/// note. A tap opens Messages for text, or plays a voice message and then clears it.
enum SeniorMessageNotice {
    static let kind = "message"
    private static let idPrefix = "message.sender."
    private static let notifiedKey = "care.message.notified"
    private static let pendingIDKey = "care.message.pending.id"
    private static let pendingAudioKey = "care.message.pending.audio"

    static func isMessage(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == kind
    }

    /// True when this device already built the alert, so the banner should stay.
    static func shouldDisplay(_ info: [AnyHashable: Any]) -> Bool {
        (info["rich"] as? String) == "1"
    }

    @MainActor
    static func sync(_ state: AppState) async {
        guard state.role == .senior else { return }
        if let pending = takePending() {
            await open(messageID: pending.id, audioPath: pending.audio, state: state)
        }
        await clearRead(keeping: state.unseenMessages.map(\.id))
        guard state.seniorTab != .messages else { return }
        let latest = Dictionary(grouping: state.unseenMessages, by: { $0.senderProfileID ?? $0.id })
            .compactMapValues { $0.max { $0.date < $1.date } }
        for message in latest.values {
            guard !wasNotified(message.id) else { continue }
            guard Date().timeIntervalSince(message.date) < 7 * 24 * 3600 else {
                rememberNotified(message.id)
                continue
            }
            let name = state.senderName(for: message)
            await post(messageID: message.id, senderID: message.senderProfileID ?? message.id, name: name,
                       body: message.audioPath == nil ? message.body : "Voice message",
                       audioPath: message.audioPath ?? "")
        }
    }

    /// A plain remote alert is replaced by one that carries the sender's picture.
    @MainActor
    static func enrichRemote(messageID: String, senderID: String, senderName: String, body: String, audioPath: String, state: AppState?) async {
        guard !messageID.isEmpty, !wasNotified(messageID) else { return }
        let trimmed = senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? (state?.senderName(forMessageID: messageID) ?? "Family") : trimmed
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        await post(messageID: messageID, senderID: senderID.isEmpty ? messageID : senderID, name: resolved,
                   body: text.isEmpty ? "New message" : text, audioPath: audioPath)
    }

    @MainActor
    static func open(messageID: String, audioPath: String, state: AppState?) async {
        guard !messageID.isEmpty else { return }
        guard let state else {
            remember(messageID: messageID, audioPath: audioPath)
            return
        }
        if !audioPath.isEmpty {
            guard let data = await state.voiceAudio(path: audioPath), MessageVoicePlayer.shared.play(data: data, done: {
                Task { @MainActor in
                    await state.markMessagesRead([messageID])
                    await remove(messageID: messageID)
                }
            }) else {
                state.showToast("Couldn't play that message.")
                state.seniorTab = .messages
                await state.markMessagesRead([messageID])
                await remove(messageID: messageID)
                return
            }
            return
        }
        state.seniorTab = .messages
        await state.markMessagesRead([messageID])
        await remove(messageID: messageID)
    }

    private static func post(messageID: String, senderID: String, name: String, body: String, audioPath: String) async {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = body
        content.sound = .default
        content.threadIdentifier = idPrefix + senderID
        content.categoryIdentifier = "carecompanion.message"
        content.userInfo = [
            "kind": kind,
            "rich": "1",
            "messageID": messageID,
            "senderID": senderID,
            "senderName": name,
            "body": body,
            "audioPath": audioPath
        ]
        let picture = avatarData(name: name)
        MedicationReminderCenter.forwardMessageToWatch(
            messageID: messageID, name: name, body: body, audioPath: audioPath, image: picture)
        if let data = picture {
            content.attachments = [avatarAttachment(data: data, senderID: senderID)].compactMap { $0 }
            if let styled = communicationContent(content, name: name, body: body, senderID: senderID, image: data),
               !styled.attachments.isEmpty {
                let request = UNNotificationRequest(identifier: idPrefix + senderID, content: styled, trigger: nil)
                await deliver(request, messageID: messageID)
                return
            }
        }
        let request = UNNotificationRequest(identifier: idPrefix + senderID, content: content, trigger: nil)
        await deliver(request, messageID: messageID)
    }

    private static func deliver(_ request: UNNotificationRequest, messageID: String) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
        do {
            try await center.add(request)
            rememberNotified(messageID)
        } catch {}
    }

    private static func clearRead(keeping ids: [String]) async {
        let keep = Set(ids)
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let staleDelivered = delivered.filter { note in
            guard isMessage(note.request.content.userInfo) else { return false }
            let id = note.request.content.userInfo["messageID"] as? String ?? ""
            return !keep.contains(id)
        }.map(\.request.identifier)
        let stalePending = pending.filter { request in
            guard isMessage(request.content.userInfo) else { return false }
            let id = request.content.userInfo["messageID"] as? String ?? ""
            return !keep.contains(id)
        }.map(\.identifier)
        center.removeDeliveredNotifications(withIdentifiers: staleDelivered)
        center.removePendingNotificationRequests(withIdentifiers: stalePending)
    }

    static func remove(messageID: String) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let deliveredIDs = delivered.filter { $0.request.content.userInfo["messageID"] as? String == messageID }
            .map(\.request.identifier)
        let pendingIDs = pending.filter { $0.content.userInfo["messageID"] as? String == messageID }
            .map(\.identifier)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIDs)
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
    }

    private static func communicationContent(_ content: UNMutableNotificationContent, name: String, body: String,
                                              senderID: String, image: Data) -> UNNotificationContent? {
        let person = INPerson(personHandle: INPersonHandle(value: senderID, type: .unknown),
                              nameComponents: nil, displayName: name, image: INImage(imageData: image),
                              contactIdentifier: nil, customIdentifier: senderID)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: body,
                                          speakableGroupName: nil, conversationIdentifier: "carecompanion.messages",
                                          serviceName: "CareCompanion", sender: person, attachments: nil)
        intent.setImage(INImage(imageData: image), forParameterNamed: \.sender)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate()
        return try? content.updating(from: intent)
    }

    private static func avatarData(name: String) -> Data? {
        if let portrait = portrait(named: name), let data = portrait.jpegData(compressionQuality: 0.85) {
            return data
        }
        return initialsImage(name: name).jpegData(compressionQuality: 0.9)
    }

    private static func portrait(named name: String) -> UIImage? {
        guard let first = name.split(separator: " ").first else { return nil }
        let asset = "\(first.prefix(1).uppercased())\(first.dropFirst().lowercased())Portrait"
        return UIImage(named: asset)
    }

    private static func initialsImage(name: String) -> UIImage {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.map { String($0.prefix(1)).uppercased() }.joined()
        let initials = letters.isEmpty ? "?" : letters
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(red: 112 / 255, green: 160 / 255, blue: 124 / 255, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: style
            ]
            let text = initials as NSString
            let bounds = text.boundingRect(with: size, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
            text.draw(in: CGRect(x: 0, y: (size.height - bounds.height) / 2, width: size.width, height: bounds.height),
                      withAttributes: attributes)
        }
    }

    private static func avatarAttachment(data: Data, senderID: String) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("care-sender-\(senderID).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "photo", url: url)
        } catch {
            return nil
        }
    }

    private static func wasNotified(_ id: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []).contains(id)
    }

    private static func rememberNotified(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []
        ids.append(id)
        if ids.count > 300 { ids.removeFirst(ids.count - 300) }
        UserDefaults.standard.set(ids, forKey: notifiedKey)
    }

    private static func remember(messageID: String, audioPath: String) {
        UserDefaults.standard.set(messageID, forKey: pendingIDKey)
        UserDefaults.standard.set(audioPath, forKey: pendingAudioKey)
    }

    private static func takePending() -> (id: String, audio: String)? {
        guard let id = UserDefaults.standard.string(forKey: pendingIDKey), !id.isEmpty else { return nil }
        let audio = UserDefaults.standard.string(forKey: pendingAudioKey) ?? ""
        UserDefaults.standard.removeObject(forKey: pendingIDKey)
        UserDefaults.standard.removeObject(forKey: pendingAudioKey)
        return (id, audio)
    }
}

/// A message from the senior, shown on a family member's iPhone. A tap opens the Messages tab.
enum FamilyMessageNotice {
    private static let idPrefix = "message.family."
    private static let notifiedKey = "care.family.message.notified"
    private static let pendingKey = "care.family.message.pending"
    /// Unread messages already on screen at launch are not announced again. Later arrivals are.
    nonisolated(unsafe) private static var primed = false

    static func isFamilyMessage(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == "message" && info["audience"] as? String == "family"
    }

    @MainActor
    static func sync(_ state: AppState) async {
        guard state.role == .family else { return }
        if consumePending() { state.familyTab = .messages }
        if !primed {
            primed = true
            for message in state.unseenMessages { remember(message.id) }
            if state.familyTab == .messages { await removeDelivered() }
            return
        }
        if state.familyTab == .messages {
            for message in state.unseenMessages { remember(message.id) }
            await removeDelivered()
            return
        }
        for message in state.unseenMessages where !wasNotified(message.id) {
            guard Date().timeIntervalSince(message.date) < 7 * 24 * 3600 else {
                remember(message.id)
                continue
            }
            let name = state.senderName(for: message)
            let body = message.audioPath == nil ? message.body : "Voice message"
            await post(messageID: message.id, name: name, body: body)
        }
    }

    static func noteDelivered(_ messageID: String) {
        guard !messageID.isEmpty else { return }
        remember(messageID)
    }

    @MainActor
    static func open(messageID: String, state: AppState?) async {
        if !messageID.isEmpty { remember(messageID) }
        await remove(messageID: messageID)
        guard let state else {
            UserDefaults.standard.set(true, forKey: pendingKey)
            return
        }
        state.familyTab = .messages
    }

    private static func post(messageID: String, name: String, body: String) async {
        let content = UNMutableNotificationContent()
        let who = name.trimmingCharacters(in: .whitespacesAndNewlines)
        content.title = who.isEmpty || who == "You" ? "New message" : "\(who) sent a message"
        content.body = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New message" : body
        content.sound = .default
        content.categoryIdentifier = "carecompanion.message"
        content.threadIdentifier = "family.messages"
        content.userInfo = [
            "kind": "message",
            "audience": "family",
            "messageID": messageID,
            "body": content.body
        ]
        let request = UNNotificationRequest(identifier: idPrefix + messageID, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
        do {
            try await center.add(request)
            remember(messageID)
        } catch {}
    }

    private static func remove(messageID: String) async {
        guard !messageID.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { $0.request.content.userInfo["messageID"] as? String == messageID }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids + [idPrefix + messageID])
    }

    private static func removeDelivered() async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { isFamilyMessage($0.request.content.userInfo) }.map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func consumePending() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return false }
        UserDefaults.standard.set(false, forKey: pendingKey)
        return true
    }

    private static func wasNotified(_ id: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []).contains(id)
    }

    private static func remember(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > 300 { ids.removeFirst(ids.count - 300) }
        UserDefaults.standard.set(ids, forKey: notifiedKey)
    }
}

/// A mood update or a medicine marked taken, shown on a family member's iPhone. A tap opens Home.
enum FamilyCareNotice {
    private static let notifiedKey = "care.family.care.notified"
    private static let pendingKey = "care.family.care.pending"
    nonisolated(unsafe) private static var primed = false

    static func isFamilyUpdate(_ info: [AnyHashable: Any]) -> Bool {
        guard info["audience"] as? String == "family" else { return false }
        let kind = info["kind"] as? String
        return kind == "mood" || kind == "medication"
    }

    /// True the first time this update is shown, so a push and a live alert do not both banner.
    static func claim(_ activityID: String) -> Bool {
        if activityID.isEmpty { return true }
        if wasNotified(activityID) { return false }
        remember(activityID)
        return true
    }

    @MainActor
    static func sync(_ state: AppState) async {
        guard state.role == .family else { return }
        if consumePending() { state.familyTab = .dashboard }
        let moods = state.snapshot.moods
        let taken = state.snapshot.medicationEvents.filter { $0.status == .taken }
        if !primed {
            primed = true
            for mood in moods { remember(mood.id) }
            for event in taken { remember(event.id) }
            return
        }
        let now = Date()
        for mood in moods where !wasNotified(mood.id) {
            guard now.timeIntervalSince(mood.date) < 3 * 60 else {
                remember(mood.id)
                continue
            }
            await post(id: mood.id, kind: "mood", title: "\(seniorName(mood.seniorID, state: state)) updated their mood",
                       body: moodText(mood))
        }
        for event in taken where !wasNotified(event.id) {
            guard now.timeIntervalSince(event.date) < 3 * 60 else {
                remember(event.id)
                continue
            }
            await post(id: event.id, kind: "medication",
                       title: "\(seniorName(event.seniorID, state: state)) took their medicine",
                       body: medicineText(event, state: state))
        }
    }

    @MainActor
    static func open(activityID: String, state: AppState?) async {
        if !activityID.isEmpty { remember(activityID) }
        await remove(activityID: activityID)
        guard let state else {
            UserDefaults.standard.set(true, forKey: pendingKey)
            return
        }
        state.familyTab = .dashboard
    }

    private static func post(id: String, kind: String, title: String, body: String) async {
        guard !wasNotified(id) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "family.\(kind)"
        content.userInfo = ["kind": kind, "audience": "family", "activityID": id, "body": body]
        let request = UNNotificationRequest(identifier: "family.\(kind).\(id)", content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            remember(id)
        } catch {}
    }

    private static func moodText(_ mood: MoodEntry) -> String {
        let feeling: String
        switch mood.mood {
        case .great: feeling = "Feeling good"
        case .okay: feeling = "Feeling okay"
        case .low: feeling = "Not feeling great"
        }
        let note = mood.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return note.isEmpty ? feeling : "\(feeling). \(note)"
    }

    @MainActor
    private static func medicineText(_ event: MedicationEvent, state: AppState) -> String {
        let medication = state.snapshot.medications.first { $0.id == event.medicationID }
        let parts = [medication?.name ?? "Medicine", medication?.dosage ?? ""].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private static func seniorName(_ seniorID: String, state: AppState) -> String {
        let name = state.snapshot.seniors.first { $0.id == seniorID }?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your senior" : name
    }

    private static func remove(activityID: String) async {
        guard !activityID.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { $0.request.content.userInfo["activityID"] as? String == activityID }
            .map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func consumePending() -> Bool {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return false }
        UserDefaults.standard.set(false, forKey: pendingKey)
        return true
    }

    private static func wasNotified(_ id: String) -> Bool {
        Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []).contains(id)
    }

    private static func remember(_ id: String) {
        guard !id.isEmpty else { return }
        var ids = UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        if ids.count > 300 { ids.removeFirst(ids.count - 300) }
        UserDefaults.standard.set(ids, forKey: notifiedKey)
    }
}

private extension AppState {
    func senderName(forMessageID id: String) -> String? {
        guard let message = messages.first(where: { $0.id == id }) else { return nil }
        return senderName(for: message)
    }
}

private final class MessageVoicePlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    static let shared = MessageVoicePlayer()
    private var player: AVAudioPlayer?
    private var onFinish: (@MainActor () -> Void)?

    func play(data: Data, done: @escaping @MainActor () -> Void) -> Bool {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        guard let audio = try? AVAudioPlayer(data: data), audio.duration > 0.2, audio.prepareToPlay() else { return false }
        onFinish = done
        player = audio
        audio.delegate = self
        audio.volume = 1
        return audio.play()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let done = onFinish
        onFinish = nil
        guard flag else { return }
        Task { @MainActor in done?() }
    }
}
