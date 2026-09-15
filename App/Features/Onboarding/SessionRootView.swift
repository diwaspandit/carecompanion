import CareCore
import SwiftUI

/// Top of the view tree: onboarding screens by phase, or the care app for the active AppState.
struct SessionRootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .ready, .demo:
                RootView()
                    .id(ObjectIdentifier(session.activeState))
                    .environment(session.activeState)
            case .restoring:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CareTheme.background.ignoresSafeArea())
            case .welcome:
                WelcomeView()
            default:
                NavigationStack { step }
                    .tint(CareTheme.sageDark)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }

    @ViewBuilder private var step: some View {
        switch session.phase {
        case .enterEmail: EmailEntryView()
        case .enterCode(let email): CodeEntryView(email: email)
        case .needsProfile: ProfileSetupView()
        case .needsFamily: FamilySetupView()
        case .needsSenior: AddSeniorView()
        case .inviteFamily(let code): InviteFamilyView(code: code)
        case .needsSeniorLink(let seniors): SeniorLinkView(seniors: seniors)
        case .unreachable: UnreachableView()
        case .restoring, .welcome, .ready, .demo: EmptyView()
        }
    }
}
