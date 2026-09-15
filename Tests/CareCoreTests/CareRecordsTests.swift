import XCTest
@testable import CareCore

final class CareRecordsTests: XCTestCase {
    private let account = "a0000000-0000-0000-0000-000000000001"
    private let maya = "10000000-0000-0000-0000-000000000001"
    private let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!

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
        moods: [MoodEntryRow] = []
    ) -> CareRecords {
        CareRecords(
            account: CareAccountRow(id: account, kind: "family", name: "Sharma family", inviteCode: "ABCD1234"),
            members: [
                AccountMemberRow(id: "m1", accountID: account, profileID: "p-diwas", role: "family",
                                 profile: .init(displayName: "Diwas", city: "Austin, Texas"))
            ],
            seniors: [
                AccountSeniorRow(id: maya, accountID: account, name: "Maya Sharma", age: 74,
                                 city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu")
            ],
            checkIns: checkIns, moods: moods, medications: medications, medicationEvents: events,
            health: health, appointments: [], alerts: alerts
        )
    }

    func testAssemblesAccountMembersAndSeniors() throws {
        let snapshot = try records().snapshot(now: now)
        XCTAssertEqual(snapshot.account, CareAccount(id: account, kind: .family, name: "Sharma family"))
        XCTAssertEqual(snapshot.members, [AccountMember(id: "m1", accountID: account, name: "Diwas", city: "Austin, Texas", role: .family)])
        XCTAssertEqual(snapshot.seniors.first?.timeZoneIdentifier, "Asia/Kathmandu")
    }

    func testMedicationTakenUsesLatestEventOnSeniorsLocalDay() throws {
        let meds = [
            MedicationRow(id: "med-a", seniorID: maya, name: "Amlodipine", scheduledTime: "8:00 AM"),
            MedicationRow(id: "med-b", seniorID: maya, name: "Metformin", scheduledTime: "8:30 AM"),
            MedicationRow(id: "med-c", seniorID: maya, name: "Atorvastatin", scheduledTime: "8:00 PM")
        ]
        let events = [
            // Taken, then corrected to skipped: latest wins.
            MedicationEventRow(id: "e1", medicationID: "med-a", status: "taken", occurredAt: date("2026-09-14T02:30:00Z")),
            MedicationEventRow(id: "e2", medicationID: "med-a", status: "skipped", occurredAt: date("2026-09-14T03:00:00Z")),
            // Taken today in Kathmandu (08:00 local).
            MedicationEventRow(id: "e3", medicationID: "med-b", status: "taken", occurredAt: date("2026-09-14T02:15:00Z")),
            // Taken yesterday in Kathmandu (22:00 local on the 13th) even though it is the 13th 16:15 UTC.
            MedicationEventRow(id: "e4", medicationID: "med-c", status: "taken", occurredAt: date("2026-09-13T16:15:00Z"))
        ]
        let snapshot = try records(medications: meds, events: events).snapshot(now: now)
        let taken = Dictionary(uniqueKeysWithValues: snapshot.medications.map { ($0.id, $0.taken) })
        XCTAssertEqual(taken, ["med-a": false, "med-b": true, "med-c": false])
    }

    func testCheckInsAndMoodsOnlyCountForSeniorsLocalToday() throws {
        let snapshot = try records(
            checkIns: [
                CheckInRow(id: "old", seniorID: maya, occurredAt: date("2026-09-13T10:00:00Z")),
                CheckInRow(id: "today", seniorID: maya, occurredAt: date("2026-09-14T03:00:00Z"))
            ],
            moods: [
                MoodEntryRow(id: "mood-old", seniorID: maya, mood: "Low", occurredAt: date("2026-09-13T03:00:00Z")),
                MoodEntryRow(id: "mood-new", seniorID: maya, mood: "Great", occurredAt: date("2026-09-14T03:05:00Z"))
            ]
        ).snapshot(now: now)
        XCTAssertEqual(snapshot.checkIns.map(\.id), ["today"])
        XCTAssertEqual(snapshot.moods.last?.mood, .great)
    }

    func testHealthSortedNewestFirstWithSourcePreserved() throws {
        let snapshot = try records(health: [
            HealthSnapshotRow(id: "h1", seniorID: maya, snapshotDate: "2026-09-12", steps: 3000, sleepMinutes: 400, restingHeartRate: 70, source: "manual"),
            HealthSnapshotRow(id: "h2", seniorID: maya, snapshotDate: "2026-09-14", steps: 2840, sleepMinutes: 380, restingHeartRate: 72, source: "healthkit")
        ]).snapshot(now: now)
        XCTAssertEqual(snapshot.health.map(\.id), ["h2", "h1"])
        XCTAssertEqual(snapshot.health.first?.source, "healthkit")
    }

    func testUnknownEnumValuesAreRejected() {
        var bad = records()
        bad.moods = [MoodEntryRow(id: "x", seniorID: maya, mood: "Ecstatic", occurredAt: now)]
        XCTAssertThrowsError(try bad.snapshot(now: now)) { error in
            XCTAssertEqual(error as? CareServiceError, .invalidState("Unknown mood: Ecstatic"))
        }
    }

    func testOnlyOpenAlertsAndAcknowledgedHistoryAreMapped() throws {
        let snapshot = try records(alerts: [
            AlertRow(id: "a1", seniorID: maya, occurredAt: date("2026-09-14T03:00:00Z"), acknowledged: false)
        ]).snapshot(now: now)
        XCTAssertEqual(snapshot.alerts, [CareAlert(id: "a1", seniorID: maya, date: date("2026-09-14T03:00:00Z"), acknowledged: false)])
    }

    func testRowsDecodeFromPostgrestJSON() throws {
        let json = """
        {"id":"h1","senior_id":"s1","snapshot_date":"2026-09-14","steps":2840,
         "sleep_minutes":380,"resting_heart_rate":72,"source":"demo"}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(HealthSnapshotRow.self, from: json)
        XCTAssertEqual(row.sleepMinutes, 380)
        XCTAssertEqual(row.snapshotDate, "2026-09-14")
    }
}

final class RepositoryRefreshTests: XCTestCase {
    @MainActor
    func testRefreshPullsChangesMadeOutsideAppState() async throws {
        let repository = DemoCareRepository()
        let state = AppState(repository: repository)
        // Simulates a realtime write from Maya's phone landing in the shared repository.
        try await repository.checkIn(seniorID: DemoCareRepository.mayaID, at: DemoCareRepository.referenceDate)
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
}

@MainActor
private final class FailingRefreshRepository: CareRepository {
    private let demo = DemoCareRepository()
    var snapshot: CareSnapshot { demo.snapshot }
    func refresh() async throws { throw CareServiceError.offline }
    func checkIn(seniorID: String, at date: Date) async throws {}
    func recordMood(_ mood: Mood, seniorID: String, at date: Date) async throws {}
    func toggleMedication(id: String) async throws {}
    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {}
    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws {}
    func saveAppointment(_ appointment: Appointment) async throws {}
    func deleteAppointment(id: String) async throws {}
    func triggerSOS(seniorID: String, at date: Date) async throws {}
    func acknowledgeAlerts(seniorID: String) async throws {}
    func saveCareInsight(_ insight: CareInsight, seniorID: String) async throws {}
    func saveAppointmentPrep(_ prep: AppointmentPrep, appointmentID: String) async throws {}
    func addSenior(_ senior: AccountSenior) async throws {}
    func updateSenior(_ senior: AccountSenior) async throws {}
    func reset() async {}
}

final class AuthSessionTests: XCTestCase {
    func testEmailValidation() {
        XCTAssertTrue(EmailAddress.isValid("diwas@example.com"))
        XCTAssertTrue(EmailAddress.isValid("  maya.sharma+care@example.org "))
        XCTAssertFalse(EmailAddress.isValid(""))
        XCTAssertFalse(EmailAddress.isValid("not-an-email"))
        XCTAssertFalse(EmailAddress.isValid("a@b"))
        XCTAssertFalse(EmailAddress.isValid("a @b.com"))
    }

    @MainActor
    func testDemoAuthNeverRequiresNetworkOrSignIn() async throws {
        let auth = DemoAuthSessionService()
        let restored = await auth.restoreSession()
        XCTAssertEqual(restored, .demo)
        try await auth.sendEmailCode(to: "diwas@example.com")
        try await auth.verifyEmailCode("123456", email: "diwas@example.com")
        try await auth.signIn(email: "diwas@example.com", password: "unused")
        XCTAssertEqual(auth.state, .demo)
        try await auth.signOut()
        XCTAssertEqual(auth.state, .demo)
    }

    func testOnboardingErrorsHaveDescriptions() {
        for error in [CareServiceError.invalidCode, .inviteNotFound, .seniorAlreadyLinked] {
            XCTAssertNotNil(error.errorDescription)
        }
    }
}
