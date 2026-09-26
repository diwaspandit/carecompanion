import CareCore
import SwiftUI
import UIKit

@main
struct CareCompanionApp: App {
    @UIApplicationDelegateAdaptor(PhonePushDelegate.self) private var pushDelegate
    @State private var session = SessionController()

    init() {
        MedicationReminderCenter.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .onOpenURL { url in
                    if url.host == "messages" {
                        session.showMessagesFromWatch()
                        return
                    }
                    if CareWidgetLink.isWidgetOpen(url) {
                        if let state = session.appState {
                            CareWidgetLink.open(state)
                        } else {
                            CareWidgetLink.remember()
                        }
                    } else {
                        Task { await session.handleOpenURL(url) }
                    }
                }
        }
    }
}

private struct RootView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CareAppearance.storageKey) private var appearance = CareAppearance.system.rawValue

    var body: some View {
        Group {
            switch session.phase {
            case .notConfigured:
                NotConfiguredView()
            case .launching:
                LoadingView(message: nil)
            case .loadingAccount:
                LoadingView(message: "Loading your family…")
            case .welcome:
                WelcomeView()
            case .checkEmail(let email):
                CheckEmailView(email: email, kind: .confirmation)
            case .passwordResetSent(let email):
                CheckEmailView(email: email, kind: .passwordReset)
            case .chooseNewPassword:
                ChooseNewPasswordView()
            case .loadFailed(let message):
                LoadFailedView(message: message)
            case .profileSetup:
                ProfileSetupView()
            case .accountSetup:
                AccountSetupView()
            case .ready:
                if let state = session.appState {
                    SignedInView(state: state)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .preferredColorScheme(CareAppearance(rawValue: appearance)?.colorScheme)
        .onAppear { CareWidgetPublisher.syncAppearance(appearance) }
        .onChange(of: appearance) { _, value in
            CareWidgetPublisher.syncAppearance(value)
            session.publishWatch()
        }
        .task { await session.restore() }
        .onContinueUserActivity(PhoneOpen.messagesActivity) { _ in
            session.showMessagesFromWatch()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // A notification action can deliver this change off the main thread. The refresh has to
            // start on the main queue or SwiftUI crashes while snapshotting the app.
            DispatchQueue.main.async {
                Task { await session.refreshForForeground() }
            }
        }
        .overlay { MedicationAlertScreen() }
    }
}

final class PhonePushDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.store(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}
}

/// Chooses the experience for a signed-in member of a care account.
private struct SignedInView: View {
    let state: AppState
    @State private var sosNotice = FamilySOSNotice.shared

    var body: some View {
        Group {
            if state.needsSeniorLink {
                SeniorLinkView()
            } else if state.role == .family && state.snapshot.seniors.isEmpty {
                AddFirstSeniorView()
            } else if state.role == .senior {
                SeniorRootView()
            } else {
                FamilyRootView()
            }
        }
        .environment(state)
        .onAppear {
            CareWidgetPublisher.publish(state)
            CareWidgetLink.apply(to: state)
        }
        .onChange(of: state.snapshot) { _, _ in
            CareWidgetPublisher.publish(state)
            if state.role == .senior {
                Task { await SeniorMessageNotice.sync(state) }
            }
        }
        .onChange(of: state.selectedSeniorID) { _, _ in CareWidgetPublisher.publish(state) }
        .overlay {
            if state.role == .family, let seniorID = sosNotice.seniorID {
                FamilySOSCallView(seniorID: seniorID)
            }
        }
        .overlay(alignment: .bottom) { ToastOverlay().environment(state) }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toastMessage)
        .tint(CareTheme.sageDark)
    }
}
