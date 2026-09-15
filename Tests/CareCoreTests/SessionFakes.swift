import Foundation
@testable import CareCore

/// Repository whose snapshot is the demo seed with a chosen senior list. Writes are no-ops.
@MainActor final class StubCareRepository: CareRepository {
    var snapshot: CareSnapshot

    init(seniors: [AccountSenior]) {
        var seed = DemoCareRepository().snapshot
        seed.seniors = seniors
        snapshot = seed
    }

    func refresh() async throws {}
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
    func addSenior(_ senior: AccountSenior) async throws { snapshot.seniors.append(senior) }
    func updateSenior(_ senior: AccountSenior) async throws {}
    func reset() async {}
}

enum Fixture {
    static let accountID = "account-1"
    static let diwasID = "profile-diwas"
    static let mayaID = "profile-maya"

    static func maya(linkedTo profileID: String? = nil) -> AccountSenior {
        AccountSenior(id: "senior-maya", accountID: accountID, name: "Maya Sharma", age: 74,
                      city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu", profileID: profileID)
    }

    @MainActor static func membership(role: CareRole, seniors: [AccountSenior]) -> CareMembership {
        CareMembership(accountID: accountID, inviteCode: "ABCD1234", role: role,
                       repository: StubCareRepository(seniors: seniors))
    }
}

@MainActor final class FakeAuthSessionService: AuthSessionService {
    var state: AuthSessionState
    var validCode = "123456"
    var profileIDOnSignIn = Fixture.diwasID
    var sendError: CareServiceError?
    private(set) var sentCodes: [String] = []
    private(set) var signOutCount = 0

    init(state: AuthSessionState = .signedOut) { self.state = state }

    func restoreSession() async -> AuthSessionState { state }

    func sendEmailCode(to email: String) async throws {
        if let sendError { throw sendError }
        sentCodes.append(email)
        state = .codeSent(email: email)
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        guard code == validCode else { throw CareServiceError.invalidCode }
        state = .signedIn(AuthenticatedUser(id: profileIDOnSignIn, email: email))
    }

    func signIn(email: String, password: String) async throws {
        state = .signedIn(AuthenticatedUser(id: profileIDOnSignIn, email: email))
    }

    func signOut() async throws {
        signOutCount += 1
        state = .signedOut
    }
}

/// In-memory family backend. Server-side rules that matter to routing are mirrored here.
@MainActor final class FakeCareAccountService: CareAccountService {
    var profile = MemberProfile(displayName: "", city: "")
    var role: CareRole?
    var seniors: [AccountSenior] = []
    var signedInProfileID = Fixture.diwasID
    var validInviteCode = "ABCD1234"
    /// Thrown by the next call to any method, then cleared.
    var nextError: CareServiceError?
    private(set) var liveUpdatesRunning = false

    private func failIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func loadProfile() async throws -> MemberProfile {
        try failIfNeeded()
        return profile
    }

    func updateProfile(_ profile: MemberProfile) async throws {
        try failIfNeeded()
        self.profile = profile
    }

    func loadMembership() async throws -> CareMembership? {
        try failIfNeeded()
        guard let role else { return nil }
        return Fixture.membership(role: role, seniors: seniors)
    }

    func createFamily(name: String) async throws {
        try failIfNeeded()
        role = .family
    }

    func joinFamily(inviteCode: String, role: CareRole) async throws {
        try failIfNeeded()
        guard inviteCode == validInviteCode else { throw CareServiceError.inviteNotFound }
        self.role = role
    }

    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws {
        try failIfNeeded()
        seniors.append(AccountSenior(id: "senior-\(seniors.count + 1)", accountID: Fixture.accountID, name: name,
                                     age: age, city: city, timeZoneIdentifier: timeZoneIdentifier))
    }

    func claimSenior(id: String) async throws {
        try failIfNeeded()
        guard role == .senior else { throw CareServiceError.unauthorized }
        guard let index = seniors.firstIndex(where: { $0.id == id }) else { throw CareServiceError.invalidState("Senior not found") }
        if let owner = seniors[index].profileID, owner != signedInProfileID { throw CareServiceError.seniorAlreadyLinked }
        seniors[index].profileID = signedInProfileID
    }

    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws {
        try failIfNeeded()
        liveUpdatesRunning = true
    }

    func stopLiveUpdates() async { liveUpdatesRunning = false }
}
