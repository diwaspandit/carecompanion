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
    func addMedication(seniorID: String, name: String, dosage: String, scheduledTime: String) async throws
    func updateMedication(id: String, name: String, dosage: String, scheduledTime: String) async throws
    func deleteMedication(id: String) async throws

    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws

    /// Inserts when `appointment.id` is empty, otherwise updates.
    func saveAppointment(_ appointment: Appointment) async throws
    func deleteAppointment(id: String) async throws

    func triggerSOS(seniorID: String, at date: Date) async throws
    func acknowledgeAlerts(seniorID: String) async throws

    func addSenior(_ senior: AccountSenior) async throws
    func updateSenior(_ senior: AccountSenior) async throws
    func removeSenior(id: String) async throws
    /// Links the signed-in senior member's login to a senior record.
    func claimSenior(id: String) async throws

    /// Inserts when `contact.id` is empty, otherwise updates.
    func saveEmergencyContact(_ contact: EmergencyContact) async throws
    func deleteEmergencyContact(id: String) async throws

    func sendMessage(_ body: String) async throws

    /// Updates the signed-in user's own profile.
    func updateProfile(displayName: String, city: String, phone: String) async throws
}
