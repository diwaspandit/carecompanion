import CareCore
import SwiftUI

struct WelcomeView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleIcon(systemName: "heart.text.square", color: CareTheme.sageDark, size: 56, iconSize: 25, fillOpacity: 0.20)
                .padding(.top, 70)
                .padding(.bottom, 32)
            Text("Care that travels\nacross time zones.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.title")
            Text("Sign in to share check-ins, medicines and visits with your family.")
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 16)
            Spacer()
            if session.isSignInAvailable {
                OnboardingPrimaryButton(title: "Get started", identifier: "welcome.getStarted") { session.startSignIn() }
            } else {
                Text("Sign-in isn't set up in this build.")
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.mutedText)
                    .frame(maxWidth: .infinity)
            }
            OnboardingLinkButton(title: "Try the demo", identifier: "welcome.tryDemo") { session.tryDemo() }
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}
