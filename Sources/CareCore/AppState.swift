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
        if medicationsTakenCount < medications.count { count += 1 }
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

    // MARK: - Care actions

    public func refresh() async {
        do {
            try await repository.refresh()
            applyRepositorySnapshot()
        } catch {
            showToast("Couldn't refresh care data: \(error.localizedDescription)")
        }
    }

    public func checkIn() async {
        let ok = await perform("Check-in failed", success: "Check-in shared with your family.") {
            try await self.repository.checkIn(seniorID: self.selectedSeniorID, at: self.now())
        }
        if ok { seniorTab = .mood }
    }

    public func recordMood(_ mood: Mood, note: String? = nil) async {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await perform("Couldn't save mood", success: "Mood shared with your family.") {
            try await self.repository.recordMood(mood, seniorID: self.selectedSeniorID, at: self.now(),
                                                 note: trimmed?.isEmpty == false ? trimmed : nil)
        }
        if ok { seniorTab = .home }
    }

    public func toggleMedication(id: String) async {
        guard let medication = snapshot.medications.first(where: { $0.id == id }) else { return }
        await perform("Couldn't update medication") {
            try await self.repository.recordMedicationEvent(medicationID: id, taken: !medication.taken, at: self.now())
        }
    }

    @discardableResult
    public func addMedication(name: String, dosage: String, scheduledTime: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await perform("Couldn't add medication", success: "\(name) added.") {
            try await self.repository.addMedication(seniorID: self.selectedSeniorID, name: name,
                                                    dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    scheduledTime: scheduledTime)
        }
    }

    @discardableResult
    public func updateMedication(id: String, name: String, dosage: String, scheduledTime: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return await perform("Couldn't update medication", success: "Medication updated.") {
            try await self.repository.updateMedication(id: id, name: name,
                                                       dosage: dosage.trimmingCharacters(in: .whitespacesAndNewlines),
                                                       scheduledTime: scheduledTime)
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

    public func deleteAppointment(id: String) async {
        await perform("Couldn't delete appointment", success: "Appointment removed.") {
            try await self.repository.deleteAppointment(id: id)
        }
        appointmentPrep = nil
    }

    public func triggerSOS() async {
        await perform("Couldn't send SOS") {
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
            try await repository.upsertHealthSnapshots(snapshots)
            applyRepositorySnapshot()
            healthSyncStatus.healthData = .synced
            healthSyncStatus.lastSyncDate = now()
            healthSyncStatus.lastError = nil
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
            Task { @MainActor in await self?.syncHealthData() }
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
