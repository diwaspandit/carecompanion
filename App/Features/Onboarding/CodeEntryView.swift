import CareCore
import SwiftUI

struct CodeEntryView: View {
    @Environment(AppSession.self) private var session
    let email: String
    @State private var code = ""

    var body: some View {
        OnboardingScaffold(title: "Enter your code", subtitle: "We sent a 6-digit code to \(email).", showsSignOut: false) {
            OnboardingField(label: "6-digit code", text: $code, identifier: "code.field")
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    guard digits == newValue else {
                        code = digits
                        return
                    }
                    if digits.count == 6 { Task { await session.verifyCode(digits) } }
                }
            OnboardingPrimaryButton(title: "Continue", enabled: code.count == 6, identifier: "code.verify") {
                await session.verifyCode(code)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = session.secondsUntilResend()
                OnboardingLinkButton(title: seconds > 0 ? "Resend code in \(seconds)s" : "Resend code",
                                     identifier: "code.resend") {
                    Task { await session.resendCode() }
                }
                .disabled(seconds > 0)
            }
            OnboardingLinkButton(title: "Use a different email", identifier: "code.changeEmail") { session.useDifferentEmail() }
        }
        .onChange(of: session.errorMessage) { _, message in
            if message != nil { code = "" }
        }
    }
}
