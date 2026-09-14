import Foundation

/// Repository protocol for care data operations
@MainActor public protocol CareRepository: AnyObject {
    /// Current snapshot of all care data
    var snapshot: CareSnapshot { get }

    // MARK: - Check-in Operations
    /// Record a check-in for a senior
    func checkIn(seniorID: String, at date: Date) async throws

    // MARK: - Mood Operations
    /// Record a mood entry for a senior
    func recordMood(_ mood: Mood, seniorID: String, at date: Date) async throws

    // MARK: - Medication Operations
    /// Toggle medication taken/not taken status
    func toggleMedication(id: String) async throws

    /// Record a medication event
    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws

    // MARK: - Health Data Operations
    /// Update health snapshots for a senior
    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws

    // MARK: - Appointment Operations
    /// Create or update an appointment
    func saveAppointment(_ appointment: Appointment) async throws

    /// Delete an appointment
    func deleteAppointment(id: String) async throws

    // MARK: - Alert Operations
    /// Trigger an SOS alert
    func triggerSOS(seniorID: String, at date: Date) async throws

    /// Acknowledge alerts for a senior
    func acknowledgeAlerts(seniorID: String) async throws

    // MARK: - AI Insights Operations
    /// Save a care insight
    func saveCareInsight(_ insight: CareInsight, seniorID: String) async throws

    /// Save appointment preparation
    func saveAppointmentPrep(_ prep: AppointmentPrep, appointmentID: String) async throws

    // MARK: - Account Operations
    /// Add a new senior to the account
    func addSenior(_ senior: AccountSenior) async throws

    /// Update senior profile
    func updateSenior(_ senior: AccountSenior) async throws

    // MARK: - Demo/Reset Operations
    /// Reset to initial demo state
    func reset() async
}

@MainActor public final class DemoCareRepository: CareRepository {
    public nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_788_998_400)
    public nonisolated static let mayaID = "senior-maya"
    public private(set) var snapshot: CareSnapshot
    private let seed: CareSnapshot

    public init() {
        let senior = Self.mayaID
        let account = "account-sharma"
        let date = Self.referenceDate
        let healthProvider = DemoHealthDataProvider()
        seed = CareSnapshot(
            account: CareAccount(id: account, kind: .family, name: "Sharma family"),
            members: [AccountMember(id: "member-diwas", accountID: account, name: "Diwas", city: "Austin, Texas", role: .family)],
            seniors: [AccountSenior(id: senior, accountID: account, name: "Maya Sharma", age: 74, city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu")],
            checkIns: [],
            moods: [MoodEntry(id: "mood-\(senior)", seniorID: senior, mood: .okay, date: date)],
            medications: (0..<4).map { index in
                Medication(id: "med-\(index)", seniorID: senior,
                           name: ["Amlodipine", "Metformin", "Calcium + D3", "Atorvastatin"][index],
                           scheduledTime: ["8:00 AM", "8:30 AM", "1:00 PM", "8:00 PM"][index], taken: index < 3)
            },
            health: healthProvider.snapshotsSync(seniorID: senior, endingAt: date),
            appointments: [Appointment(id: "appointment-maya", seniorID: senior, title: "Cardiology follow-up", clinician: "Dr. Shrestha", date: date.addingTimeInterval(172800), location: "Kathmandu clinic", notes: "Discuss recent sleep, daily routine, and medication timing.")],
            alerts: []
        )
        snapshot = seed
    }
    private func contains(_ seniorID: String) -> Bool {
        snapshot.seniors.contains { $0.id == seniorID }
    }

    // MARK: - Check-in Operations
    public func checkIn(seniorID: String, at date: Date) async throws {
        guard contains(seniorID) else { throw CareServiceError.invalidState("Senior not found") }
        snapshot.checkIns.removeAll { $0.seniorID == seniorID }
        snapshot.checkIns.append(CheckIn(id: "checkin-\(seniorID)", seniorID: seniorID, date: date))
    }

    // MARK: - Mood Operations
    public func recordMood(_ mood: Mood, seniorID: String, at date: Date) async throws {
        guard contains(seniorID) else { throw CareServiceError.invalidState("Senior not found") }
        snapshot.moods.removeAll { $0.seniorID == seniorID }
        snapshot.moods.append(MoodEntry(id: "mood-\(seniorID)", seniorID: seniorID, mood: mood, date: date))
    }

    // MARK: - Medication Operations
    public func toggleMedication(id: String) async throws {
        guard let index = snapshot.medications.firstIndex(where: { $0.id == id }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        snapshot.medications[index].taken.toggle()
    }

    public func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {
        guard let index = snapshot.medications.firstIndex(where: { $0.id == medicationID }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        snapshot.medications[index].taken = taken
    }

    // MARK: - Health Data Operations
    public func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws {
        for newSnapshot in snapshots {
            guard contains(newSnapshot.seniorID) else { continue }
            snapshot.health.removeAll { $0.id == newSnapshot.id }
            snapshot.health.append(newSnapshot)
        }
        snapshot.health.sort { $0.date > $1.date }
    }

    // MARK: - Appointment Operations
    public func saveAppointment(_ appointment: Appointment) async throws {
        guard contains(appointment.seniorID) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        snapshot.appointments.removeAll { $0.id == appointment.id }
        snapshot.appointments.append(appointment)
    }

    public func deleteAppointment(id: String) async throws {
        snapshot.appointments.removeAll { $0.id == id }
    }

    // MARK: - Alert Operations
    public func triggerSOS(seniorID: String, at date: Date) async throws {
        guard contains(seniorID) else { throw CareServiceError.invalidState("Senior not found") }
        guard !snapshot.alerts.contains(where: { $0.seniorID == seniorID && !$0.acknowledged }) else { return }
        snapshot.alerts.append(CareAlert(id: "alert-\(seniorID)-\(snapshot.alerts.count)", seniorID: seniorID, date: date, acknowledged: false))
    }

    public func acknowledgeAlerts(seniorID: String) async throws {
        for index in snapshot.alerts.indices where snapshot.alerts[index].seniorID == seniorID {
            snapshot.alerts[index].acknowledged = true
        }
    }

    // MARK: - AI Insights Operations
    public func saveCareInsight(_ insight: CareInsight, seniorID: String) async throws {
        guard contains(seniorID) else { throw CareServiceError.invalidState("Senior not found") }
        // In demo mode, insights are not persisted to snapshot
        // They are managed by AppState for display purposes
    }

    public func saveAppointmentPrep(_ prep: AppointmentPrep, appointmentID: String) async throws {
        guard snapshot.appointments.contains(where: { $0.id == appointmentID }) else {
            throw CareServiceError.invalidState("Appointment not found")
        }
        // In demo mode, preps are not persisted to snapshot
        // They are managed by AppState for display purposes
    }

    // MARK: - Account Operations
    public func addSenior(_ senior: AccountSenior) async throws {
        guard !snapshot.seniors.contains(where: { $0.id == senior.id }) else {
            throw CareServiceError.invalidState("Senior already exists")
        }
        snapshot.seniors.append(senior)
    }

    public func updateSenior(_ senior: AccountSenior) async throws {
        guard let index = snapshot.seniors.firstIndex(where: { $0.id == senior.id }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        snapshot.seniors[index] = senior
    }

    // MARK: - Demo/Reset Operations
    public func reset() async {
        snapshot = seed
    }
}
