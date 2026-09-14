import Foundation

@MainActor public protocol CareRepository: AnyObject {
    var snapshot: CareSnapshot { get }
    func checkIn(seniorID: String, at date: Date)
    func recordMood(_ mood: Mood, seniorID: String, at date: Date)
    func toggleMedication(id: String)
    func triggerSOS(seniorID: String, at date: Date)
    func acknowledgeAlerts(seniorID: String)
    func reset()
}

@MainActor public final class DemoCareRepository: CareRepository {
    public nonisolated static let referenceDate = Date(timeIntervalSince1970: 1_788_998_400)
    public nonisolated static let mayaID = "senior-maya"
    public private(set) var snapshot: CareSnapshot
    private let seed: CareSnapshot

    public init(healthProvider: any HealthDataProvider = DemoHealthDataProvider()) {
        let senior = Self.mayaID
        let account = "account-sharma"
        let date = Self.referenceDate
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
            health: healthProvider.snapshots(seniorID: senior, endingAt: date),
            appointments: [Appointment(id: "appointment-maya", seniorID: senior, title: "Cardiology follow-up", clinician: "Dr. Shrestha", date: date.addingTimeInterval(172800), location: "Kathmandu clinic", notes: "Discuss recent sleep, daily routine, and medication timing.")],
            alerts: []
        )
        snapshot = seed
    }
    private func contains(_ seniorID: String) -> Bool {
        snapshot.seniors.contains { $0.id == seniorID }
    }
    public func checkIn(seniorID: String, at date: Date) {
        guard contains(seniorID) else { return }
        snapshot.checkIns.removeAll { $0.seniorID == seniorID }
        snapshot.checkIns.append(CheckIn(id: "checkin-\(seniorID)", seniorID: seniorID, date: date))
    }
    public func recordMood(_ mood: Mood, seniorID: String, at date: Date) {
        guard contains(seniorID) else { return }
        snapshot.moods.removeAll { $0.seniorID == seniorID }
        snapshot.moods.append(MoodEntry(id: "mood-\(seniorID)", seniorID: seniorID, mood: mood, date: date))
    }
    public func toggleMedication(id: String) {
        guard let index = snapshot.medications.firstIndex(where: { $0.id == id }) else { return }
        snapshot.medications[index].taken.toggle()
    }
    public func triggerSOS(seniorID: String, at date: Date) {
        guard contains(seniorID), !snapshot.alerts.contains(where: { $0.seniorID == seniorID && !$0.acknowledged }) else { return }
        snapshot.alerts.append(CareAlert(id: "alert-\(seniorID)-\(snapshot.alerts.count)", seniorID: seniorID, date: date, acknowledged: false))
    }
    public func acknowledgeAlerts(seniorID: String) {
        for index in snapshot.alerts.indices where snapshot.alerts[index].seniorID == seniorID {
            snapshot.alerts[index].acknowledged = true
        }
    }
    public func reset() { snapshot = seed }
}
