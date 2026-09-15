import Foundation
import Observation

/// Owns launch and onboarding: restores the session, walks a new user through setup, and holds
/// the AppState on screen (the demo one, or the live one once the account is ready).
@MainActor @Observable public final class AppSession {
    public static let resendDelay: TimeInterval = 60
    static let invalidEmailMessage = "Enter a valid email address"
    static let fallbackMessage = "Something went wrong. Please try again."

    public private(set) var phase: SessionPhase = .restoring
    public private(set) var activeState: AppState
    public private(set) var isBusy = false
    public var errorMessage: String?

    private var membership: CareMembership?
    private var liveState: AppState?
    private var signedInProfileID: String?
    private var lastCodeSentAt: Date?
    private var justCreatedFamily = false
    private var phaseBeforeDemo: SessionPhase?

    @ObservationIgnored private let auth: (any AuthSessionService)?
    @ObservationIgnored private let accounts: (any CareAccountService)?
    @ObservationIgnored private let demoState: AppState
    @ObservationIgnored private let makeHealthProvider: () -> (any HealthDataProvider)?
    @ObservationIgnored private let isUITesting: Bool
    @ObservationIgnored private let now: () -> Date

    public init(
        auth: (any AuthSessionService)?,
        accounts: (any CareAccountService)?,
        demoState: AppState,
        makeHealthProvider: @escaping () -> (any HealthDataProvider)? = { nil },
        isUITesting: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.accounts = accounts
        self.demoState = demoState
        self.makeHealthProvider = makeHealthProvider
        self.isUITesting = isUITesting
        self.now = now
        activeState = demoState
    }

    /// False on a build without Supabase secrets: only the demo is offered.
    public var isSignInAvailable: Bool { auth != nil && accounts != nil }
    public var isSignedIn: Bool { signedInProfileID != nil }
    /// The family account whose data is on screen; nil in the demo and during onboarding.
    public var liveAccountID: String? { phase == .ready ? membership?.accountID : nil }

    public func secondsUntilResend() -> Int {
        guard let lastCodeSentAt else { return 0 }
        return max(0, Int((Self.resendDelay - now().timeIntervalSince(lastCodeSentAt)).rounded(.up)))
    }

    // MARK: - Launch

    public func start() async {
        if isUITesting {
            activeState = demoState
            phase = .demo
            return
        }
        guard let auth, isSignInAvailable else {
            phase = .welcome
            return
        }
        phase = .restoring
        if case .signedIn(let user) = await auth.restoreSession() {
            signedInProfileID = user.id
            await route()
        } else {
            phase = .welcome
        }
    }

    public func retry() async {
        await route()
    }

    // MARK: - Demo

    public func tryDemo() {
        if phase != .demo { phaseBeforeDemo = phase }
        errorMessage = nil
        activeState = demoState
        phase = .demo
    }

    /// Back to where the user was (their account if signed in), with the demo reset for next time.
    public func exitDemo() async {
        await demoState.resetDemo()
        let previous = phaseBeforeDemo ?? .welcome
        phaseBeforeDemo = nil
        if previous == .ready, let liveState {
            activeState = liveState
            phase = .ready
        } else {
            activeState = demoState
            phase = [.demo, .restoring, .ready].contains(previous) ? .welcome : previous
        }
    }

    // MARK: - Sign-in

    public func startSignIn() {
        errorMessage = nil
        phase = .enterEmail
    }

    public func useDifferentEmail() {
        startSignIn()
    }

    public func sendCode(to rawEmail: String) async {
        guard let auth else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isValid(email) else {
            errorMessage = Self.invalidEmailMessage
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await auth.sendEmailCode(to: email)
            lastCodeSentAt = now()
            phase = .enterCode(email: email)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func resendCode() async {
        guard case .enterCode(let email) = phase, secondsUntilResend() == 0 else { return }
        await sendCode(to: email)
    }

    public func verifyCode(_ code: String) async {
        guard let auth, case .enterCode(let email) = phase else { return }
        await signIn { try await auth.verifyEmailCode(code, email: email) }
    }

    /// Test accounts only; offered in DEBUG builds.
    public func signInWithPassword(email: String, password: String) async {
        guard let auth else { return }
        await signIn { try await auth.signIn(email: email, password: password) }
    }

    private func signIn(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
            return
        }
        isBusy = false
        guard case .signedIn(let user) = auth?.state else {
            errorMessage = Self.fallbackMessage
            return
        }
        signedInProfileID = user.id
        await route()
    }

    public func signOut() async {
        await accounts?.stopLiveUpdates()
        try? await auth?.signOut()
        membership = nil
        liveState = nil
        signedInProfileID = nil
        lastCodeSentAt = nil
        justCreatedFamily = false
        phaseBeforeDemo = nil
        errorMessage = nil
        isBusy = false
        activeState = demoState
        phase = .welcome
    }

    // MARK: - Routing

    /// Reloads profile and membership from the server and moves to the next unfinished step.
    func route() async {
        guard let accounts, let signedInProfileID else {
            phase = .welcome
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let profile = try await accounts.loadProfile()
            let membership = try await accounts.loadMembership()
            self.membership = membership
            let next = OnboardingRouter.nextPhase(profile: profile, membership: membership,
                                                  signedInProfileID: signedInProfileID,
                                                  justCreatedFamily: justCreatedFamily)
            isBusy = false
            if next == .ready, let membership {
                await enterReady(membership)
            } else {
                phase = next
            }
        } catch CareServiceError.unauthorized {
            await signOut()
        } catch {
            isBusy = false
            if phase == .restoring || phase == .unreachable {
                phase = .unreachable
            } else {
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Runs one onboarding write, then routes onward. On failure the phase stays put with a message.
    func runStep(_ work: @MainActor (any CareAccountService) async throws -> Void,
                 onError: (Error) -> String = { AppSession.message(for: $0) }) async {
        guard let accounts else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await work(accounts)
        } catch {
            isBusy = false
            errorMessage = onError(error)
            return
        }
        isBusy = false
        await route()
    }

    func markFamilyCreated() { justCreatedFamily = true }
    func clearFamilyCreated() { justCreatedFamily = false }

    private func enterReady(_ membership: CareMembership) async {
        let state = AppState(repository: membership.repository, healthProvider: makeHealthProvider(),
                             currentProfileID: signedInProfileID, isProduction: true, now: Date.init)
        if membership.role == .senior,
           let linked = state.snapshot.seniors.first(where: { $0.profileID == signedInProfileID }) {
            state.selectSenior(id: linked.id)
        }
        state.enterAsMember(role: membership.role)
        liveState = state
        activeState = state
        phase = .ready
        do {
            try await accounts?.startLiveUpdates { [weak state] in await state?.refresh() }
        } catch {
            state.showDemoToast("Live updates are paused. Changes appear when you reopen the app.")
        }
    }

    static func message(for error: Error) -> String {
        switch error as? CareServiceError {
        case .invalidCode: "That code didn't work. Check the email or send a new one."
        case .inviteNotFound: "No family found for that code."
        case .offline: "Can't reach CareCompanion. Check your connection and try again."
        case .invalidState(let message) where message == invalidEmailMessage: invalidEmailMessage
        default: fallbackMessage
        }
    }
}

// MARK: - Onboarding steps

extension AppSession {
    public func saveProfile(displayName: String, city: String) async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter your name"
            return
        }
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        await runStep { try await $0.updateProfile(MemberProfile(displayName: name, city: city)) }
    }

    public func createFamily(name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a family name"
            return
        }
        await runStep { accounts in
            try await accounts.createFamily(name: name)
            self.markFamilyCreated()
        }
    }

    public func joinFamily(inviteCode: String, role: CareRole) async {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            errorMessage = "Enter the invite code"
            return
        }
        await runStep { try await $0.joinFamily(inviteCode: code, role: role) }
    }

    public func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter their name"
            return
        }
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        await runStep { try await $0.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZoneIdentifier) }
    }

    public func finishInvite() async {
        clearFamilyCreated()
        await route()
    }

    public func claimSenior(id: String) async {
        var name = "This senior"
        if case .needsSeniorLink(let seniors) = phase, let senior = seniors.first(where: { $0.id == id }) {
            name = senior.name
        }
        await runStep({ try await $0.claimSenior(id: id) }, onError: { error in
            switch error as? CareServiceError {
            case .seniorAlreadyLinked: "\(name) is already linked to another phone. Ask your family for help."
            case .unauthorized: "Only someone who joined as the senior can do this."
            default: AppSession.message(for: error)
            }
        })
    }
}
