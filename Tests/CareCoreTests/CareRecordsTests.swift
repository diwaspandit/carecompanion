import XCTest
@testable import CareCore

final class CareRecordsTests: XCTestCase {
    private let account = "a0000000-0000-0000-0000-000000000001"
    private let maya = "10000000-0000-0000-0000-000000000001"

    // 2026-09-14 10:00 Kathmandu (UTC+5:45) == 04:15 UTC
    private var now: Date { date("2026-09-14T04:15:00Z") }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func records(
        medications: [MedicationRow] = [],
        events: [MedicationEventRow] = [],
        health: [HealthSnapshotRow] = [],
        alerts: [AlertRow] = [],
        checkIns: [CheckInRow] = [],
        moods: [MoodEntryRow] = [],
        contacts: [EmergencyContactRow] = [],
        messages: [MessageRow] = []
    ) -> CareRecords {
        CareRecords(
            account: CareAccountRow(id: account, kind: "family", name: "Sharma family", inviteCode: "ABCD1234"),
            members: [
                AccountMemberRow(id: "m1", accountID: account, profileID: "p-diwas", role: "family",
                                 profile: .init(displayName: "Diwas", city: "Austin, Texas", phone: "+1 512 555 0142")),
                AccountMemberRow(id: "m2", accountID: account, profileID: "p-maya", role: "senior", profile: nil)
            ],
            seniors: [
                AccountSeniorRow(id: maya, accountID: account, name: "Maya Sharma", age: 74,
                                 city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu", profileID: "p-maya")
            ],
            checkIns: checkIns, moods: moods, medications: medications, medicationEvents: events,
            health: health, appointments: [], alerts: alerts, contacts: contacts, messages: messages
        )
    }

    func testAssemblesAccountMembersAndSeniors() throws {
        let snapshot = try records().snapshot(now: now)
        XCTAssertEqual(snapshot.account, CareAccount(id: account, kind: .family, name: "Sharma family", inviteCode: "ABCD1234"))
        XCTAssertEqual(snapshot.members, [
            AccountMember(id: "m1", accountID: account, profileID: "p-diwas", name: "Diwas", city: "Austin, Texas",
                          phone: "+1 512 555 0142", role: .family),
            AccountMember(id: "m2", accountID: account, profileID: "p-maya", name: "", role: .senior)
        ])
        XCTAssertEqual(snapshot.seniors.first?.timeZoneIdentifier, "Asia/Kathmandu")
        XCTAssertEqual(snapshot.seniors.first?.profileID, "p-maya")
    }

    func testMedicationTakenUsesLatestEventOnSeniorsLocalDay() throws {
        let meds = [
            MedicationRow(id: "med-a", seniorID: maya, name: "Amlodipine", dosage: "5 mg", scheduledTime: "8:00 AM"),
            MedicationRow(id: "med-b", seniorID: maya, name: "Metformin", scheduledTime: "8:30 AM"),
            MedicationRow(id: "med-c", seniorID: maya, name: "Atorvastatin", scheduledTime: "8:00 PM")
        ]
        let events = [
            // Taken, then corrected to skipped: latest wins.
            MedicationEventRow(id: "e1", medicationID: "med-a", status: "taken", occurredAt: date("2026-09-14T02:30:00Z")),
            MedicationEventRow(id: "e2", medicationID: "med-a", status: "skipped", occurredAt: date("2026-09-14T03:00:00Z")),
            // Taken today in Kathmandu (08:00 local).
            MedicationEventRow(id: "e3", medicationID: "med-b", status: "taken", occurredAt: date("2026-09-14T02:15:00Z")),
            // Taken yesterday in Kathmandu (22:00 local on the 13th).
            MedicationEventRow(id: "e4", medicationID: "med-c", status: "taken", occurredAt: date("2026-09-13T16:15:00Z"))
        ]
        let snapshot = try records(medications: meds, events: events).snapshot(now: now)
        let taken = Dictionary(uniqueKeysWithValues: snapshot.medications.map { ($0.id, $0.taken) })
        XCTAssertEqual(taken, ["med-a": false, "med-b": true, "med-c": false])
        XCTAssertEqual(snapshot.medications.first?.dosage, "5 mg")
        XCTAssertEqual(snapshot.medicationEvents.map(\.id), ["e4", "e3", "e1", "e2"], "history is kept, oldest first")
        XCTAssertTrue(snapshot.medicationEvents.allSatisfy { $0.seniorID == maya })
    }

    func testEventsForUnknownMedicationsAreDroppedAndUnknownStatusRejected() throws {
        let meds = [MedicationRow(id: "med-a", seniorID: maya, name: "Amlodipine", scheduledTime: "8:00 AM")]
        let orphan = [MedicationEventRow(id: "e1", medicationID: "deleted", status: "taken", occurredAt: now)]
        XCTAssertTrue(try records(medications: meds, events: orphan).snapshot(now: now).medicationEvents.isEmpty)

        let bad = [MedicationEventRow(id: "e2", medicationID: "med-a", status: "forgotten", occurredAt: now)]
        XCTAssertThrowsError(try records(medications: meds, events: bad).snapshot(now: now)) { error in
            XCTAssertEqual(error as? CareServiceError, .invalidState("Unknown medication event status: forgotten"))
        }
    }

    func testCheckInsOnlyCountForSeniorsLocalTodayAndMoodNotesSurvive() throws {
        let snapshot = try records(
            checkIns: [
                CheckInRow(id: "old", seniorID: maya, occurredAt: date("2026-09-13T10:00:00Z")),
                CheckInRow(id: "today", seniorID: maya, occurredAt: date("2026-09-14T03:00:00Z"))
            ],
            moods: [
                MoodEntryRow(id: "mood-old", seniorID: maya, mood: "Low", occurredAt: date("2026-09-13T03:00:00Z")),
                MoodEntryRow(id: "mood-new", seniorID: maya, mood: "Great", note: "Walked to the temple", occurredAt: date("2026-09-14T03:05:00Z"))
            ]
        ).snapshot(now: now)
        XCTAssertEqual(snapshot.checkIns.map(\.id), ["today"])
        XCTAssertEqual(snapshot.moods.last?.mood, .great)
        XCTAssertEqual(snapshot.moods.last?.note, "Walked to the temple")
    }

    func testHealthSortedNewestFirstWithSourcePreserved() throws {
        let snapshot = try records(health: [
            HealthSnapshotRow(id: "h1", seniorID: maya, snapshotDate: "2026-09-12", steps: 3000, sleepMinutes: 400, restingHeartRate: 70, source: "manual"),
            HealthSnapshotRow(id: "h2", seniorID: maya, snapshotDate: "2026-09-14", steps: 2840, sleepMinutes: 380, restingHeartRate: 72, source: "healthkit")
        ]).snapshot(now: now)
        XCTAssertEqual(snapshot.health.map(\.id), ["h2", "h1"])
        XCTAssertEqual(snapshot.health.first?.source, "healthkit")
    }

    func testContactsSortedByNameAndMessagesOldestFirst() throws {
        let snapshot = try records(
            contacts: [
                EmergencyContactRow(id: "c2", seniorID: maya, name: "sunita", relation: "Daughter", phone: "+977 1"),
                EmergencyContactRow(id: "c1", seniorID: maya, name: "Dr. Rana", relation: "Cardiologist", phone: "+977 2")
            ],
            messages: [
                MessageRow(id: "late", senderProfileID: "p-maya", body: "Yes", createdAt: date("2026-09-14T04:00:00Z")),
                MessageRow(id: "early", senderProfileID: nil, body: "Slept well?", createdAt: date("2026-09-14T03:00:00Z"))
            ]
        ).snapshot(now: now)
        XCTAssertEqual(snapshot.contacts.map(\.id), ["c1", "c2"])
        XCTAssertEqual(snapshot.messages.map(\.id), ["early", "late"])
        XCTAssertNil(snapshot.messages.first?.senderProfileID)
    }

    func testUnknownEnumValuesAreRejected() {
        var bad = records()
        bad.moods = [MoodEntryRow(id: "x", seniorID: maya, mood: "Ecstatic", occurredAt: now)]
        XCTAssertThrowsError(try bad.snapshot(now: now)) { error in
            XCTAssertEqual(error as? CareServiceError, .invalidState("Unknown mood: Ecstatic"))
        }
    }

    func testOpenAlertsAreMapped() throws {
        let snapshot = try records(alerts: [
            AlertRow(id: "a1", seniorID: maya, occurredAt: date("2026-09-14T03:00:00Z"), acknowledged: false)
        ]).snapshot(now: now)
        XCTAssertEqual(snapshot.alerts, [CareAlert(id: "a1", seniorID: maya, date: date("2026-09-14T03:00:00Z"), acknowledged: false)])
    }

    func testRowsDecodeFromPostgrestJSON() throws {
        let health = try JSONDecoder().decode(HealthSnapshotRow.self, from: Data("""
        {"id":"h1","senior_id":"s1","snapshot_date":"2026-09-14","steps":2840,
         "sleep_minutes":380,"resting_heart_rate":72,"source":"healthkit"}
        """.utf8))
        XCTAssertEqual(health.sleepMinutes, 380)

        let member = try JSONDecoder().decode(AccountMemberRow.self, from: Data("""
        {"id":"m1","account_id":"a1","profile_id":"p1","role":"family",
         "profiles":{"display_name":"Diwas","city":"Austin","phone":"+1 512"}}
        """.utf8))
        XCTAssertEqual(member.profile?.phone, "+1 512")

        let senior = try JSONDecoder().decode(AccountSeniorRow.self, from: Data("""
        {"id":"s1","account_id":"a1","name":"Maya","age":74,"city":"","time_zone_identifier":"UTC","profile_id":null}
        """.utf8))
        XCTAssertNil(senior.profileID)

        let medication = try JSONDecoder().decode(MedicationRow.self, from: Data("""
        {"id":"m1","senior_id":"s1","name":"Amlodipine","dosage":"5 mg","scheduled_time":"8:00 AM"}
        """.utf8))
        XCTAssertEqual(medication.dosage, "5 mg")
    }
}

final class RepositoryRefreshTests: XCTestCase {
    @MainActor
    func testRefreshPullsChangesMadeOutsideAppState() async throws {
        let repository = InMemoryCareRepository()
        let state = AppState(repository: repository)
        // Simulates a realtime write from the senior's phone landing in the shared repository.
        try await repository.checkIn(seniorID: InMemoryCareRepository.mayaID, at: InMemoryCareRepository.referenceDate)
        XCTAssertFalse(state.isCheckedIn)
        await state.refresh()
        XCTAssertTrue(state.isCheckedIn)
    }

    @MainActor
    func testRefreshFailureKeepsLastKnownSnapshot() async {
        let repository = FailingRefreshRepository()
        let state = AppState(repository: repository)
        let before = state.snapshot
        await state.refresh()
        XCTAssertEqual(state.snapshot, before)
        XCTAssertEqual(state.toastMessage, "Couldn't refresh care data: Service is offline. Please check your connection.")
    }

    @MainActor
    func testFailedWriteShowsErrorAndKeepsSnapshot() async {
        let state = AppState(repository: FailingRefreshRepository())
        let before = state.snapshot
        let sent = await state.sendMessage("hello")
        XCTAssertFalse(sent)
        XCTAssertEqual(state.snapshot, before)
        XCTAssertEqual(state.toastMessage, "Message not sent: Service is offline. Please check your connection.")
    }
}

@MainActor
private final class FailingRefreshRepository: CareRepository {
    private let backing = InMemoryCareRepository()
    var snapshot: CareSnapshot { backing.snapshot }
    var currentProfileID: String? { backing.currentProfileID }
    func refresh() async throws { throw CareServiceError.offline }
    func checkIn(seniorID: String, at date: Date) async throws { throw CareServiceError.offline }
    func recordMood(_ mood: Mood, seniorID: String, at date: Date, note: String?) async throws { throw CareServiceError.offline }
    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws { throw CareServiceError.offline }
    func addMedication(seniorID: String, name: String, dosage: String, scheduledTime: String) async throws { throw CareServiceError.offline }
    func updateMedication(id: String, name: String, dosage: String, scheduledTime: String) async throws { throw CareServiceError.offline }
    func deleteMedication(id: String) async throws { throw CareServiceError.offline }
    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws { throw CareServiceError.offline }
    func saveAppointment(_ appointment: Appointment) async throws { throw CareServiceError.offline }
    func deleteAppointment(id: String) async throws { throw CareServiceError.offline }
    func triggerSOS(seniorID: String, at date: Date) async throws { throw CareServiceError.offline }
    func acknowledgeAlerts(seniorID: String) async throws { throw CareServiceError.offline }
    func addSenior(_ senior: AccountSenior) async throws { throw CareServiceError.offline }
    func updateSenior(_ senior: AccountSenior) async throws { throw CareServiceError.offline }
    func removeSenior(id: String) async throws { throw CareServiceError.offline }
    func claimSenior(id: String) async throws { throw CareServiceError.offline }
    func saveEmergencyContact(_ contact: EmergencyContact) async throws { throw CareServiceError.offline }
    func deleteEmergencyContact(id: String) async throws { throw CareServiceError.offline }
    func sendMessage(_ body: String) async throws { throw CareServiceError.offline }
    func updateProfile(displayName: String, city: String, phone: String) async throws { throw CareServiceError.offline }
}

final class AuthValidationTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertTrue(EmailAddress.isValid("diwas@example.com"))
        XCTAssertTrue(EmailAddress.isValid("  maya.sharma+care@example.org "))
        XCTAssertFalse(EmailAddress.isValid(""))
        XCTAssertFalse(EmailAddress.isValid("not-an-email"))
        XCTAssertFalse(EmailAddress.isValid("a@b"))
        XCTAssertFalse(EmailAddress.isValid("a @b.com"))
    }
}
