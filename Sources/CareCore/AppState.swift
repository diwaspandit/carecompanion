import Foundation
import Observation

@MainActor @Observable public final class AppState {
    public var seniorTab: SeniorTab = .home
    public var familyTab: FamilyTab = .dashboard
    public var toastMessage: String?
    public var careInsight: CareInsight?
    public var appointmentPrep: AppointmentPrep?
    public private(set) var snapshot: CareSnapshot
    public private(set) var selectedSeniorID: String
    public var healthSyncStatus = SyncStatus()
    @ObservationIgnored public let healthProvider: (any HealthDataProvider)?
    @ObservationIgnored private let repository: any CareRepository
    @ObservationIgnored private let aiService: any AIService
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var healthObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var cachedWatchReadings: [HealthReading] = []
    @ObservationIgnored private var cachedWatchSnapshots: [HealthSnapshot] = []
    @ObservationIgnored private var cachedWatchHealthAt: Date?
    @ObservationIgnored private var lastPresenceReport: Date?

    public init(
        repository: any CareRepository,
        healthProvider: (any HealthDataProvider)? = nil,
        aiService: any AIService = MockAIService(),
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.healthProvider = healthProvider
        self.aiService = aiService
        self.now = now
        snapshot = repository.snapshot
        selectedSeniorID = Self.defaultSeniorID(in: repository.snapshot, profileID: repository.currentProfileID)
    }

    // MARK: - Who is using the app

    public var currentProfileID: String? { repository.currentProfileID }
    public var currentMember: AccountMember? {
        guard let currentProfileID else { return nil }
        return snapshot.members.first { $0.profileID == currentProfileID }
    }
    public var role: CareRole { currentMember?.role ?? .family }
    /// The senior record that belongs to the signed-in user, if they are the senior.
    public var linkedSenior: AccountSenior? {
        guard let currentProfileID else { return nil }
        return snapshot.seniors.first { $0.profileID == currentProfileID }
    }
    public var needsSeniorLink: Bool { role == .senior && linkedSenior == nil }
    /// Only the senior's own phone holds their Apple Health data.
    public var canSyncHealth: Bool { healthProvider != nil && linkedSenior != nil }

    // MARK: - Selected senior

    public var selectedSenior: AccountSenior? { snapshot.seniors.first { $0.id == selectedSeniorID } }
    public var selectedSummary: SeniorCareSummary? { SeniorCareSummary(snapshot: snapshot, seniorID: selectedSeniorID, now: now()) }
    public var seniorSummaries: [SeniorCareSummary] {
        snapshot.seniors.compactMap { SeniorCareSummary(snapshot: snapshot, seniorID: $0.id, now: now()) }
    }
    public var isCheckedIn: Bool { snapshot.checkIns.contains { $0.seniorID == selectedSeniorID } }
    public var currentMood: Mood? { selectedSummary?.mood }
    public var hasEmergency: Bool { snapshot.alerts.contains { $0.seniorID == selectedSeniorID && !$0.acknowledged } }
    public var medications: [Medication] { snapshot.medications.filter { $0.seniorID == selectedSeniorID } }
    public var medicationsTakenCount: Int { medications.filter(\.taken).count }
    public var latestHealth: HealthSnapshot? { selectedSummary?.latestHealth }
    public var appointments: [Appointment] {
        snapshot.appointments.filter { $0.seniorID == selectedSeniorID }.sorted { $0.date < $1.date }
    }
    public var nextAppointment: Appointment? { selectedSummary?.nextAppointment }
    public var activeAlertCount: Int {
        var count = 0
        let zone = selectedSenior.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
        let due = medications.filter { CareSchedule.medicationIsDue($0, on: now(), timeZone: zone) }
        if due.contains(where: { !$0.taken }) { count += 1 }
        if !isCheckedIn { count += 1 }
        if hasEmergency { count += 1 }
        if selectedSummary?.isStepsBelowBaseline == true { count += 1 }
        return count
    }

    public func selectSenior(id: String) {
        guard id != selectedSeniorID, snapshot.seniors.contains(where: { $0.id == id }) else { return }
        selectedSeniorID = id
        careInsight = nil
        appointmentPrep = nil
    }

    // MARK: - Messages

    public var messages: [CareMessage] { snapshot.messages }

    public func senderName(for message: CareMessage) -> String {
        if message.senderProfileID != nil, message.senderProfileID == currentProfileID { return "You" }
        guard let member = snapshot.members.first(where: { $0.profileID == message.senderProfileID }) else {
            return "Former member"
        }
        return member.name.isEmpty ? (member.role == .senior ? "Senior" : "Family member") : member.name
    }

    public func isFromCurrentUser(_ message: CareMessage) -> Bool {
        message.senderProfileID != nil && message.senderProfileID == currentProfileID
    }

    @discardableResult
    public func sendMessage(_ body: String) async -> Bool {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return await perform("Message not sent") { try await self.repository.sendMessage(String(text.prefix(2000))) }
    }

    @discardableResult
    public func sendVoiceMessage(_ data: Data) async -> Bool {
        guard !data.isEmpty else { return false }
        return await perform("Voice message not sent", success: "Sent to your family.") {
            try await self.repository.sendVoiceMessage(data)
        }
    }

    public func voiceAudio(path: String) async -> Data? {
        guard !path.isEmpty else { return nil }
        return try? await repository.voiceAudio(path: path)
    }

    /// True once someone other than the sender has opened the message.
    public func isSeen(_ message: CareMessage) -> Bool {
        message.readerProfileIDs.contains { $0 != message.senderProfileID }
    }

    /// Messages from someone else that this person has not opened.
    public var unseenMessages: [CareMessage] {
        guard let currentProfileID else { return [] }
        return messages.filter { $0.senderProfileID != currentProfileID && !$0.readerProfileIDs.contains(currentProfileID) }
    }

    /// The two newest messages this person has not opened, oldest first.
    public var latestUnseenMessages: [CareMessage] {
        Array(unseenMessages.suffix(2))
    }

    public func markMessagesRead(_ ids: [String]) async {
        guard let currentProfileID else { return }
        let pending = ids.filter { id in
            guard let message = messages.first(where: { $0.id == id }) else { return false }
            return !message.readerProfileIDs.contains(currentProfileID)
        }
        guard !pending.isEmpty else { return }
        do {
            try await repository.markMessagesRead(pending)
            try await repository.refresh()
            applyRepositorySnapshot()
        } catch {
            // A missing read table should not interrupt the conversation.
        }
    }

    // MARK: - Care actions

    /// False only when the server rejected the login. Other failures stay on the last snapshot.
    @discardableResult
    public func refresh() async -> Bool {
        do {
            try await repository.refresh()
            applyRepositorySnapshot()
            return true
        } catch {
            showToast("Couldn't refresh care data: \(error.localizedDescription)")
            return (error as? CareServiceError) != .unauthorized
        }
    }

    public func checkIn() async {
        let ok = await perform("Check-in failed", success: "Check-in shared with your family.") {
            try await self.repository.checkIn(seniorID: self.selectedSeniorID, at: self.now())
        }
        if ok { seniorTab = .mood }
    }

    @discardableResult
    public func recordMood(_ mood: Mood, note: String? = nil) async -> Bool {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await perform("Couldn't save mood", success: "Mood shared with your family.") {
            try await self.repository.recordMood(mood, seniorID: self.selectedSeniorID, at: self.now(),
                                                 note: trimmed?.isEmpty == false ? trimmed : nil)
            try? await self.repository.clearMoodPrompt(seniorID: self.selectedSeniorID)
        }
        if ok { seniorTab = .home }
        return ok
    }

    @discardableResult
    public func saveMoodSchedule(morning: String, evening: String) async -> Bool {
        guard !morning.isEmpty, !evening.isEmpty else { return false }
        return await perform("Couldn't save the mood times", success: "Mood times saved.") {
            try await self.repository.updateMoodSchedule(seniorID: self.selectedSeniorID, morning: morning, evening: evening)
        }
    }

    @discardableResult
    public func askForMoodNow() async -> Bool {
        return await perform("Couldn't ask for a mood", success: "Asked for a mood.") {
            try await self.repository.requestMoodPrompt(seniorID: self.selectedSeniorID, at: self.now())
        }
    }

    public func toggleMedication(id: String) async {
        guard let medication = snapshot.medications.first(where: { $0.id == id }) else { return }
        await perform("Couldn't update medication") {
            try await self.repository.recordMedicationEvent(medicationID: id, taken: !medication.taken, at: self.now())
        }
    }

    /// Records the dose as taken. A second call the same day does nothing.
    /// Returns false only when the save itself failed, so a retry can keep the dose.
    @discardableResult
    public func markMedicationTaken(id: String) async -> Bool {
        guard let medication = snapshot.medications.first(where: { $0.id == id }) else { return true }
        guard !medication.taken else { return true }
        return await perform("Couldn't update medication") {
            try await self.repository.recordMedicationEvent(medicationID: id, taken: true, at: self.now())
        }
    }

    public func snoozeMedication(id: String, until: Date) async {
        guard snapshot.medications.contains(where: { $0.id == id }) else { return }
        await perform("Couldn't snooze") {
            try await self.repository.snoozeMedication(id: id, until: until)
        }
    }

    @discardableResult
    public func addMedication(name: String, dosage: String, scheduledTime: String,
                              weekdays: [Int] = [], endsOn: Date? = nil) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await perform("Couldn't add medication", success: "\(name) added.") {
            try await self.repository.addMedication(seniorID: self.selectedSeniorID, name: name,
                                                    dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    scheduledTime: scheduledTime, weekdays: weekdays, endsOn: endsOn)
        }
    }

    @discardableResult
    public func updateMedication(id: String, name: String, dosage: String, scheduledTime: String,
                                 weekdays: [Int] = [], endsOn: Date? = nil) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await perform("Couldn't update medication", success: "Medication updated.") {
            try await self.repository.updateMedication(id: id, name: name,
                                                       dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       scheduledTime: scheduledTime, weekdays: weekdays, endsOn: endsOn)
        }
    }

    public func requestMedicationReminder(id: String) async {
        guard let medication = snapshot.medications.first(where: { $0.id == id }) else { return }
        await perform("Couldn't send reminder", success: "Reminder sent for \(medication.name).") {
            try await self.repository.requestMedicationReminder(id: id, at: self.now())
        }
    }

    public func deleteMedication(id: String) async {
        await perform("Couldn't delete medication", success: "Medication removed.") {
            try await self.repository.deleteMedication(id: id)
        }
    }

    @discardableResult
    public func saveAppointment(_ appointment: Appointment) async -> Bool {
        guard !appointment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let ok = await perform("Couldn't save appointment", success: appointment.id.isEmpty ? "Appointment added." : "Appointment updated.") {
            try await self.repository.saveAppointment(appointment)
        }
        if ok { appointmentPrep = nil }
        return ok
    }

    /// Records that a visit happened or was missed. A failed save can be retried.
    @discardableResult
    public func logVisit(id: String, outcome: VisitOutcome, occurrence: Date? = nil) async -> Bool {
        guard let visit = snapshot.appointments.first(where: { $0.id == id }) else { return true }
        let when = occurrence ?? self.now()
        if let loggedAt = visit.loggedAt, abs(loggedAt.timeIntervalSince(when)) < 90 { return true }
        if visit.repeatRule == .once, visit.outcome != nil { return true }
        let saved = outcome == .went ? "Visit logged." : "Visit marked missed."
        return await perform("Couldn't save visit", success: saved) {
            try await self.repository.logVisit(id: id, outcome: outcome, at: when)
        }
    }

    public func deleteAppointment(id: String) async {
        await perform("Couldn't delete appointment", success: "Appointment removed.") {
            try await self.repository.deleteAppointment(id: id)
        }
        appointmentPrep = nil
    }

    @discardableResult
    public func triggerSOS() async -> Bool {
        await perform("Couldn't send SOS", success: "Your family has your SOS.") {
            try await self.repository.triggerSOS(seniorID: self.selectedSeniorID, at: self.now())
        }
    }

    public func acknowledgeEmergency() async {
        await perform("Couldn't acknowledge alert", success: "Alert acknowledged.") {
            try await self.repository.acknowledgeAlerts(seniorID: self.selectedSeniorID)
        }
    }

    // MARK: - Insights

    public func loadCareInsight() async {
        careInsight = try? await aiService.careInsight(for: snapshot, seniorID: selectedSeniorID)
    }

    public func prepareAppointment(id: String? = nil) async {
        let appointment = id.flatMap { id in snapshot.appointments.first { $0.id == id } } ?? nextAppointment
        guard let appointment else {
            showToast("Add an upcoming appointment first.")
            return
        }
        appointmentPrep = try? await aiService.appointmentPrep(for: appointment, snapshot: snapshot)
    }

    // MARK: - Seniors, contacts and profile

    @discardableResult
    public func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String, isMe: Bool = false) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let before = Set(snapshot.seniors.map(\.id))
        let senior = AccountSenior(id: "", accountID: snapshot.account.id, name: name, age: age,
                                   city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                                   timeZoneIdentifier: timeZoneIdentifier, profileID: isMe ? currentProfileID : nil)
        let ok = await perform("Couldn't add senior", success: "\(name) added.") {
            try await self.repository.addSenior(senior)
        }
        if ok, let added = snapshot.seniors.first(where: { !before.contains($0.id) }) {
            selectSenior(id: added.id)
        }
        return ok
    }

    @discardableResult
    public func updateSeniorProfile(name: String, age: Int, city: String, timeZone: String) async -> Bool {
        guard var senior = selectedSenior else { return false }
        senior.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        senior.age = age
        senior.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        senior.timeZoneIdentifier = timeZone
        guard !senior.name.isEmpty else { return false }
        return await perform("Couldn't update senior", success: "Profile updated.") {
            try await self.repository.updateSenior(senior)
        }
    }

    public func removeSenior(id: String) async {
        await perform("Couldn't remove senior", success: "Senior removed.") {
            try await self.repository.removeSenior(id: id)
        }
    }

    @discardableResult
    public func claimSenior(id: String) async -> Bool {
        let ok = await perform("Couldn't link your profile") { try await self.repository.claimSenior(id: id) }
        if ok, let linkedSenior { selectedSeniorID = linkedSenior.id }
        return ok
    }

    @discardableResult
    public func saveEmergencyContact(name: String, relation: String, phone: String, id: String = "") async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !phone.isEmpty else { return false }
        let contact = EmergencyContact(id: id, seniorID: selectedSeniorID, name: name,
                                       relation: relation.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone)
        return await perform("Couldn't save contact", success: id.isEmpty ? "Contact added." : "Contact updated.") {
            try await self.repository.saveEmergencyContact(contact)
        }
    }

    public func deleteEmergencyContact(id: String) async {
        await perform("Couldn't delete contact", success: "Contact removed.") {
            try await self.repository.deleteEmergencyContact(id: id)
        }
    }

    @discardableResult
    public func updateProfile(displayName: String, city: String, phone: String) async -> Bool {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await perform("Couldn't save your profile", success: "Profile saved.") {
            try await self.repository.updateProfile(displayName: name,
                                                    city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    phone: phone.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    // MARK: - Health sync

    public func syncHealthData() async {
        guard let healthProvider, let senior = linkedSenior else { return }
        guard await healthProvider.permissionStatus() == .authorized else {
            healthSyncStatus.healthData = .idle
            return
        }
        healthSyncStatus.healthData = .syncing
        do {
            let snapshots = try await healthProvider.snapshots(seniorID: senior.id, endingAt: now())
            let readings = try await healthProvider.readings(seniorID: senior.id, endingAt: now())
            try await repository.upsertHealthSnapshots(snapshots)
            try await repository.upsertHealthReadings(readings)
            applyRepositorySnapshot()
            healthSyncStatus.healthData = .synced
            healthSyncStatus.lastSyncDate = now()
            healthSyncStatus.lastError = nil
            HealthUploadSchedule.markUploaded(now())
        } catch {
            healthSyncStatus.healthData = .failed
            healthSyncStatus.lastError = error.localizedDescription
        }
    }

    /// Stores a report from the paired watch. Wear is written immediately. Steps, sleep, heart rate and
    /// blood pressure are held and written once an hour.
    public func ingestWatchHealth(_ report: WatchHealthReport) async {
        guard let senior = linkedSenior else { return }
        let stamped = report.stamped(seniorID: senior.id)
        if stamped.readings != nil {
            cachedWatchReadings = stamped.readings ?? []
            cachedWatchSnapshots = stamped.snapshots ?? []
            cachedWatchHealthAt = stamped.reportedAt
        }
        await publishWatchPresence(stamped, seniorID: senior.id)
        await uploadScheduledHealth()
    }

    /// Writes the newest health totals when an hour has passed. Watch readings win over this iPhone's Health store.
    public func uploadScheduledHealth() async {
        guard linkedSenior != nil else { return }
        guard HealthUploadSchedule.shouldUpload(lastUpload: HealthUploadSchedule.lastUpload(), now: now()) else { return }
        if let cachedWatchHealthAt, now().timeIntervalSince(cachedWatchHealthAt) < HealthUploadSchedule.watchFreshInterval {
            await uploadCachedWatchHealth()
            return
        }
        await syncHealthData()
    }

    private func publishWatchPresence(_ report: WatchHealthReport, seniorID: String) async {
        if lastPresenceReport == report.reportedAt { return }
        lastPresenceReport = report.reportedAt
        do {
            try await repository.upsertHealthReadings([
                WatchPresence.reading(seniorID: seniorID, worn: report.worn, reportedAt: report.reportedAt)
            ])
            applyRepositorySnapshot()
        } catch {
            lastPresenceReport = nil
        }
    }

    private func uploadCachedWatchHealth() async {
        healthSyncStatus.healthData = .syncing
        do {
            if !cachedWatchSnapshots.isEmpty {
                try await repository.upsertHealthSnapshots(cachedWatchSnapshots)
            }
            if !cachedWatchReadings.isEmpty {
                try await repository.upsertHealthReadings(cachedWatchReadings)
            }
            applyRepositorySnapshot()
            healthSyncStatus.healthData = .synced
            healthSyncStatus.lastSyncDate = now()
            healthSyncStatus.lastError = nil
            HealthUploadSchedule.markUploaded(now())
        } catch {
            healthSyncStatus.healthData = .failed
            healthSyncStatus.lastError = error.localizedDescription
        }
    }

    public func checkHealthPermissionStatus() async -> HealthPermissionStatus {
        await healthProvider?.permissionStatus() ?? .notDetermined
    }

    public func requestHealthPermissions() async throws {
        guard let healthProvider else { throw CareServiceError.vendorUnavailable }
        try await healthProvider.requestPermission()
    }

    /// Keeps Apple Health in sync while the senior's phone has permission. Safe to call repeatedly.
    public func setupAutomaticHealthSync() async {
        guard canSyncHealth, let healthProvider else { return }
        guard await healthProvider.permissionStatus() == .authorized else { return }
        try? await healthProvider.startBackgroundSync()
        guard healthObserver == nil else { return }
        healthObserver = NotificationCenter.default.addObserver(forName: .healthKitDataAvailable, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.uploadScheduledHealth() }
        }
    }

    public func teardownAutomaticHealthSync() async {
        if let healthObserver {
            NotificationCenter.default.removeObserver(healthObserver)
            self.healthObserver = nil
        }
        await healthProvider?.stopBackgroundSync()
    }

    // MARK: - Toasts

    public func showToast(_ message: String) {
        toastMessage = message
    }

    public func clearToast() {
        toastMessage = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func perform(_ failure: String, success: String? = nil, _ work: () async throws -> Void) async -> Bool {
        do {
            try await work()
            applyRepositorySnapshot()
            if let success { showToast(success) }
            return true
        } catch {
            showToast("\(failure): \(error.localizedDescription)")
            return false
        }
    }

    private func applyRepositorySnapshot() {
        snapshot = repository.snapshot
        if !snapshot.seniors.contains(where: { $0.id == selectedSeniorID }) {
            selectedSeniorID = Self.defaultSeniorID(in: snapshot, profileID: currentProfileID)
            careInsight = nil
            appointmentPrep = nil
        }
    }

    private static func defaultSeniorID(in snapshot: CareSnapshot, profileID: String?) -> String {
        if let profileID, let mine = snapshot.seniors.first(where: { $0.profileID == profileID }) {
            return mine.id
        }
        return snapshot.seniors.first?.id ?? ""
    }
}

extension Notification.Name {
    public static let healthKitDataAvailable = Notification.Name("com.carecompanion.healthkit.dataAvailable")
}
