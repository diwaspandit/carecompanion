import AppIntents
import CareCore
import UserNotifications

/// Sends the same family SOS as the in-app button. Shortcuts, Siri, and the Action Button can run it
/// while CareCompanion stays closed.
struct SendCareSOSIntent: AppIntent {
    static let title: LocalizedStringResource = "Send SOS"
    static let description = IntentDescription("Alerts your family that you need help, without opening CareCompanion.")
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CareSOSSender.send()
        return .result(dialog: IntentDialog(stringLiteral: outcome))
    }
}

struct CareAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendCareSOSIntent(),
            phrases: [
                "Send SOS in \(.applicationName)",
                "Send an SOS with \(.applicationName)",
                "Alert my family in \(.applicationName)"
            ],
            shortTitle: "Send SOS",
            systemImageName: "exclamationmark.triangle.fill"
        )
    }
}

private enum CareSOSSender {
    @MainActor
    static func send() async -> String {
        guard let client = SupabaseConfig.sharedClient else {
            return "CareCompanion is not ready on this device."
        }
        let auth = SupabaseAuthSessionService(client: client)
        guard case .signedIn = await auth.restoreSession() else {
            return "Open CareCompanion and sign in, then try SOS again."
        }
        do {
            let repository = try await SupabaseCareRepository.load(client: client)
            let state = AppState(repository: repository, healthProvider: nil)
            guard state.role == .senior, state.linkedSenior != nil else {
                return "SOS works on the senior's iPhone and Apple Watch."
            }
            guard await state.triggerSOS() else {
                return "Couldn't send SOS. Open CareCompanion and use the SOS button."
            }
            await confirm()
            return "Your family has your SOS."
        } catch {
            return "Couldn't send SOS. Open CareCompanion and use the SOS button."
        }
    }

    private static func confirm() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "SOS sent"
        content.body = "Your family has your SOS."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "sos.sent.\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }
}
