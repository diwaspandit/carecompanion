import CareCore
import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

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
    @ObservationIgnored private let watchRelay = WatchSessionRelay()
    @ObservationIgnored private let reachability = CareReachability()
    @ObservationIgnored private var healthClock: Task<Void, Never>?
    private var pendingWatchHealth: WatchHealthReport?
    private var pendingOpenMessages = false
    private var hasLoadedAccount = false

    init(client: SupabaseClient? = SupabaseConfig.sharedClient) {
        self.client = client
        self.auth = client.map(SupabaseAuthSessionService.init)
        watchRelay.start(controller: self)
        reachability.onReconnect = { [weak self] in
            Task { @MainActor in await self?.refreshForForeground() }
        }
        PushRegistration.readyToUpload = { [weak self] in
            await self?.uploadPushToken()
        }
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

    /// The watch asked for Messages. Switch there, and bring this app forward when it is in the background.
    func showMessagesFromWatch() {
        pendingOpenMessages = true
        applyPendingMessagesOpen()
        guard UIApplication.shared.applicationState != .active else { return }
        let activity = NSUserActivity(activityType: PhoneOpen.messagesActivity)
        activity.title = "Messages"
        activity.userInfo = ["screen": "messages"]
        activity.requiredUserInfoKeys = ["screen"]
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil, errorHandler: nil)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard UIApplication.shared.applicationState != .active else {
                let center = UNUserNotificationCenter.current()
                center.removeDeliveredNotifications(withIdentifiers: [Self.messagesOpenID])
                center.removePendingNotificationRequests(withIdentifiers: [Self.messagesOpenID])
                return
            }
            await Self.postMessagesOpenNotice()
        }
    }

    private func applyPendingMessagesOpen() {
        guard pendingOpenMessages, let appState else { return }
        pendingOpenMessages = false
        if appState.role == .senior {
            appState.seniorTab = .messages
        } else {
            appState.familyTab = .messages
        }
    }

    private static let messagesOpenID = "watch.open.messages"

    private static func postMessagesOpenNotice() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = "Messages"
        content.body = "Open CareCompanion to read them."
        content.sound = .default
        content.userInfo = ["kind": PhoneOpen.messagesKind]
        let request = UNNotificationRequest(identifier: messagesOpenID, content: content, trigger: nil)
        try? await center.add(request)
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
        watchRelay.publish()
        CareWidgetPublisher.clear()
        await MedicationReminderCenter.shared.sync(from: nil)
    }

    /// Permanently deletes the login, the profile and any care account nobody else belongs to.
    func deleteAccount() async -> Bool {
        guard let client, let auth else { return false }
        guard await run({ try await SupabaseCareRepository.deleteMyAccount(client: client) }) else { return false }
        await clearAccount()
        try? await auth.signOut()
        authState = .signedOut
        watchRelay.publish()
        CareWidgetPublisher.clear()
        await MedicationReminderCenter.shared.sync(from: nil)
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
        // Send the current login to the watch before this phone refreshes care data, so the watch
        // never has to refresh the shared token itself.
        watchRelay.publish()
        guard let appState else { return }
        await appState.refresh()
        await appState.syncHealthData()
        await MedicationReminderCenter.shared.sync(from: appState)
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
        watchRelay.publish()
    }

    /// What the paired watch should do with this iPhone's account.
    func publishWatch() {
        watchRelay.publish()
    }

    func watchHandoff() async -> WatchAuthHandoff {
        guard let client, signedInUser != nil else {
            return WatchAuthHandoff(status: .signedOut)
        }
        guard hasLoadedAccount else {
            return WatchAuthHandoff(status: .unavailable)
        }
        guard let appState else {
            return WatchAuthHandoff(status: .needsLink)
        }
        guard appState.role == .senior, appState.linkedSenior != nil else {
            return appState.role == .senior
                ? WatchAuthHandoff(status: .needsLink)
                : WatchAuthHandoff(status: .notSenior)
        }
        do {
            let session = try await client.auth.session
            return WatchAuthHandoff(status: .ready, accessToken: session.accessToken, refreshToken: session.refreshToken)
        } catch {
            // A failed refresh is not a sign-out. Telling the watch it signed out cleared a session
            // that still worked and left the watch on "Couldn't load".
            return WatchAuthHandoff(status: .unavailable)
        }
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
        applyPendingMessagesOpen()
        do {
            try await loaded.startRealtime { [weak state] in
                await state?.refresh()
                await MedicationReminderCenter.shared.sync(from: state)
            }
            isRealtimeConnected = true
        } catch {
            isRealtimeConnected = false
        }
        await state.setupAutomaticHealthSync()
        if let pendingWatchHealth {
            await state.ingestWatchHealth(pendingWatchHealth)
        }
        startHealthClock()
        watchRelay.publish()
        await MedicationReminderCenter.shared.sync(from: state)
        await uploadPushToken()
    }

    func receiveWatchHealth(_ report: WatchHealthReport) async {
        pendingWatchHealth = report
        guard let appState, appState.linkedSenior != nil else { return }
        await appState.ingestWatchHealth(report)
    }

    private func startHealthClock() {
        healthClock?.cancel()
        healthClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.appState?.uploadScheduledHealth()
            }
        }
    }

    private func uploadPushToken() async {
        guard let client, appState != nil else { return }
        await PushRegistration.upload(using: client)
    }

    private func clearRepository() async {
        healthClock?.cancel()
        healthClock = nil
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
