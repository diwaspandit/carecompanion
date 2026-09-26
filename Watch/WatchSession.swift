import CareCore
import Foundation
import Observation
import Supabase
import SwiftUI
import WatchConnectivity

/// Light unless the iPhone appearance is set to Dark.
@MainActor
@Observable
final class WatchAppearance {
    static let shared = WatchAppearance()
    var preference = "light"

    var scheme: ColorScheme { preference == "dark" ? .dark : .light }

    var forced: ColorScheme? { preference == "dark" ? .dark : .light }

    nonisolated static func apply(_ raw: String?) {
        guard let raw else { return }
        let next = raw == "dark" ? "dark" : "light"
        Task { @MainActor in
            shared.preference = next
        }
    }
}

/// The watch uses the account from the paired iPhone. After that, check-ins and SOS go to
/// Supabase from the watch itself.
@MainActor @Observable final class WatchSession {
    enum Phase: Equatable {
        case notConfigured
        case launching
        case waitingForPhone
        case loading
        case needsPhoneSetup(String)
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .launching
    private(set) var appState: AppState?
    /// Bumped when a dose screen should close onto the home grid.
    private(set) var homeRequest = 0

    @ObservationIgnored private let client: SupabaseClient?
    @ObservationIgnored private let auth: SupabaseAuthSessionService?
    @ObservationIgnored private var repository: SupabaseCareRepository?
    @ObservationIgnored private let phone = WatchPhoneReceiver.shared
    @ObservationIgnored private var adoptedRefreshToken: String?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var signedOutStreak = 0
    @ObservationIgnored private let reachability = CareReachability()

    init(client: SupabaseClient? = SupabaseConfig.sharedClient) {
        self.client = client
        self.auth = client.map(SupabaseAuthSessionService.init)
        reachability.onReconnect = { [weak self] in
            Task { @MainActor in await self?.refreshIfReady() }
        }
        PushRegistration.readyToUpload = { [weak self] in
            await self?.uploadPushToken()
        }
        phone.onHandoff = { [weak self] handoff in
            await self?.apply(handoff)
        }
        phone.onMoodClear = { [weak self] in
            await self?.refreshIfReady()
        }
        phone.flushPending()
        phone.activate()
    }

    func refreshIfReady() async {
        guard phase == .ready, let state = appState else {
            phone.requestSession()
            if hasUsableSession { await loadCare() }
            return
        }
        let sessionStillValid = await state.refresh()
        if sessionStillValid {
            await MedicationReminderCenter.shared.sync(from: state)
        } else {
            // A rejected refresh is not a sign-out. Stay on the home grid and ask the phone again.
            phone.requestSession()
        }
    }

    func returnHome() {
        homeRequest += 1
    }

    func retry() async {
        await loadCare()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        guard auth != nil else {
            phase = .notConfigured
            return
        }
        phone.onHandoff = { [weak self] handoff in
            await self?.apply(handoff)
        }
        phone.onMoodClear = { [weak self] in
            await self?.refreshIfReady()
        }
        phone.flushPending()
        phone.activate()
        if hasUsableSession {
            await loadCare()
        } else {
            phase = .waitingForPhone
        }
        while !Task.isCancelled {
            if isWaiting {
                phone.requestSession()
            }
            try? await Task.sleep(for: .seconds(2))
        }
        if phase != .ready { didStart = false }
    }

    private var hasUsableSession: Bool {
        guard let token = client?.auth.currentSession?.accessToken else { return false }
        return WatchAuthHandoff.accessTokenIsUsable(token)
    }

    private var isWaiting: Bool {
        if case .failed = phase { return true }
        if case .needsPhoneSetup = phase { return true }
        return phase == .waitingForPhone
    }

    private func apply(_ handoff: WatchAuthHandoff) async {
        switch handoff.status {
        case .unavailable:
            return
        case .signedOut:
            // One stray "signed out" arrives when a dose save and the phone's login resend overlap.
            // Leave the home grid up unless the phone says so again.
            signedOutStreak += 1
            if showingHome, signedOutStreak < 2 {
                phone.requestSession()
                return
            }
            signedOutStreak = 0
            if phase == .ready { await signOut() }
            if phase != .loading { phase = .waitingForPhone }
        case .notSenior:
            phase = .needsPhoneSetup("Sign in as the senior on the iPhone this watch is paired with.")
        case .needsLink:
            phase = .needsPhoneSetup("On that iPhone, join the family and choose which senior you are.")
        case .ready:
            signedOutStreak = 0
            guard let accessToken = handoff.accessToken, let refreshToken = handoff.refreshToken else { return }
            // An expired access token would make setSession refresh it and sign the iPhone out too.
            guard WatchAuthHandoff.accessTokenIsUsable(accessToken) else {
                if phase != .ready { phase = .waitingForPhone }
                return
            }
            if adoptedRefreshToken == refreshToken, phase == .ready || phase == .loading { return }
            do {
                try await auth?.adoptSession(accessToken: accessToken, refreshToken: refreshToken)
                adoptedRefreshToken = refreshToken
                await loadCare()
            } catch {
                if phase != .ready { phase = .waitingForPhone }
            }
        }
    }

    private func uploadPushToken() async {
        guard let client, phase == .ready else { return }
        await PushRegistration.upload(using: client)
    }

    private func signOut() async {
        await repository?.stopRealtime()
        repository = nil
        appState = nil
        adoptedRefreshToken = nil
        try? await auth?.signOut()
        await MedicationReminderCenter.shared.sync(from: nil)
    }

    private var showingHome: Bool {
        phase == .ready && appState != nil
    }

    private func loadCare() async {
        guard let client else { return }
        loadGeneration += 1
        let generation = loadGeneration
        let keepHome = showingHome
        if !keepHome { phase = .loading }
        do {
            let loaded = try await SupabaseCareRepository.load(client: client)
            guard generation == loadGeneration else { return }
            await repository?.stopRealtime()
            let state = AppState(repository: loaded, healthProvider: nil)
            repository = loaded
            appState = state
            try? await loaded.startRealtime { [weak state] in
                guard await state?.refresh() == true else { return }
                await MedicationReminderCenter.shared.sync(from: state)
            }
            guard generation == loadGeneration else { return }
            if state.role != .senior {
                phase = .needsPhoneSetup("Sign in as the senior on the iPhone this watch is paired with.")
            } else if state.needsSeniorLink {
                phase = .needsPhoneSetup("On that iPhone, join the family and choose which senior you are.")
            } else {
                phase = .ready
            }
            await MedicationReminderCenter.shared.sync(from: phase == .ready ? state : nil)
            if phase == .ready { await uploadPushToken() }
        } catch {
            guard generation == loadGeneration else { return }
            if Task.isCancelled || error is CancellationError {
                if keepHome { phase = .ready }
                else if phase == .loading { phase = .waitingForPhone }
                return
            }
            let message = error.localizedDescription
            if keepHome {
                phase = .ready
                phone.requestSession()
                return
            }
            if error as? CareServiceError == .unauthorized || message.contains("not authorized") {
                phase = .waitingForPhone
                phone.requestSession()
            } else if message.contains("No care account") || message.contains("Invalid state") {
                phase = .needsPhoneSetup("Finish setup on the paired iPhone, then this watch will sign in on its own.")
            } else {
                phase = .failed(message)
            }
        }
    }
}

/// Starts the phone link before any screen appears, so a message can wake the watch while the app is closed.
func activateWatchPhoneLink() {
    WatchPhoneReceiver.shared.activate()
}

/// Receives the iPhone session. `sendMessage` is what the Simulator can deliver; application context covers the case where the phone published before the watch opened.
private final class WatchPhoneReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchPhoneReceiver()

    var onHandoff: (@MainActor (WatchAuthHandoff) async -> Void)?
    var onMoodClear: (@MainActor () async -> Void)?
    private var pending: WatchAuthHandoff?

    /// Delivers a login that arrived before the watch screen was ready to store it.
    func flushPending() {
        guard let pending else { return }
        deliver(pending)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func requestSession() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["request": "session"], replyHandler: { [weak self] reply in
            WatchAppearance.apply(reply["appearance"] as? String)
            guard let handoff = WatchAuthHandoff(dictionary: reply) else { return }
            self?.deliver(handoff)
        }, errorHandler: { _ in })
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        if let handoff = WatchAuthHandoff(dictionary: session.receivedApplicationContext) {
            deliver(handoff)
        }
        requestSession()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { requestSession() }
        if let handoff = WatchAuthHandoff(dictionary: session.receivedApplicationContext) {
            deliver(handoff)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchAppearance.apply(applicationContext["appearance"] as? String)
        guard let handoff = WatchAuthHandoff(dictionary: applicationContext) else { return }
        deliver(handoff)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo["kind"] as? String == "moodClear" {
            let clear = onMoodClear
            Task { @MainActor in
                await MedicationReminderCenter.shared.dismissMoodPromptLocally()
                await clear?()
            }
            return
        }
        if userInfo["kind"] as? String == "message" {
            let messageID = userInfo["messageID"] as? String ?? ""
            let name = userInfo["senderName"] as? String ?? "Family"
            let body = userInfo["body"] as? String ?? "New message"
            let image = userInfo["image"] as? Data
            Task { @MainActor in
                await MedicationReminderCenter.showWatchMessage(name: name, body: body, messageID: messageID, image: image)
            }
            return
        }
        let zone = userInfo["timeZone"] as? String ?? ""
        let rows = Self.stringRows(userInfo["medications"])
        let visits = Self.stringRows(userInfo["visits"])
        Task { @MainActor in
            await MedicationReminderCenter.shared.applyForwarded(rows, visits: visits, timeZoneIdentifier: zone)
        }
    }

    private static func stringRows(_ value: Any?) -> [[String: String]] {
        (value as? [Any] ?? []).compactMap { item -> [String: String]? in
            guard let dict = item as? [String: Any] else { return nil }
            var row: [String: String] = [:]
            for (key, value) in dict {
                if let text = value as? String { row[key] = text }
            }
            return row.isEmpty ? nil : row
        }
    }

    private func deliver(_ handoff: WatchAuthHandoff) {
        pending = handoff
        let callback = onHandoff
        Task { @MainActor in
            await callback?(handoff)
        }
    }
}

/// Asks the paired iPhone to open CareCompanion on Messages. The reply stays off the main actor.
enum WatchPhoneOpener {
    @MainActor
    static func openMessages() {
        let activity = NSUserActivity(activityType: PhoneOpen.messagesActivity)
        activity.title = "Messages"
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        deliver()
    }

    nonisolated private static func deliver() {
        let info: [String: Any] = ["kind": PhoneOpen.messagesKind, "screen": "messages"]
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(info, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(info)
            })
        } else {
            WCSession.default.transferUserInfo(info)
        }
    }
}
