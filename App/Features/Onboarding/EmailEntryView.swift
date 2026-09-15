import CareCore
import SwiftUI

struct EmailEntryView: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    #if DEBUG
    @State private var usePassword = false
    @State private var password = ""
    #endif

    var body: some View {
        OnboardingScaffold(title: "What's your email?",
                           subtitle: "We'll email you a 6-digit code. No password needed.",
                           showsSignOut: false) {
            OnboardingField(label: "Email", text: $email, identifier: "email.field")
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            OnboardingPrimaryButton(title: "Send code", enabled: !email.isEmpty, identifier: "email.send") {
                await session.sendCode(to: email)
            }
            #if DEBUG
            if usePassword {
                OnboardingField(label: "Password (test accounts)", text: $password, isSecure: true, identifier: "email.password")
                OnboardingPrimaryButton(title: "Sign in with password", enabled: !email.isEmpty && !password.isEmpty,
                                        identifier: "email.passwordSignIn") {
                    await session.signInWithPassword(email: email, password: password)
                }
            } else {
                OnboardingLinkButton(title: "Use password (debug)", identifier: "email.usePassword") { usePassword = true }
            }
            #endif
            // Not signed in yet, so signing out simply returns to Welcome.
            OnboardingLinkButton(title: "Back", identifier: "email.back") { Task { await session.signOut() } }
        }
    }
}
