import Foundation

/// Account-scoped care data. Production uses `SupabaseCareRepository`; tests use an in-memory double.
/// Writes refresh `snapshot` so callers can read the result right after awaiting.
@MainActor public protocol CareRepository: AnyObject {
    var snapshot: CareSnapshot { get }
    /// Profile id of the signed-in user.
    var currentProfileID: String? { get }

    /// Re-reads the source of truth, e.g. after a realtime change from another device.
    func refresh() async throws

    func checkIn(seniorID: String, at date: Date) async throws
    func recordMood(_ mood: Mood, seniorID: String, at date: Date, note: String?) async throws

    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws
    /// Asks both of the senior's devices to show this dose again at `until`.
    func snoozeMedication(id: String, until: Date) async throws
    func addMedication(seniorID: String, name: String, dosage: String, scheduledTime: String, weekdays: [Int], endsOn: Date?) async throws
    func updateMedication(id: String, name: String, dosage: String, scheduledTime: String, weekdays: [Int], endsOn: Date?) async throws
    func deleteMedication(id: String) async throws
    /// Asks the senior's phone and watch to show this medicine now.
    func requestMedicationReminder(id: String, at date: Date) async throws

    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws
    /// Stores hourly heart rate, blood pressure, steps and sleep. The same hour is updated, not duplicated.
    func upsertHealthReadings(_ readings: [HealthReading]) async throws

    /// Inserts when `appointment.id` is empty, otherwise updates.
    func saveAppointment(_ appointment: Appointment) async throws
    func deleteAppointment(id: String) async throws
    /// Records whether a visit happened. Safe to call again with the same outcome.
    func logVisit(id: String, outcome: VisitOutcome, at date: Date) async throws

    func triggerSOS(seniorID: String, at date: Date) async throws
    func acknowledgeAlerts(seniorID: String) async throws

    func addSenior(_ senior: AccountSenior) async throws
    func updateSenior(_ senior: AccountSenior) async throws
    /// Changes when the senior is asked how they feel. Times are "9:00 AM" style, in the senior's time zone.
    func updateMoodSchedule(seniorID: String, morning: String, evening: String) async throws
    /// Asks the senior for a mood immediately, on the phone and the watch.
    func requestMoodPrompt(seniorID: String, at date: Date) async throws
    /// Clears a family "ask now" after the senior answers.
    func clearMoodPrompt(seniorID: String) async throws
    func removeSenior(id: String) async throws
    /// Links the signed-in senior member's login to a senior record.
    func claimSenior(id: String) async throws

    /// Inserts when `contact.id` is empty, otherwise updates.
    func saveEmergencyContact(_ contact: EmergencyContact) async throws
    func deleteEmergencyContact(id: String) async throws

    func sendMessage(_ body: String) async throws
    /// Uploads a short voice clip into the family conversation.
    func sendVoiceMessage(_ data: Data) async throws
    /// Records that the signed-in person has opened these messages.
    func markMessagesRead(_ ids: [String]) async throws
    func voiceAudio(path: String) async throws -> Data

    /// Updates the signed-in user's own profile.
    func updateProfile(displayName: String, city: String, phone: String) async throws
}
