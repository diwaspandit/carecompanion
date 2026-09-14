import SwiftUI
import CareCore

/// Production onboarding: sign in, create or join account, then continue to app.
/// Demo mode bypasses this entirely (existing flow).
struct ProductionOnboardingView: View {
    @Environment(LiveModeController.self) private var live
    @State private var showingCreateAccount = false
    @State private var showingJoinAccount = false
    @State private var showingSignIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()

            Text("Welcome to\nCareCompanion")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)

            Text("Care that travels across time zones")
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.bottom, 40)

            if !live.isSignedIn {
                Button {
                    showingSignIn = true
                } label: {
                    Label("Sign In", systemImage: "person")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            } else if !live.hasAccount {
                VStack(spacing: 16) {
                    Text("Signed in as \(live.signedInEmail ?? "")")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.secondaryText)

                    Button {
                        showingCreateAccount = true
                    } label: {
                        Label("Create Family Account", systemImage: "person.2")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showingJoinAccount = true
                    } label: {
                        Label("Join Existing Account", systemImage: "person.badge.key")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(CareTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(CareTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(CareTheme.background)
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .sheet(isPresented: $showingCreateAccount) {
            CreateAccountView()
        }
        .sheet(isPresented: $showingJoinAccount) {
            JoinAccountView()
        }
    }
}

private struct SignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveModeController.self) private var live
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }

                Section {
                    Button("Sign In") {
                        Task {
                            await live.signIn(email: email, password: password)
                            if live.isSignedIn {
                                dismiss()
                            }
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || live.isBusy)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveModeController.self) private var live
    @State private var familyName = ""
    @State private var role: CareRole = .family

    var body: some View {
        NavigationStack {
            Form {
                Section("Family Details") {
                    TextField("Family Name", text: $familyName)
                    Picker("Your Role", selection: $role) {
                        Text("Family Member").tag(CareRole.family)
                        Text("Senior").tag(CareRole.senior)
                    }
                }

                Section {
                    Button("Create Account") {
                        Task {
                            await live.createAccount(name: familyName, role: role)
                            if live.hasAccount {
                                dismiss()
                            }
                        }
                    }
                    .disabled(familyName.isEmpty || live.isBusy)
                }

                if let message = live.message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct JoinAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LiveModeController.self) private var live
    @State private var inviteCode = ""
    @State private var role: CareRole = .family

    var body: some View {
        NavigationStack {
            Form {
                Section("Join Family") {
                    TextField("Invite Code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                    Picker("Your Role", selection: $role) {
                        Text("Family Member").tag(CareRole.family)
                        Text("Senior").tag(CareRole.senior)
                    }
                }

                Section {
                    Button("Join Account") {
                        Task {
                            await live.joinAccount(code: inviteCode, role: role)
                            if live.hasAccount {
                                dismiss()
                            }
                        }
                    }
                    .disabled(inviteCode.isEmpty || live.isBusy)
                }

                if let message = live.message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Join Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
