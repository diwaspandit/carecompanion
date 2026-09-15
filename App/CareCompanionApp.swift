import CareCore
import SwiftUI

@main
struct CareCompanionApp: App {
    @State private var session = SessionController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.light)
                .onOpenURL { url in Task { await session.handleOpenURL(url) } }
        }
    }
}

private struct RootView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.scenePhase) private var scenePhase

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
        .task { await session.restore() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await session.refreshForForeground() }
            }
        }
    }
}

/// Chooses the experience for a signed-in member of a care account.
private struct SignedInView: View {
    let state: AppState

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
        .overlay(alignment: .bottom) { ToastOverlay().environment(state) }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toastMessage)
        .tint(CareTheme.sageDark)
    }
}
