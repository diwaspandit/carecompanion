import CareCore
import Foundation
import Intents
import Network
import Observation
import SwiftUI
import UIKit
import UserNotifications
import WatchConnectivity

/// Daily local reminders for the signed-in senior's medicines. The same alert is scheduled on the
/// iPhone and on the watch. Taken writes through the care account; Snooze comes back in 15 minutes.
final class MedicationReminderCenter: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = MedicationReminderCenter()

    fileprivate static let categoryID = "carecompanion.medication"
    fileprivate static let takenAction = "taken"
    fileprivate static let snoozeAction = "snooze"
    private static let dailyPrefix = "medication.daily."
    private static let snoozePrefix = "medication.snooze."
    private static let stickPrefix = "medication.stick."
    fileprivate static let snoozeInterval: TimeInterval = 15 * 60
    fileprivate static let visitCategoryID = "carecompanion.visit"
    fileprivate static let wentAction = "went"
    fileprivate static let missedAction = "missed"
    private static let visitAtPrefix = "visit.at."
    fileprivate static let visitCatchPrefix = "visit.catchup."
    private static let visitStickPrefix = "visit.stick."
    fileprivate static let moodCategoryID = "carecompanion.mood"
    fileprivate static let moodGreat = "mood.great"
    fileprivate static let moodOkay = "mood.okay"
    fileprivate static let moodLow = "mood.low"
    private static let moodMorningID = "mood.daily.morning"
    private static let moodEveningID = "mood.daily.evening"
    private static let moodStickID = "mood.stick"

    private let box = ReminderBox()

    func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let taken = UNNotificationAction(identifier: Self.takenAction, title: "Taken", options: [])
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 15 min", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [taken, snooze],
                                              intentIdentifiers: [], options: [.customDismissAction])
        let sos = UNNotificationCategory(identifier: "carecompanion.sos", actions: [], intentIdentifiers: [], options: [])
        let message = UNNotificationCategory(identifier: "carecompanion.message", actions: [], intentIdentifiers: [], options: [])
        let went = UNNotificationAction(identifier: Self.wentAction, title: "Went", options: [])
        let missed = UNNotificationAction(identifier: Self.missedAction, title: "Missed", options: [])
        let visit = UNNotificationCategory(identifier: Self.visitCategoryID, actions: [went, missed],
                                           intentIdentifiers: [], options: [])
        let good = UNNotificationAction(identifier: Self.moodGreat, title: "Good", options: [.foreground])
        let okay = UNNotificationAction(identifier: Self.moodOkay, title: "Okay", options: [.foreground])
        let low = UNNotificationAction(identifier: Self.moodLow, title: "Not great", options: [.foreground])
        let mood = UNNotificationCategory(identifier: Self.moodCategoryID, actions: [good, okay, low],
                                          intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category, visit, sos, message, mood])
    }

    @MainActor
    func sync(from state: AppState?) async {
        box.setState(state)
        guard let state else {
            await Self.removeAll()
            return
        }
        guard let senior = state.snapshot.seniors.first(where: { $0.id == state.selectedSeniorID })
                ?? (state.role == .senior ? state.linkedSenior : nil) else {
            await Self.removeAll()
            return
        }
        let zone = TimeZone(identifier: senior.timeZoneIdentifier) ?? .current
        let medications = state.snapshot.medications.filter { $0.seniorID == senior.id }
        let visits = state.snapshot.appointments.filter { $0.seniorID == senior.id }
        await Self.requestPermissionIfNeeded()
        if state.role == .senior {
            await Self.replaceDailyReminders(medications, timeZone: zone)
            await Self.deliverNudges(medications)
            await Self.applySharedSnoozes(medications)
            await Self.clearAlertIfResolved(medications)
            await Self.syncMoodPrompt(senior: senior, moods: state.snapshot.moods, zone: zone)
        } else {
            await Self.removeDailyReminders()
        }
        await Self.dismissTaken(medications.filter(\.taken).map(\.id))
        await Self.scheduleVisits(visits, timeZone: zone)
        await Self.deliverCatchUp(medications: medications, visits: visits, timeZone: zone)
        await box.flushPending()
        #if os(iOS)
        if state.role == .senior {
            await SeniorMessageNotice.sync(state)
        } else if state.role == .family {
            await FamilyMessageNotice.sync(state)
            await FamilyCareNotice.sync(state)
        }
        #endif
        #if os(watchOS)
        if state.role == .senior {
            await Self.deliverWatchMessages(state)
        }
        #endif
        #if os(iOS)
        if state.role == .senior {
            Self.forwardToWatch(medications, visits: visits, timeZoneIdentifier: senior.timeZoneIdentifier)
        }
        #endif
    }

    /// The watch app schedules from this list, including when it is not on screen.
    func applyForwarded(_ rows: [[String: String]], visits: [[String: String]] = [], timeZoneIdentifier: String) async {
        let medications = rows.compactMap { row -> Medication? in
            guard let id = row["id"], let name = row["name"], let time = row["time"] else { return nil }
            let nudge = row["nudge"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
            let snooze = row["snooze"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            let taken = row["taken"] == "1"
            let endsOn = row["ends"].flatMap { CareRecords.dateOnly.date(from: $0) }
            let createdAt = row["created"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            return Medication(id: id, seniorID: "", name: name, dosage: row["dosage"] ?? "", scheduledTime: time,
                              weekdays: CareSchedule.weekdayList(from: row["weekdays"]), endsOn: endsOn,
                              taken: taken, nudgeAt: nudge, snoozeUntil: snooze, createdAt: createdAt)
        }
        let parsedVisits = visits.compactMap { row -> Appointment? in
            guard let id = row["id"], let title = row["title"], let stamp = row["date"].flatMap(Double.init) else { return nil }
            let outcome = row["outcome"].flatMap(VisitOutcome.init(rawValue:))
            let rule = row["repeat"].flatMap(VisitRepeat.init(rawValue:)) ?? .once
            let endsOn = row["ends"].flatMap { CareRecords.dateOnly.date(from: $0) }
            let loggedAt = row["logged"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            return Appointment(id: id, seniorID: "", title: title, clinician: "", date: Date(timeIntervalSince1970: stamp),
                               location: "", notes: "", repeatRule: rule, endsOn: endsOn, outcome: outcome, loggedAt: loggedAt)
        }
        await Self.requestPermissionIfNeeded()
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        await Self.replaceDailyReminders(medications, timeZone: zone)
        await Self.deliverNudges(medications)
        await Self.dismissTaken(medications.filter(\.taken).map(\.id))
        await Self.applySharedSnoozes(medications)
        await Self.clearAlertIfResolved(medications)
        await Self.scheduleVisits(parsedVisits, timeZone: zone)
        await Self.deliverCatchUp(medications: medications, visits: parsedVisits, timeZone: zone)
    }

    @MainActor
    func takePresentedDose() async {
        guard let id = MedicationAlert.shared.medicationID else { return }
        await box.handle(action: Self.takenAction, medicationID: id, name: MedicationAlert.shared.name,
                         dosage: MedicationAlert.shared.dosage, requestID: Self.stickID(id))
    }

    /// Marks a dose taken from the watch New page and clears its reminder.
    @MainActor
    func markDoseTaken(id: String, name: String, dosage: String) async {
        await box.handle(action: Self.takenAction, medicationID: id, name: name, dosage: dosage, requestID: Self.stickID(id))
    }

    @MainActor
    func snoozePresentedDose() async {
        guard let id = MedicationAlert.shared.medicationID else { return }
        await box.handle(action: Self.snoozeAction, medicationID: id, name: MedicationAlert.shared.name,
                         dosage: MedicationAlert.shared.dosage, requestID: Self.stickID(id))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        if Self.isMoodPrompt(info) {
            let finish = MainCallback { completionHandler($0) }
            Task { @MainActor in
                MoodPromptAlert.shared.present()
                finish.call([.banner, .list, .sound])
            }
            return
        }
        if info["kind"] as? String == PhoneOpen.messagesKind {
            let box = box
            let finish = MainCallback { completionHandler($0) }
            Task { @MainActor in
                if let state = box.state {
                    if state.role == .senior { state.seniorTab = .messages } else { state.familyTab = .messages }
                }
                finish.call([])
            }
            return
        }
        if Self.isMessage(info) {
            #if os(iOS)
            if FamilyMessageNotice.isFamilyMessage(info) {
                let messageID = info["messageID"] as? String ?? ""
                let finish = MainCallback { completionHandler($0) }
                Task { @MainActor in
                    FamilyMessageNotice.noteDelivered(messageID)
                    finish.call([.banner, .list, .sound])
                }
                return
            }
            let finish = MainCallback { completionHandler($0) }
            let box = box
            let rich = SeniorMessageNotice.shouldDisplay(info)
            let messageID = info["messageID"] as? String ?? ""
            let senderID = info["senderID"] as? String ?? ""
            let senderName = info["senderName"] as? String ?? ""
            let body = info["body"] as? String ?? notification.request.content.body
            let audioPath = info["audioPath"] as? String ?? ""
            Task { @MainActor in
                if rich {
                    finish.call([.banner, .list, .sound])
                } else {
                    await SeniorMessageNotice.enrichRemote(
                        messageID: messageID, senderID: senderID, senderName: senderName, body: body, audioPath: audioPath,
                        state: box.state)
                    finish.call([])
                }
            }
            #else
            completionHandler([.banner, .list, .sound])
            #endif
            return
        }
        #if os(iOS)
        if FamilyCareNotice.isFamilyUpdate(info) {
            let activityID = info["activityID"] as? String ?? ""
            let finish = MainCallback { completionHandler($0) }
            Task { @MainActor in
                finish.call(FamilyCareNotice.claim(activityID) ? [.banner, .list, .sound] : [])
            }
            return
        }
        #endif
        if Self.isSOS(info) {
            let seniorID = info["seniorID"] as? String ?? ""
            let finish = MainCallback { completionHandler($0) }
            Task { @MainActor in
                if !seniorID.isEmpty { FamilySOSNotice.shared.present(seniorID) }
                finish.call([.banner, .list, .sound])
            }
            return
        }
        if Self.isVisit(info) {
            let finish = MainCallback { completionHandler($0) }
            Task { @MainActor in finish.call([.banner, .list, .sound]) }
            return
        }
        let medicationID = info["medicationID"] as? String
        let nudge = Self.isNudge(info)
        let box = box
        let finish = MainCallback { completionHandler($0) }
        let name = notification.request.content.title
        let dosage = info["dosage"] as? String ?? ""
        Task { @MainActor in
            let show = nudge || !box.isTaken(medicationID)
            if show, let medicationID {
                MedicationAlert.shared.present(id: medicationID, name: name, dosage: dosage)
            }
            finish.call(show ? [.banner, .list, .sound] : [])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        if Self.isMoodPrompt(content.userInfo) {
            let action = response.actionIdentifier
            let box = box
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                if action == UNNotificationDismissActionIdentifier {
                    await Self.repostMoodPromptIfDue()
                } else if let mood = Self.mood(for: action) {
                    _ = await box.state?.recordMood(mood)
                    await Self.syncMoodFromState()
                } else {
                    MoodPromptAlert.shared.present()
                }
                finish.call(())
            }
            return
        }
        if content.userInfo["kind"] as? String == PhoneOpen.messagesKind {
            let box = box
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                if let state = box.state {
                    if state.role == .senior { state.seniorTab = .messages } else { state.familyTab = .messages }
                }
                finish.call(())
            }
            return
        }
        if Self.isMessage(content.userInfo) {
            #if os(iOS)
            let messageID = content.userInfo["messageID"] as? String ?? ""
            let audioPath = content.userInfo["audioPath"] as? String ?? ""
            let family = FamilyMessageNotice.isFamilyMessage(content.userInfo)
            let box = box
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                if family || box.state?.role == .family {
                    await FamilyMessageNotice.open(messageID: messageID, state: box.state)
                } else {
                    await SeniorMessageNotice.open(messageID: messageID, audioPath: audioPath, state: box.state)
                }
                finish.call(())
            }
            #else
            completionHandler()
            #endif
            return
        }
        #if os(iOS)
        if FamilyCareNotice.isFamilyUpdate(content.userInfo) {
            let activityID = content.userInfo["activityID"] as? String ?? ""
            let box = box
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                await FamilyCareNotice.open(activityID: activityID, state: box.state)
                finish.call(())
            }
            return
        }
        #endif
        if Self.isSOS(content.userInfo) {
            let seniorID = content.userInfo["seniorID"] as? String ?? ""
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                if !seniorID.isEmpty { FamilySOSNotice.shared.present(seniorID) }
                finish.call(())
            }
            return
        }
        if Self.isVisit(content.userInfo) {
            let action = response.actionIdentifier
            let visitID = content.userInfo["appointmentID"] as? String ?? ""
            let title = content.title
            let occurrence = (content.userInfo["occurrence"] as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
                ?? (content.userInfo["occurrence"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let box = box
            let finish = MainCallback<Void> { _ in completionHandler() }
            Task { @MainActor in
                await box.handleVisit(action: action, visitID: visitID, title: title, occurrence: occurrence)
                finish.call(())
            }
            return
        }
        let action = response.actionIdentifier
        let requestID = response.notification.request.identifier
        let medicationID = content.userInfo["medicationID"] as? String
        let dosage = content.userInfo["dosage"] as? String ?? ""
        let name = content.title
        let box = box
        let finish = MainCallback<Void> { _ in completionHandler() }
        Task { @MainActor in
            await box.handle(action: action, medicationID: medicationID, name: name, dosage: dosage, requestID: requestID)
            finish.call(())
        }
    }

    private static func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
        }
        let updated = await center.notificationSettings()
        if updated.authorizationStatus == .authorized || updated.authorizationStatus == .provisional {
            PushRegistration.registerWithSystem()
        }
    }

    private static func replaceDailyReminders(_ medications: [Medication], timeZone: TimeZone) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let dailyIDs = Set(medications.map { Self.dailyID($0.id) })
        let medicationIDs = Set(medications.map(\.id))
        let stale = pending.map(\.identifier).filter { identifier in
            if identifier.hasPrefix(Self.dailyPrefix) { return !dailyIDs.contains(identifier) }
            if let id = Self.medicationID(fromSnooze: identifier) { return !medicationIDs.contains(id) }
            if identifier.hasPrefix(Self.stickPrefix) {
                return !medicationIDs.contains(String(identifier.dropFirst(Self.stickPrefix.count)))
            }
            return false
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var datedIDs = Set<String>()
        let retiredDaily = medications.filter { !CareSchedule.repeatsEveryDayForever($0) }.map { Self.dailyID($0.id) }
        center.removePendingNotificationRequests(withIdentifiers: retiredDaily)

        for medication in medications {
            guard let time = Self.hourMinute(from: medication.scheduledTime) else { continue }
            if CareSchedule.repeatsEveryDayForever(medication) {
                var components = DateComponents()
                components.calendar = calendar
                components.timeZone = timeZone
                components.hour = time.hour
                components.minute = time.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: Self.dailyID(medication.id),
                                                    content: Self.content(name: medication.name, dosage: medication.dosage, medicationID: medication.id),
                                                    trigger: trigger)
                try? await center.add(request)
                continue
            }
            for moment in CareSchedule.upcomingDoseTimes(medication, now: Date(), timeZone: timeZone) {
                let identifier = Self.doseDayID(medication.id, moment, calendar: calendar)
                datedIDs.insert(identifier)
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
                var components = parts
                components.calendar = calendar
                components.timeZone = timeZone
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: Self.content(name: medication.name, dosage: medication.dosage, medicationID: medication.id),
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
                try? await center.add(request)
            }
        }
        let leftover = (await center.pendingNotificationRequests()).map(\.identifier).filter { identifier in
            identifier.hasPrefix("medication.day.") && !datedIDs.contains(identifier)
        }
        center.removePendingNotificationRequests(withIdentifiers: leftover)
    }

    /// Shows a dose only when the family tapped Remind. Saving the medicine does not set this.
    private static func deliverNudges(_ medications: [Medication]) async {
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        for medication in medications {
            guard let nudgeAt = medication.nudgeAt else { continue }
            let key = "medication.nudge.seen.\(medication.id)"
            let stamp = Int(nudgeAt.timeIntervalSince1970 * 1000)
            let seen = defaults.integer(forKey: key)
            // The first time this device sees an older medicine, remember it without alerting.
            if seen == 0, Date().timeIntervalSince(nudgeAt) > 120 { 
                defaults.set(stamp, forKey: key)
                continue
            }
            if stamp <= seen { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "medication.nudge.\(medication.id).\(stamp)",
                content: content(name: medication.name, dosage: medication.dosage, medicationID: medication.id, nudge: true),
                trigger: trigger)
            do {
                try await center.add(request)
                defaults.set(stamp, forKey: key)
            } catch {
                // Leave it unseen so the next refresh can try again, for example before notifications are allowed.
            }
        }
    }

    fileprivate static func scheduleSnooze(medicationID: String, name: String, dosage: String) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.snoozeInterval, repeats: false)
        let request = UNNotificationRequest(identifier: Self.snoozeID(medicationID),
                                            content: Self.content(name: name, dosage: dosage, medicationID: medicationID),
                                            trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    fileprivate static func repostVisit(visitID: String, title: String) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: visitStickID(visitID),
            content: visitContent(title: title, visitID: visitID, occurrence: Date(),
                                  body: "You were away from the internet. Did you go to this visit?"),
            trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    fileprivate static func repost(medicationID: String, name: String, dosage: String) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: stickID(medicationID),
                                            content: content(name: name, dosage: dosage, medicationID: medicationID),
                                            trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func dismissTaken(_ medicationIDs: [String]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        var identifiers = medicationIDs.flatMap { [Self.dailyID($0), Self.snoozeID($0), Self.stickID($0)] }
        for id in medicationIDs {
            let prefixes = ["medication.day.\(id).", "medication.catchup.\(id)."]
            identifiers += pending.map(\.identifier).filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
            identifiers += delivered.map(\.request.identifier).filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        for id in medicationIDs { await MedicationAlert.shared.clear(id: id) }
    }

    /// A snooze saved on the phone or the watch is scheduled on this device too, and the dose screen goes away.
    private static func applySharedSnoozes(_ medications: [Medication]) async {
        let center = UNUserNotificationCenter.current()
        for medication in medications where !medication.taken {
            guard let until = medication.snoozeUntil else { continue }
            let remaining = until.timeIntervalSinceNow
            guard remaining > 1 else { continue }
            let request = UNNotificationRequest(
                identifier: snoozeID(medication.id),
                content: content(name: medication.name, dosage: medication.dosage, medicationID: medication.id),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            )
            try? await center.add(request)
            await MedicationAlert.shared.clear(id: medication.id)
        }
    }

    private static func clearAlertIfResolved(_ medications: [Medication]) async {
        guard let shown = await MedicationAlert.shared.medicationID else { return }
        guard let medication = medications.first(where: { $0.id == shown }) else {
            await MedicationAlert.shared.clear(id: shown)
            return
        }
        if medication.taken || (medication.snoozeUntil?.timeIntervalSinceNow ?? -1) > 1 {
            await MedicationAlert.shared.clear(id: shown)
        }
    }

    #if os(iOS)
    /// Wakes the paired watch, even if its app is not on screen, and asks it to schedule the same alerts.
    private static func forwardToWatch(_ medications: [Medication], visits: [Appointment], timeZoneIdentifier: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let rows: [[String: String]] = medications.map { medication in
            var row = ["id": medication.id, "name": medication.name, "dosage": medication.dosage,
                       "time": medication.scheduledTime, "taken": medication.taken ? "1" : "0"]
            if let createdAt = medication.createdAt {
                row["created"] = String(createdAt.timeIntervalSince1970)
            }
            if let nudgeAt = medication.nudgeAt {
                row["nudge"] = String(Int(nudgeAt.timeIntervalSince1970 * 1000))
            }
            if let snoozeUntil = medication.snoozeUntil {
                row["snooze"] = String(snoozeUntil.timeIntervalSince1970)
            }
            if let weekdays = CareSchedule.weekdayStorage(medication.weekdays) { row["weekdays"] = weekdays }
            if let endsOn = medication.endsOn { row["ends"] = CareRecords.dateOnly.string(from: endsOn) }
            return row
        }
        let visitRows: [[String: String]] = visits.map { visit in
            var row = ["id": visit.id, "title": visit.title, "date": String(visit.date.timeIntervalSince1970),
                       "repeat": visit.repeatRule.rawValue]
            if let outcome = visit.outcome { row["outcome"] = outcome.rawValue }
            if let endsOn = visit.endsOn { row["ends"] = CareRecords.dateOnly.string(from: endsOn) }
            if let loggedAt = visit.loggedAt { row["logged"] = String(loggedAt.timeIntervalSince1970) }
            return row
        }
        session.transferUserInfo(["medications": rows, "visits": visitRows, "timeZone": timeZoneIdentifier])
    }

    /// Asks the paired watch to show this message, including when the watch app is not open.
    static func forwardMessageToWatch(messageID: String, name: String, body: String, audioPath: String, image: Data?) {
        guard WCSession.isSupported(), !messageID.isEmpty else { return }
        var payload: [String: Any] = [
            "kind": "message",
            "messageID": messageID,
            "senderName": name,
            "body": body,
            "audioPath": audioPath
        ]
        if let image, let thumb = watchThumbnail(image) { payload["image"] = thumb }
        WatchSessionRelay.sendToWatch(payload)
    }

    /// A small photo the watch can show. Full portraits are too large to send while the watch app is closed.
    private static func watchThumbnail(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 160
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return thumb.jpegData(compressionQuality: 0.72)
    }
    #endif

    private static func isMoodPrompt(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == "moodPrompt"
    }

    private static func mood(for action: String) -> Mood? {
        switch action {
        case moodGreat: .great
        case moodOkay: .okay
        case moodLow: .low
        default: nil
        }
    }

    /// Daily asks at the family's times, plus a prompt that comes back if it is swiped away before a mood is chosen.
    @MainActor
    private static func syncMoodPrompt(senior: AccountSenior, moods: [MoodEntry], zone: TimeZone) async {
        let center = UNUserNotificationCenter.current()
        await replaceMoodSchedule(morning: senior.moodMorning, evening: senior.moodEvening, zone: zone)
        let due = MoodPromptSchedule.due(
            now: Date(), timeZone: zone, morning: senior.moodMorning, evening: senior.moodEvening,
            moodDates: moods.filter { $0.seniorID == senior.id }.map(\.date), askedAt: senior.moodPromptAt)
        if due == nil {
            let wasShowing = MoodPromptAlert.shared.isShowing
            let delivered = await center.deliveredNotifications()
            let hadPrompt = wasShowing || delivered.contains { request in
                request.request.identifier == moodStickID || Self.isMoodPrompt(request.request.content.userInfo)
            }
            MoodPromptAlert.shared.clear()
            let deliveredIDs = delivered.filter { Self.isMoodPrompt($0.request.content.userInfo) }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: deliveredIDs + [moodStickID])
            center.removePendingNotificationRequests(withIdentifiers: [moodStickID])
            if hadPrompt { Self.tellPeerMoodAnswered() }
            return
        }
        MoodPromptAlert.shared.present()
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()
        let visible = delivered.contains { $0.request.identifier == moodStickID }
            || pending.contains { $0.identifier == moodStickID }
        if !visible {
            try? await center.add(UNNotificationRequest(identifier: moodStickID, content: moodContent(), trigger: nil))
        }
    }

    @MainActor
    private static func syncMoodFromState() async {
        guard let state = shared.box.state, state.role == .senior,
              let senior = state.linkedSenior ?? state.snapshot.seniors.first(where: { $0.id == state.selectedSeniorID }) else { return }
        let zone = TimeZone(identifier: senior.timeZoneIdentifier) ?? .current
        await syncMoodPrompt(senior: senior, moods: state.snapshot.moods, zone: zone)
    }

    /// Drops the prompt on this device without telling the other one. Used when the other device already answered.
    @MainActor
    func dismissMoodPromptLocally() async {
        MoodPromptAlert.shared.clear()
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let ids = delivered.filter { Self.isMoodPrompt($0.request.content.userInfo) }.map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: ids + [Self.moodStickID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.moodStickID])
    }

    /// The other device removes its prompt. `transferUserInfo` is delivered even if that app is not open.
    private static func tellPeerMoodAnswered() {
        let info: [String: Any] = ["kind": "moodClear"]
        #if os(iOS)
        WatchSessionRelay.sendToWatch(info)
        #else
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(info)
        #endif
    }

    @MainActor
    private static func repostMoodPromptIfDue() async {
        guard let state = shared.box.state else {
            await stickMoodPrompt()
            return
        }
        guard state.role == .senior,
              let senior = state.linkedSenior ?? state.snapshot.seniors.first(where: { $0.id == state.selectedSeniorID }) else {
            MoodPromptAlert.shared.clear()
            return
        }
        let zone = TimeZone(identifier: senior.timeZoneIdentifier) ?? .current
        let due = MoodPromptSchedule.due(
            now: Date(), timeZone: zone, morning: senior.moodMorning, evening: senior.moodEvening,
            moodDates: state.snapshot.moods.filter { $0.seniorID == senior.id }.map(\.date), askedAt: senior.moodPromptAt)
        guard due != nil else {
            MoodPromptAlert.shared.clear()
            return
        }
        await stickMoodPrompt()
    }

    @MainActor
    private static func stickMoodPrompt() async {
        MoodPromptAlert.shared.present()
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: moodStickID, content: moodContent(), trigger: nil))
    }

    private static func replaceMoodSchedule(morning: String, evening: String, zone: TimeZone) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [moodMorningID, moodEveningID])
        for (id, text) in [(moodMorningID, morning), (moodEveningID, evening)] {
            guard let when = MoodPromptSchedule.clock(text, on: Date(), calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                return calendar
            }()) else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute], from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: id, content: moodContent(), trigger: trigger))
        }
    }

    private static func moodContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "How are you?"
        content.body = "Tell your family. This stays until you choose."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = moodCategoryID
        content.threadIdentifier = "mood.prompt"
        content.userInfo = ["kind": "moodPrompt"]
        return content
    }

    /// Posts one alert for each dose and visit whose time passed and is still unlogged.
    /// Each item is posted once per day (a dose) or once (a visit), then again only if it is still open next time the day rolls.
    private static func deliverCatchUp(medications: [Medication], visits: [Appointment], timeZone: TimeZone) async {
        let now = Date()
        let center = UNUserNotificationCenter.current()
        let defaults = UserDefaults.standard
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = dayKey(now, calendar: calendar)
        for medication in OfflineCatchUp.medications(medications, now: now, timeZone: timeZone) {
            let key = "care.catchup.med.\(medication.id).\(day)"
            if defaults.bool(forKey: key) { continue }
            let request = UNNotificationRequest(
                identifier: "medication.catchup.\(medication.id).\(day)",
                content: content(name: medication.name, dosage: medication.dosage, medicationID: medication.id,
                                 body: "You were away from the internet. Did you take this?"),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            do {
                try await center.add(request)
                defaults.set(true, forKey: key)
            } catch {}
        }
        for visit in OfflineCatchUp.visits(visits, now: now, timeZone: timeZone) {
            let stamp = Int(visit.date.timeIntervalSince1970)
            let key = "care.catchup.visit.\(visit.id).\(stamp)"
            if defaults.bool(forKey: key) { continue }
            let request = UNNotificationRequest(
                identifier: "\(visitCatchPrefix)\(visit.id).\(stamp)",
                content: visitContent(title: visit.title, visitID: visit.id, occurrence: visit.date,
                                      body: "You were away from the internet. Did you go to this visit?"),
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
            do {
                try await center.add(request)
                defaults.set(true, forKey: key)
            } catch {}
        }
    }

    /// Local visit bells at the appointment time. They fire without internet once they are scheduled.
    private static func scheduleVisits(_ visits: [Appointment], timeZone: TimeZone) async {
        let center = UNUserNotificationCenter.current()
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let planned = visits.flatMap { visit in
            CareSchedule.notificationOccurrences(of: visit, now: now, timeZone: timeZone).map { (visit, $0) }
        }
        let live = Set(planned.map { visitAtStamp($0.0.id, $0.1) })
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { identifier in
            guard identifier.hasPrefix(visitAtPrefix) else { return false }
            return !live.contains(identifier)
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for (visit, when) in planned {
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: when)
            var components = parts
            components.calendar = calendar
            components.timeZone = timeZone
            let request = UNNotificationRequest(
                identifier: visitAtStamp(visit.id, when),
                content: visitContent(title: visit.title, visitID: visit.id, occurrence: when, body: "Time for this visit."),
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await center.add(request)
        }
    }

    private static func removeDailyReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(dailyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func removeAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let delivered = await center.deliveredNotifications()
        let identifiers = (pending.map(\.identifier) + delivered.map(\.request.identifier))
            .filter { $0.hasPrefix("medication.") || $0.hasPrefix("visit.") || $0.hasPrefix("message.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func content(name: String, dosage: String, medicationID: String, nudge: Bool = false,
                                body: String? = nil) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = name
        content.body = body ?? (dosage.isEmpty ? "Time to take this." : dosage)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.categoryIdentifier = categoryID
        content.threadIdentifier = "medications"
        content.userInfo = ["medicationID": medicationID, "dosage": dosage, "nudge": nudge]
        return content
    }

    private static func visitContent(title: String, visitID: String, occurrence: Date, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = visitCategoryID
        content.threadIdentifier = "visits"
        content.userInfo = ["kind": "visit", "appointmentID": visitID, "occurrence": String(occurrence.timeIntervalSince1970)]
        return content
    }

    private static func isMessage(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == "message"
    }

    #if os(watchOS)
    /// Shows a message on the watch face. A picture is attached so it is visible with the app closed.
    @MainActor
    static func showWatchMessage(name: String, body: String, messageID: String, image: Data?) async {
        guard !messageID.isEmpty else { return }
        let key = "care.watch.message.notified"
        let already = UserDefaults.standard.stringArray(forKey: key) ?? []
        guard !already.contains(messageID) else { return }

        let content = UNMutableNotificationContent()
        content.title = name.isEmpty ? "Family" : name
        content.body = body.isEmpty ? "New message" : body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "carecompanion.message"
        content.userInfo = ["kind": "message", "rich": "1", "messageID": messageID, "senderName": name, "body": body]
        let picture = image ?? initialsJPEG(name.isEmpty ? "Family" : name)
        if let picture, let attachment = messageAttachment(picture, messageID: messageID) {
            content.attachments = [attachment]
        }
        let delivered = communicationContent(content, name: content.title, body: content.body, messageID: messageID, image: picture)
        let request = UNNotificationRequest(identifier: "message.watch.\(messageID)", content: delivered, trigger: nil)
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .timeSensitive])
        }
        let updated = await center.notificationSettings()
        guard updated.authorizationStatus == .authorized || updated.authorizationStatus == .provisional else { return }
        do {
            try await center.add(request)
        } catch {
            return
        }
        var seen = UserDefaults.standard.stringArray(forKey: key) ?? []
        seen.append(messageID)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        UserDefaults.standard.set(seen, forKey: key)
    }

    @MainActor
    private static func deliverWatchMessages(_ state: AppState) async {
        let unseen = state.unseenMessages.filter { Date().timeIntervalSince($0.date) < 7 * 24 * 3600 }
        let latest = Dictionary(grouping: unseen, by: { $0.senderProfileID ?? $0.id })
            .compactMapValues { $0.max { $0.date < $1.date } }
        for message in latest.values {
            let body = message.audioPath == nil ? message.body : "Voice message"
            await showWatchMessage(name: state.senderName(for: message), body: body, messageID: message.id, image: nil)
        }
        let keep = Set(state.unseenMessages.map(\.id))
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let stale = delivered.filter { note in
            guard isMessage(note.request.content.userInfo) else { return false }
            let id = note.request.content.userInfo["messageID"] as? String ?? ""
            return !keep.contains(id)
        }.map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: stale)
    }

    @MainActor
    private static func initialsJPEG(_ name: String) -> Data? {
        let letters = name.split(separator: " ").prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
        let initials = letters.isEmpty ? "?" : letters
        let view = Text(initials)
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 160, height: 160)
            .background(Circle().fill(Color(red: 112 / 255, green: 160 / 255, blue: 124 / 255)))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }

    private static func messageAttachment(_ data: Data, messageID: String) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-message-\(messageID).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return try UNNotificationAttachment(identifier: "photo", url: url)
        } catch {
            return nil
        }
    }

    private static func communicationContent(_ content: UNMutableNotificationContent, name: String, body: String,
                                              messageID: String, image: Data?) -> UNNotificationContent {
        guard let image else { return content }
        let person = INPerson(personHandle: INPersonHandle(value: messageID, type: .unknown),
                              nameComponents: nil, displayName: name, image: INImage(imageData: image),
                              contactIdentifier: nil, customIdentifier: messageID)
        let intent = INSendMessageIntent(recipients: nil, outgoingMessageType: .outgoingMessageText, content: body,
                                          speakableGroupName: nil, conversationIdentifier: "carecompanion.messages",
                                          serviceName: "CareCompanion", sender: person, attachments: nil)
        intent.setImage(INImage(imageData: image), forParameterNamed: \.sender)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate()
        guard let styled = try? content.updating(from: intent), !styled.attachments.isEmpty else { return content }
        return styled
    }
    #endif

    private static func isSOS(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == "sos"
    }

    private static func isVisit(_ info: [AnyHashable: Any]) -> Bool {
        info["kind"] as? String == "visit"
    }

    private static func isNudge(_ info: [AnyHashable: Any]) -> Bool {
        if let flag = info["nudge"] as? Bool { return flag }
        if let number = info["nudge"] as? NSNumber { return number.boolValue }
        return false
    }

    fileprivate static func dailyID(_ medicationID: String) -> String { dailyPrefix + medicationID }
    fileprivate static func snoozeID(_ medicationID: String) -> String { snoozePrefix + medicationID }
    fileprivate static func stickID(_ medicationID: String) -> String { stickPrefix + medicationID }
    fileprivate static func visitAtID(_ visitID: String) -> String { visitAtPrefix + visitID }
    fileprivate static func visitAtStamp(_ visitID: String, _ date: Date) -> String {
        visitAtID(visitID) + ".\(Int(date.timeIntervalSince1970))"
    }
    fileprivate static func doseDayID(_ medicationID: String, _ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "medication.day.\(medicationID).\(day)"
    }
    fileprivate static func visitCatchID(_ visitID: String) -> String { visitCatchPrefix + visitID }
    fileprivate static func visitStickID(_ visitID: String) -> String { visitStickPrefix + visitID }
    fileprivate static func visitIDs(_ visitID: String) -> [String] {
        [visitAtID(visitID), visitCatchID(visitID), visitStickID(visitID)]
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func medicationID(fromSnooze identifier: String) -> String? {
        guard identifier.hasPrefix(snoozePrefix) else { return nil }
        return String(identifier.dropFirst(snoozePrefix.count))
    }

    /// "8:00 AM" as a clock time, independent of the phone's time zone.
    private static func hourMinute(from scheduledTime: String) -> (hour: Int, minute: Int)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: scheduledTime.uppercased()) else { return nil }
        let parts = formatter.calendar.dateComponents([.hour, .minute], from: date)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return (hour, minute)
    }
}

/// Lets the notification callbacks finish on the main actor. The system snapshots the app on
/// whatever thread calls the completion handler, and that snapshot must be on the main thread.
private final class MainCallback<Value>: @unchecked Sendable {
    private let body: (Value) -> Void
    init(_ body: @escaping (Value) -> Void) { self.body = body }
    func call(_ value: Value) { body(value) }
}

@MainActor @Observable
final class MedicationAlert {
    static let shared = MedicationAlert()
    private(set) var medicationID: String?
    private(set) var name = ""
    private(set) var dosage = ""

    func present(id: String, name: String, dosage: String) {
        medicationID = id
        self.name = name.isEmpty ? "Medicine" : name
        self.dosage = dosage
    }

    func clear(id: String) {
        guard medicationID == id else { return }
        medicationID = nil
    }
}

@MainActor @Observable
final class MoodPromptAlert {
    static let shared = MoodPromptAlert()
    var isShowing = false
    func present() { isShowing = true }
    func clear() { isShowing = false }
}

@MainActor
private final class ReminderBox {
    weak var state: AppState?

    func setState(_ state: AppState?) {
        self.state = state
    }

    func handleVisit(action: String, visitID: String, title: String, occurrence: Date?) async {
        guard !visitID.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        switch action {
        case MedicationReminderCenter.wentAction, MedicationReminderCenter.missedAction:
            var identifiers = [MedicationReminderCenter.visitStickID(visitID), MedicationReminderCenter.visitAtID(visitID)]
            if let occurrence {
                identifiers.append(MedicationReminderCenter.visitAtStamp(visitID, occurrence))
                identifiers.append("\(MedicationReminderCenter.visitCatchPrefix)\(visitID).\(Int(occurrence.timeIntervalSince1970))")
            }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
            let outcome: VisitOutcome = action == MedicationReminderCenter.wentAction ? .went : .missed
            await logVisit(visitID, outcome: outcome, occurrence: occurrence)
        case UNNotificationDismissActionIdentifier:
            await MedicationReminderCenter.repostVisit(visitID: visitID, title: title)
        case UNNotificationDefaultActionIdentifier:
            if state?.role == .senior {
                state?.seniorTab = .visits
            } else {
                state?.familyTab = .appointments
            }
        default:
            break
        }
    }

    func isTaken(_ medicationID: String?) -> Bool {
        guard let medicationID, let state else { return false }
        return state.snapshot.medications.contains { $0.id == medicationID && $0.taken }
    }

    func handle(action: String, medicationID: String?, name: String, dosage: String, requestID: String) async {
        let center = UNUserNotificationCenter.current()
        guard let medicationID else { return }
        switch action {
        case MedicationReminderCenter.takenAction:
            center.removePendingNotificationRequests(withIdentifiers: [
                MedicationReminderCenter.snoozeID(medicationID), MedicationReminderCenter.stickID(medicationID)
            ])
            center.removeDeliveredNotifications(withIdentifiers: [
                MedicationReminderCenter.dailyID(medicationID),
                MedicationReminderCenter.snoozeID(medicationID),
                MedicationReminderCenter.stickID(medicationID),
                requestID
            ])
            MedicationAlert.shared.clear(id: medicationID)
            await markTaken(medicationID)
        case MedicationReminderCenter.snoozeAction:
            let until = Date().addingTimeInterval(MedicationReminderCenter.snoozeInterval)
            await MedicationReminderCenter.scheduleSnooze(medicationID: medicationID, name: name, dosage: dosage)
            center.removePendingNotificationRequests(withIdentifiers: [MedicationReminderCenter.stickID(medicationID)])
            center.removeDeliveredNotifications(withIdentifiers: [requestID, MedicationReminderCenter.stickID(medicationID)])
            MedicationAlert.shared.clear(id: medicationID)
            await rememberSnooze(medicationID, until: until)
        case UNNotificationDismissActionIdentifier:
            guard !isTaken(medicationID) else { return }
            await MedicationReminderCenter.repost(medicationID: medicationID, name: name, dosage: dosage)
        case UNNotificationDefaultActionIdentifier:
            MedicationAlert.shared.present(id: medicationID, name: name, dosage: dosage)
        default:
            break
        }
    }

    func markTaken(_ medicationID: String) async {
        guard let state else {
            PendingCareLog.addTaken(medicationID)
            return
        }
        if await state.markMedicationTaken(id: medicationID) == false {
            PendingCareLog.addTaken(medicationID)
        }
    }

    func logVisit(_ visitID: String, outcome: VisitOutcome, occurrence: Date?) async {
        guard let state else {
            PendingCareLog.addVisit(id: visitID, outcome: outcome.rawValue, occurrence: occurrence)
            return
        }
        if await state.logVisit(id: visitID, outcome: outcome, occurrence: occurrence) == false {
            PendingCareLog.addVisit(id: visitID, outcome: outcome.rawValue, occurrence: occurrence)
        }
    }

    func rememberSnooze(_ medicationID: String, until: Date) async {
        guard let state else {
            pendingSnoozes.append((medicationID, until))
            return
        }
        await state.snoozeMedication(id: medicationID, until: until)
    }

    func flushPending() async {
        guard let state else { return }
        var stillDue: [String] = []
        for id in PendingCareLog.takenIDs() {
            if await state.markMedicationTaken(id: id) == false {
                stillDue.append(id)
            }
        }
        PendingCareLog.setTaken(stillDue)
        var stillOpen: [(String, String, String)] = []
        for item in PendingCareLog.visits() {
            guard let outcome = VisitOutcome(rawValue: item.outcome) else { continue }
            let occurrence = Double(item.occurrence).map { Date(timeIntervalSince1970: $0) }
            if await state.logVisit(id: item.id, outcome: outcome, occurrence: occurrence) == false {
                stillOpen.append(item)
            }
        }
        PendingCareLog.setVisits(stillOpen)
        let snoozes = pendingSnoozes
        pendingSnoozes = []
        for (id, until) in snoozes where until.timeIntervalSinceNow > 1 {
            await state.snoozeMedication(id: id, until: until)
        }
    }

    private var pendingSnoozes: [(String, Date)] = []
}

/// Dose and visit logs made while the device had no connection. Uploaded the next time the account loads.
private enum PendingCareLog {
    private static let takenKey = "care.pending.taken"
    private static let visitKey = "care.pending.visits"

    static func takenIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: takenKey) ?? []
    }

    static func addTaken(_ id: String) {
        var ids = takenIDs()
        if !ids.contains(id) { ids.append(id) }
        setTaken(ids)
    }

    static func setTaken(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: takenKey)
    }

    static func visits() -> [(id: String, outcome: String, occurrence: String)] {
        (UserDefaults.standard.stringArray(forKey: visitKey) ?? []).compactMap { item in
            let parts = item.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            return (parts[0], parts[1], parts.count > 2 ? parts[2] : "")
        }
    }

    static func addVisit(id: String, outcome: String, occurrence: Date?) {
        var rows = visits().filter { $0.id != id }
        rows.append((id, outcome, occurrence.map { String($0.timeIntervalSince1970) } ?? ""))
        setVisits(rows)
    }

    static func setVisits(_ rows: [(id: String, outcome: String, occurrence: String)]) {
        UserDefaults.standard.set(rows.map { "\($0.id)|\($0.outcome)|\($0.occurrence)" }, forKey: visitKey)
    }
}

/// Calls back when a device that was offline gets a connection again.
final class CareReachability: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private var wasOffline = false
    var onReconnect: (@Sendable () -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let online = path.status == .satisfied
            if online, self.wasOffline { self.onReconnect?() }
            self.wasOffline = !online
        }
        monitor.start(queue: DispatchQueue(label: "care.reachability"))
    }
}

/// Set when a family phone receives or opens an SOS notification.
@MainActor @Observable final class FamilySOSNotice {
    static let shared = FamilySOSNotice()
    var seniorID: String?

    func present(_ seniorID: String) {
        self.seniorID = seniorID
    }

    func clear() {
        seniorID = nil
    }
}
