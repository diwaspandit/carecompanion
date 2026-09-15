import CareCore
import SwiftUI

struct WelcomeView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    @Environment(SessionController.self) private var session
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showForgotPassword = false
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 30

    private enum Field { case email, password, confirm }

    private var localProblem: String? {
        guard mode == .signUp, !password.isEmpty else { return nil }
        if let problem = PasswordPolicy.problem(with: password) { return problem }
        if !confirmPassword.isEmpty && confirmPassword != password { return "Passwords don't match." }
        return nil
    }

    private var canSubmit: Bool {
        EmailAddress.isValid(email) && !password.isEmpty
            && (mode == .signIn || (PasswordPolicy.problem(with: password) == nil && password == confirmPassword))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingConnectionView()
                    .padding(.horizontal, -8)
                    .padding(.top, 24)
                Text("Care that travels\nacross time zones.")
                    .font(.system(size: titleSize, weight: .bold, design: .rounded))
                    .lineSpacing(3)
                    .foregroundStyle(CareTheme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("welcome.title")
                Text("Daily check-ins, medicines, visits and Apple Health, shared between a senior and the family looking after them.")
                    .font(.subheadline)
                    .lineSpacing(3)
                    .foregroundStyle(CareTheme.mutedText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 12)
                .accessibilityIdentifier("auth.mode")

                VStack(spacing: 14) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                        .careField()
                        .accessibilityIdentifier("auth.email")
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focused, equals: .password)
                        .submitLabel(mode == .signIn ? .go : .next)
                        .onSubmit { mode == .signIn ? submit() : (focused = .confirm) }
                        .careField()
                        .accessibilityIdentifier("auth.password")
                    if mode == .signUp {
                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focused, equals: .confirm)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .careField()
                            .accessibilityIdentifier("auth.confirmPassword")
                    }
                }

                FormErrorText(message: session.errorMessage ?? localProblem)

                PrimaryActionButton(title: mode.rawValue, isLoading: session.isBusy, isDisabled: !canSubmit, action: submit)
                    .accessibilityIdentifier("auth.submit")

                if mode == .signIn {
                    Button("Forgot password?") { showForgotPassword = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CareTheme.sageDark)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("We'll email you a link to confirm your address.")
                        .font(.system(size: 13))
                        .foregroundStyle(CareTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background.ignoresSafeArea())
        .onChange(of: mode) { session.errorMessage = nil }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(initialEmail: email)
                .presentationDetents([.medium])
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        Task {
            if mode == .signIn {
                await session.signIn(email: email, password: password)
            } else {
                await session.signUp(email: email, password: password)
            }
        }
    }
}

private struct ForgotPasswordView: View {
    @Environment(SessionController.self) private var session
    @Environment(\.dismiss) private var dismiss
    let initialEmail: String
    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reset password")
                .font(.system(size: 26, weight: .black))
            Text("Enter your account email. We'll send a link that opens CareCompanion so you can choose a new password.")
                .font(.system(size: 16))
                .foregroundStyle(CareTheme.secondaryText)
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .careField()
            FormErrorText(message: session.errorMessage)
            PrimaryActionButton(title: "Send reset link", isLoading: session.isBusy, isDisabled: !EmailAddress.isValid(email)) {
                Task {
                    await session.sendPasswordReset(email: email)
                    if session.errorMessage == nil { dismiss() }
                }
            }
            Spacer()
        }
        .padding(24)
        .background(CareTheme.background)
        .onAppear { email = initialEmail }
    }
}

struct CheckEmailView: View {
    enum Kind { case confirmation, passwordReset }

    @Environment(SessionController.self) private var session
    let email: String
    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            CircleIcon(systemName: "envelope.badge", color: CareTheme.sageDark, size: 72, iconSize: 32, fillOpacity: 0.2)
            Text("Check your email")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
            Text(kind == .confirmation
                 ? "We sent a confirmation link to \(email). Open it on this iPhone to finish creating your account."
                 : "We sent a password reset link to \(email). Open it on this iPhone to choose a new password.")
                .font(.system(size: 18))
                .lineSpacing(5)
                .foregroundStyle(CareTheme.mutedText)
            FormErrorText(message: session.errorMessage)
            Spacer()
            PrimaryActionButton(title: "Back to sign in") { session.returnToSignIn() }
        }
        .padding(24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}

struct ChooseNewPasswordView: View {
    @Environment(SessionController.self) private var session
    @State private var password = ""
    @State private var confirm = ""

    private var problem: String? {
        guard !password.isEmpty else { return nil }
        if let problem = PasswordPolicy.problem(with: password) { return problem }
        if !confirm.isEmpty && confirm != password { return "Passwords don't match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Choose a new password")
                .font(.system(size: 30, weight: .black, design: .rounded))
            SecureField("New password", text: $password)
                .textContentType(.newPassword)
                .careField()
            SecureField("Confirm new password", text: $confirm)
                .textContentType(.newPassword)
                .careField()
            FormErrorText(message: session.errorMessage ?? problem)
            PrimaryActionButton(title: "Save password", isLoading: session.isBusy,
                                isDisabled: PasswordPolicy.problem(with: password) != nil || password != confirm) {
                Task { await session.updatePassword(password) }
            }
            Spacer()
        }
        .padding(24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}

struct LoadingView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            if let message {
                Text(message).font(.system(size: 16)).foregroundStyle(CareTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareTheme.background.ignoresSafeArea())
    }
}

struct LoadFailedView: View {
    @Environment(SessionController.self) private var session
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            CircleIcon(systemName: "wifi.exclamationmark", color: CareTheme.coral, size: 72, iconSize: 30, fillOpacity: 0.18)
            Text("Couldn't load your family")
                .font(.system(size: 30, weight: .black, design: .rounded))
            Text(message)
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.mutedText)
            Spacer()
            PrimaryActionButton(title: "Try again", isLoading: session.isBusy) {
                Task { await session.retryLoading() }
            }
            Button("Sign out") { Task { await session.signOut() } }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CareTheme.secondaryText)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}

struct NotConfiguredView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("Backend not configured")
                .font(.system(size: 28, weight: .black))
            Text("This build has no Supabase project. Copy Config/Secrets.xcconfig.example to Config/Secrets.xcconfig, add the project host and publishable key, and rebuild.")
                .font(.system(size: 16))
                .foregroundStyle(CareTheme.mutedText)
            Spacer()
        }
        .padding(24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}
