import Foundation
@testable import CareCore

/// In-memory `CareRepository` with a small, fixed family used across the unit tests.
@MainActor final class InMemoryCareRepository: CareRepository {
    nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_788_998_400)
    nonisolated static let mayaID = "senior-maya"
    nonisolated static let diwasProfileID = "profile-diwas"
    nonisolated static let mayaProfileID = "profile-maya"

    private(set) var snapshot: CareSnapshot
    let currentProfileID: String?
    private var nextID = 0

    init(currentProfileID: String? = InMemoryCareRepository.diwasProfileID, mayaLinked: Bool = false) {
        self.currentProfileID = currentProfileID
        let senior = Self.mayaID
        let account = "account-sharma"
        let date = Self.referenceDate
        snapshot = CareSnapshot(
            account: CareAccount(id: account, kind: .family, name: "Sharma family", inviteCode: "ABCD1234"),
            members: [
                AccountMember(id: "member-diwas", accountID: account, profileID: Self.diwasProfileID, name: "Diwas",
                              city: "Austin, Texas", phone: "+1 512 555 0142", role: .family),
                AccountMember(id: "member-maya", accountID: account, profileID: Self.mayaProfileID, name: "Maya",
                              city: "Kathmandu, Nepal", phone: "+977 98 5100 1122", role: .senior)
            ],
            seniors: [AccountSenior(id: senior, accountID: account, name: "Maya Sharma", age: 74, city: "Kathmandu, Nepal",
                                    timeZoneIdentifier: "Asia/Kathmandu", profileID: mayaLinked ? Self.mayaProfileID : nil)],
            checkIns: [],
            moods: [MoodEntry(id: "mood-\(senior)", seniorID: senior, mood: .okay, date: date, note: nil)],
            medications: (0..<4).map { index in
                Medication(id: "med-\(index)", seniorID: senior,
                           name: ["Amlodipine", "Metformin", "Calcium + D3", "Atorvastatin"][index],
                           dosage: ["5 mg", "500 mg", "1 tablet", "10 mg"][index],
                           scheduledTime: ["8:00 AM", "8:30 AM", "1:00 PM", "8:00 PM"][index], taken: index < 3)
            },
            health: zip([2840, 3120, 2680, 3400, 2950, 3200, 3050], [380, 410, 395, 420, 405, 390, 415])
                .enumerated()
                .map { day, values in
                    HealthSnapshot(id: "health-\(senior)-\(day)", seniorID: senior,
                                   date: date.addingTimeInterval(Double(-day) * 86_400),
                                   steps: values.0, sleepMinutes: values.1, restingHeartRate: 72, source: "manual")
                },
            appointments: [Appointment(id: "appointment-maya", seniorID: senior, title: "Cardiology follow-up",
                                       clinician: "Dr. Shrestha", date: date.addingTimeInterval(172_800),
                                       location: "Kathmandu clinic",
                                       notes: "Discuss recent sleep, daily routine, and medication timing.")],
            alerts: []
        )
    }

    func refresh() async throws {}

    func checkIn(seniorID: String, at date: Date) async throws {
        try requireSenior(seniorID)
        snapshot.checkIns.removeAll { $0.seniorID == seniorID }
        snapshot.checkIns.append(CheckIn(id: "checkin-\(seniorID)", seniorID: seniorID, date: date))
    }

    func recordMood(_ mood: Mood, seniorID: String, at date: Date, note: String?) async throws {
        try requireSenior(seniorID)
        snapshot.moods.removeAll { $0.seniorID == seniorID }
        snapshot.moods.append(MoodEntry(id: "mood-\(seniorID)", seniorID: seniorID, mood: mood, date: date, note: note))
    }

    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {
        guard let index = snapshot.medications.firstIndex(where: { $0.id == medicationID }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        snapshot.medications[index].taken = taken
        snapshot.medicationEvents.append(MedicationEvent(id: makeID("event"), medicationID: medicationID,
                                                         seniorID: snapshot.medications[index].seniorID,
                                                         status: taken ? .taken : .skipped, date: date))
    }

    func addMedication(seniorID: String, name: String, dosage: String, scheduledTime: String) async throws {
        try requireSenior(seniorID)
        snapshot.medications.append(Medication(id: makeID("med"), seniorID: seniorID, name: name, dosage: dosage,
                                               scheduledTime: scheduledTime))
    }

    func updateMedication(id: String, name: String, dosage: String, scheduledTime: String) async throws {
        guard let index = snapshot.medications.firstIndex(where: { $0.id == id }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        snapshot.medications[index].name = name
        snapshot.medications[index].dosage = dosage
        snapshot.medications[index].scheduledTime = scheduledTime
    }

    func deleteMedication(id: String) async throws {
        snapshot.medications.removeAll { $0.id == id }
    }

    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws {
        for item in snapshots where snapshot.seniors.contains(where: { $0.id == item.seniorID }) {
            snapshot.health.removeAll {
                $0.seniorID == item.seniorID && $0.source == item.source
                    && CareRecords.dateOnly.string(from: $0.date) == CareRecords.dateOnly.string(from: item.date)
            }
            snapshot.health.append(item)
        }
        snapshot.health.sort { $0.date > $1.date }
    }

    func saveAppointment(_ appointment: Appointment) async throws {
        try requireSenior(appointment.seniorID)
        if appointment.id.isEmpty {
            snapshot.appointments.append(Appointment(id: makeID("appointment"), seniorID: appointment.seniorID,
                                                     title: appointment.title, clinician: appointment.clinician,
                                                     date: appointment.date, location: appointment.location,
                                                     notes: appointment.notes))
        } else {
            snapshot.appointments.removeAll { $0.id == appointment.id }
            snapshot.appointments.append(appointment)
        }
    }

    func deleteAppointment(id: String) async throws {
        snapshot.appointments.removeAll { $0.id == id }
    }

    func triggerSOS(seniorID: String, at date: Date) async throws {
        try requireSenior(seniorID)
        guard !snapshot.alerts.contains(where: { $0.seniorID == seniorID && !$0.acknowledged }) else { return }
        snapshot.alerts.append(CareAlert(id: makeID("alert"), seniorID: seniorID, date: date, acknowledged: false))
    }

    func acknowledgeAlerts(seniorID: String) async throws {
        for index in snapshot.alerts.indices where snapshot.alerts[index].seniorID == seniorID {
            snapshot.alerts[index].acknowledged = true
        }
    }

    func addSenior(_ senior: AccountSenior) async throws {
        snapshot.seniors.append(AccountSenior(id: senior.id.isEmpty ? makeID("senior") : senior.id,
                                              accountID: senior.accountID, name: senior.name, age: senior.age,
                                              city: senior.city, timeZoneIdentifier: senior.timeZoneIdentifier,
                                              profileID: senior.profileID))
    }

    func updateSenior(_ senior: AccountSenior) async throws {
        guard let index = snapshot.seniors.firstIndex(where: { $0.id == senior.id }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        snapshot.seniors[index] = senior
    }

    func removeSenior(id: String) async throws {
        snapshot.seniors.removeAll { $0.id == id }
    }

    func claimSenior(id: String) async throws {
        guard let currentProfileID,
              snapshot.members.contains(where: { $0.profileID == currentProfileID && $0.role == .senior }) else {
            throw CareServiceError.unauthorized
        }
        guard let index = snapshot.seniors.firstIndex(where: { $0.id == id }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        for other in snapshot.seniors.indices where snapshot.seniors[other].profileID == currentProfileID {
            snapshot.seniors[other].profileID = nil
        }
        snapshot.seniors[index].profileID = currentProfileID
    }

    func saveEmergencyContact(_ contact: EmergencyContact) async throws {
        try requireSenior(contact.seniorID)
        if contact.id.isEmpty {
            snapshot.contacts.append(EmergencyContact(id: makeID("contact"), seniorID: contact.seniorID, name: contact.name,
                                                      relation: contact.relation, phone: contact.phone))
        } else {
            guard let index = snapshot.contacts.firstIndex(where: { $0.id == contact.id }) else {
                throw CareServiceError.invalidState("Contact not found")
            }
            snapshot.contacts[index] = contact
        }
    }

    func deleteEmergencyContact(id: String) async throws {
        snapshot.contacts.removeAll { $0.id == id }
    }

    func sendMessage(_ body: String) async throws {
        snapshot.messages.append(CareMessage(id: makeID("message"), senderProfileID: currentProfileID, body: body,
                                             date: Self.referenceDate.addingTimeInterval(Double(nextID))))
    }

    func updateProfile(displayName: String, city: String, phone: String) async throws {
        guard let index = snapshot.members.firstIndex(where: { $0.profileID == currentProfileID }) else {
            throw CareServiceError.unauthorized
        }
        snapshot.members[index].name = displayName
        snapshot.members[index].city = city
        snapshot.members[index].phone = phone
    }

    private func requireSenior(_ seniorID: String) throws {
        guard snapshot.seniors.contains(where: { $0.id == seniorID }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
    }

    private func makeID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)-\(nextID)"
    }
}

/// Health provider double: returns three days of fixed data for whichever senior is syncing.
struct StubHealthDataProvider: HealthDataProvider {
    var status: HealthPermissionStatus = .authorized

    func permissionStatus() async -> HealthPermissionStatus { status }
    func requestPermission() async throws {}
    func startBackgroundSync() async throws {}
    func stopBackgroundSync() async {}

    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return HealthDayAggregator.snapshots(
            seniorID: seniorID,
            steps: [HealthDayAggregator.dayKey(for: date, calendar: calendar): 4200,
                    HealthDayAggregator.dayKey(for: date.addingTimeInterval(-86_400), calendar: calendar): 5100],
            sleepMinutes: [HealthDayAggregator.dayKey(for: date, calendar: calendar): 400],
            restingHeartRate: [HealthDayAggregator.dayKey(for: date, calendar: calendar): 64],
            days: 3, endingAt: date, calendar: calendar)
    }
}
