import CareCore
import Foundation
import Observation
import Supabase

/// Owns the signed-in session: authentication, the user's profile, their care account and the
/// `AppState` built on it. `RootView` renders whatever `phase` says comes next.
@MainActor @Observable final class SessionController {
    enum Phase: Equatable {
        case notConfigured
        case launching
        case welcome
        case checkEmail(String)
        case passwordResetSent(String)
        case chooseNewPassword
        case loadingAccount
        case loadFailed(String)
        case profileSetup
        case accountSetup
        case ready
    }

    private(set) var authState: AuthSessionState = .signedOut
    private(set) var profile: UserProfileDetails?
    private(set) var repository: SupabaseCareRepository?
    private(set) var appState: AppState?
    private(set) var isRestoring = true
    private(set) var isBusy = false
    private(set) var loadError: String?
    private(set) var isRealtimeConnected = false
    /// Form-level error for the screen currently asking the user for input.
    var errorMessage: String?

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let auth: SupabaseAuthSessionService?
    @ObservationIgnored private let healthProvider = HealthKitHealthDataProvider()
    private var hasLoadedAccount = false

    init(client: SupabaseClient? = SupabaseConfig.sharedClient) {
        self.client = client
        self.auth = client.map(SupabaseAuthSessionService.init)
    }

    var signedInUser: AuthenticatedUser? {
        if case .signedIn(let user) = authState { user } else { nil }
    }

    var phase: Phase {
        guard client != nil else { return .notConfigured }
        if isRestoring { return .launching }
        switch authState {
        case .signedOut: return .welcome
        case .awaitingEmailConfirmation(let email): return .checkEmail(email)
        case .passwordResetSent(let email): return .passwordResetSent(email)
        case .recoveringPassword: return .chooseNewPassword
        case .signedIn:
            if let loadError { return .loadFailed(loadError) }
            guard hasLoadedAccount, let profile else { return .loadingAccount }
            if profile.displayName.trimmingCharacters(in: .whitespaces).isEmpty { return .profileSetup }
            return appState == nil ? .accountSetup : .ready
        }
    }

    // MARK: - Authentication

    func restore() async {
        defer { isRestoring = false }
        guard let auth else { return }
        authState = await auth.restoreSession()
        if signedInUser != nil { await loadAccount() }
    }

    func signIn(email: String, password: String) async {
        guard let auth else { return }
        if await run({ try await auth.signIn(email: email, password: password) }) {
            authState = auth.state
            await loadAccount()
        }
    }

    func signUp(email: String, password: String) async {
        guard let auth else { return }
        if await run({ try await auth.signUp(email: email, password: password, displayName: "") }) {
            authState = auth.state
            if signedInUser != nil { await loadAccount() }
        }
    }

    func sendPasswordReset(email: String) async {
        guard let auth else { return }
        if await run({ try await auth.sendPasswordReset(to: email) }) {
            authState = auth.state
        }
    }

    func updatePassword(_ password: String) async {
        guard let auth else { return }
        if await run({ try await auth.updatePassword(password) }) {
            authState = auth.state
            await loadAccount()
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard let auth else { return }
        if await run({ try await auth.handleOpenURL(url) }) {
            authState = auth.state
            if signedInUser != nil { await loadAccount() }
        }
    }

    func returnToSignIn() {
        auth?.returnToSignIn()
        authState = .signedOut
        errorMessage = nil
    }

    func signOut() async {
        guard let auth else { return }
        await clearAccount()
        try? await auth.signOut()
        authState = .signedOut
    }

    /// Permanently deletes the login, the profile and any care account nobody else belongs to.
    func deleteAccount() async -> Bool {
        guard let client, let auth else { return false }
        guard await run({ try await SupabaseCareRepository.deleteMyAccount(client: client) }) else { return false }
        await clearAccount()
        try? await auth.signOut()
        authState = .signedOut
        return true
    }

    // MARK: - Profile and account

    func retryLoading() async {
        loadError = nil
        await loadAccount()
    }

    func saveProfile(displayName: String, city: String, phone: String) async {
        guard let client else { return }
        let details = UserProfileDetails(displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                         city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                                         phone: phone.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !details.displayName.isEmpty else {
            errorMessage = "Enter your name so your family knows who you are."
            return
        }
        if await run({ try await SupabaseCareRepository.saveProfile(client: client, details) }) {
            profile = details
        }
    }

    func createAccount(name: String, role: CareRole) async {
        guard let client else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Give your family a name, for example \"Sharma family\"."
            return
        }
        if await run({ try await SupabaseCareRepository.createAccount(client: client, name: name, role: role) }) {
            await loadRepository()
        }
    }

    func joinAccount(code: String, role: CareRole) async {
        guard let client else { return }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            errorMessage = "Enter the invite code from your family."
            return
        }
        if await run({ try await SupabaseCareRepository.joinAccount(client: client, inviteCode: code, role: role) }) {
            await loadRepository()
        }
    }

    /// Called when the app returns to the foreground.
    func refreshForForeground() async {
        guard let appState else { return }
        await appState.refresh()
        await appState.syncHealthData()
    }

    // MARK: - Private

    private func loadAccount() async {
        guard let client else { return }
        do {
            profile = try await SupabaseCareRepository.loadProfile(client: client)
            try await loadRepositoryOrThrow()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        hasLoadedAccount = true
    }

    private func loadRepository() async {
        do {
            try await loadRepositoryOrThrow()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRepositoryOrThrow() async throws {
        guard let client else { return }
        do {
            let loaded = try await SupabaseCareRepository.load(client: client)
            await start(loaded)
        } catch CareServiceError.invalidState {
            // Signed in, but not part of a care account yet.
            await clearRepository()
        }
    }

    private func start(_ loaded: SupabaseCareRepository) async {
        await clearRepository()
        let state = AppState(repository: loaded, healthProvider: healthProvider)
        repository = loaded
        appState = state
        do {
            try await loaded.startRealtime { [weak state] in
                await state?.refresh()
            }
            isRealtimeConnected = true
        } catch {
            isRealtimeConnected = false
        }
        await state.setupAutomaticHealthSync()
        await state.syncHealthData()
    }

    private func clearRepository() async {
        await appState?.teardownAutomaticHealthSync()
        await repository?.stopRealtime()
        repository = nil
        appState = nil
        isRealtimeConnected = false
    }

    private func clearAccount() async {
        await clearRepository()
        profile = nil
        loadError = nil
        errorMessage = nil
        hasLoadedAccount = false
    }

    private func run(_ work: () async throws -> Void) async -> Bool {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
