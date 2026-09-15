import CareCore
import Foundation
import Observation
import Supabase

/// Developer path into production data: sign in, create/join a family account, then swap the
/// app's AppState onto SupabaseCareRepository with realtime refresh. Demo remains the default.
@MainActor @Observable final class LiveModeController {
    private(set) var authState: AuthSessionState = .signedOut
    private(set) var repository: SupabaseCareRepository?
    private(set) var liveState: AppState?
    private(set) var isRealtimeConnected = false
    private(set) var isBusy = false
    var message: String?

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let auth: SupabaseAuthSessionService?

    init(client: SupabaseClient? = SupabaseConfig.sharedClient) {
        self.client = client
        self.auth = client.map(SupabaseAuthSessionService.init)
    }

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { if case .signedIn = authState { true } else { false } }
    var signedInEmail: String? { if case .signedIn(let user) = authState { user.email } else { nil } }
    var signedInProfileID: String? { if case .signedIn(let user) = authState { user.id } else { nil } }
    /// Account whose data is on screen; nil in demo mode.
    var liveAccountID: String? { isLive ? repository?.accountID : nil }
    /// The senior record this login is linked to, if any (their own device).
    var linkedSenior: AccountSenior? {
        guard let signedInProfileID else { return nil }
        return repository?.snapshot.seniors.first { $0.profileID == signedInProfileID }
    }
    var hasAccount: Bool { repository != nil }
    var hasSenior: Bool { !(repository?.snapshot.seniors.isEmpty ?? true) }
    var isLive: Bool { liveState != nil }

    func restore() async {
        guard let auth else { return }
        authState = await auth.restoreSession()
        if isSignedIn { await loadAccount(reportMissing: false) }
    }

    func sendMagicLink(to email: String) async {
        await run { try await self.auth?.sendMagicLink(to: email) }
        authState = auth?.state ?? .signedOut
        if case .magicLinkSent(let email) = authState { message = "Magic link sent to \(email). Open it on this device." }
    }

    func signIn(email: String, password: String) async {
        await run { try await self.auth?.signIn(email: email, password: password) }
        authState = auth?.state ?? .signedOut
        if isSignedIn { await loadAccount(reportMissing: false) }
    }

    func handleOpenURL(_ url: URL) async {
        await run { try await self.auth?.handleOpenURL(url) }
        authState = auth?.state ?? .signedOut
        if isSignedIn { await loadAccount(reportMissing: false) }
    }

    func createAccount(name: String, role: CareRole) async {
        guard let client else { return }
        await run { try await SupabaseCareRepository.createAccount(client: client, name: name, role: role) }
        await loadAccount(reportMissing: true)
    }

    func joinAccount(code: String, role: CareRole) async {
        guard let client else { return }
        await run { try await SupabaseCareRepository.joinAccount(client: client, inviteCode: code, role: role) }
        await loadAccount(reportMissing: true)
    }

    func addSenior(name: String, age: Int, city: String, timeZone: String) async {
        guard let repository else { return }
        let senior = AccountSenior(id: UUID().uuidString, accountID: repository.accountID, name: name,
                                   age: age, city: city, timeZoneIdentifier: timeZone)
        await run { try await repository.addSenior(senior) }
    }

    /// Adds a starter medication schedule and one visit for the first senior. No health metrics:
    /// seeded values must never look like Apple Health data.
    func addStarterCarePlan() async {
        guard let repository, let senior = repository.snapshot.seniors.first else { return }
        await run {
            for (name, time) in [("Amlodipine", "8:00 AM"), ("Metformin", "8:30 AM"),
                                 ("Calcium + D3", "1:00 PM"), ("Atorvastatin", "8:00 PM")] {
                try await repository.addMedication(seniorID: senior.id, name: name, scheduledTime: time)
            }
            try await repository.saveAppointment(Appointment(
                id: "new", seniorID: senior.id, title: "Cardiology follow-up", clinician: "Dr. Shrestha",
                date: Date().addingTimeInterval(2 * 86_400), location: "Kathmandu clinic",
                notes: "Discuss recent sleep, daily routine, and medication timing."))
        }
        await liveState?.refresh()
    }

    /// "I am this senior": links this login so this device may share the senior's Apple Health data.
    func claimSenior(id: String) async {
        guard let repository else { return }
        await run { try await repository.claimSeniorProfile(seniorID: id) }
        await liveState?.refresh()
    }

    func goLive() async {
        guard let repository, hasSenior else { return }
        let state = AppState(repository: repository, healthProvider: HealthKitHealthDataProvider(),
                             currentProfileID: signedInProfileID, now: Date.init)
        if let linkedSenior { state.selectSenior(id: linkedSenior.id) }
        liveState = state
        do {
            try await repository.startRealtime { [weak state] in
                await state?.refresh()
            }
            isRealtimeConnected = true
        } catch {
            isRealtimeConnected = false
            message = "Live data loaded, but realtime is unavailable: \(error.localizedDescription)"
        }
    }

    func returnToDemo() async {
        await repository?.stopRealtime()
        isRealtimeConnected = false
        liveState = nil
    }

    func signOut() async {
        await returnToDemo()
        await run { try await self.auth?.signOut() }
        repository = nil
        authState = auth?.state ?? .signedOut
    }

    private func loadAccount(reportMissing: Bool) async {
        guard let client else { return }
        do {
            repository = try await SupabaseCareRepository.load(client: client)
        } catch CareServiceError.invalidState {
            repository = nil
            if reportMissing { message = "No care account found for this user." }
        } catch {
            message = error.localizedDescription
        }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
    }
}
