import CareCore
import SwiftUI

struct InviteFamilyView: View {
    @Environment(AppSession.self) private var session
    let code: String

    var body: some View {
        OnboardingScaffold(title: "Invite your family",
                           subtitle: "Share this code with the senior and anyone else helping. They enter it after signing in.") {
            LovableCard {
                VStack(spacing: 8) {
                    Text("Invite code").font(.system(size: 15, weight: .bold)).foregroundStyle(CareTheme.mutedText)
                    Text(code)
                        .font(.system(size: 40, weight: .black, design: .monospaced))
                        .kerning(4)
                        .foregroundStyle(CareTheme.ink)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("invite.code")
                }
                .frame(maxWidth: .infinity)
            }
            ShareLink(item: "Join our family on CareCompanion. Sign in and enter invite code \(code).") {
                Label("Share code", systemImage: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(CareTheme.sageDark)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(CareTheme.cardStroke))
            }
            .accessibilityIdentifier("invite.share")
            OnboardingPrimaryButton(title: "Continue", identifier: "invite.continue") { await session.finishInvite() }
        }
    }
}
