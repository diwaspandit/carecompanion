import CareCore
import SwiftUI

/// Hidden developer screen (Demo menu → Live Supabase). Not part of the judged demo flow.
struct LiveModeView: View {
    @Environment(LiveModeController.self) private var live
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var accountName = "Sharma family"
    @State private var inviteCode = ""
    @State private var role: CareRole = .family
    @State private var seniorName = "Maya Sharma"
    @State private var seniorAge = 74
    @State private var seniorCity = "Kathmandu, Nepal"

    var body: some View {
        @Bindable var live = live
        Form {
            Section("Status") {
                LabeledContent("Supabase", value: live.isConfigured ? "Configured" : "Missing Secrets.xcconfig")
                LabeledContent("Session", value: live.signedInEmail ?? (live.isSignedIn ? "Signed in" : "Signed out"))
                if let repository = live.repository {
                    LabeledContent("Account", value: repository.snapshot.account.name)
                    LabeledContent("Invite code", value: repository.inviteCode)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("live.inviteCode")
                    LabeledContent("Members", value: "\(repository.snapshot.members.count)")
                    LabeledContent("Seniors", value: repository.snapshot.seniors.map(\.name).joined(separator: ", "))
                }
                LabeledContent("Data source", value: live.isLive ? (live.isRealtimeConnected ? "Live · realtime" : "Live") : "Demo")
            }

            if live.isConfigured && !live.isSignedIn {
                Section("Sign in") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("live.email")
                    SecureField("Password (test accounts)", text: $password)
                        .accessibilityIdentifier("live.password")
                    Button("Sign in with password") { Task { await live.signIn(email: email, password: password) } }
                        .disabled(password.isEmpty)
                        .accessibilityIdentifier("live.passwordSignIn")
                }
            }

            if live.isSignedIn && !live.hasAccount {
                Section("Care account") {
                    Picker("My role", selection: $role) {
                        Text("Family").tag(CareRole.family)
                        Text("Senior").tag(CareRole.senior)
                    }
                    TextField("Family name", text: $accountName)
                    Button("Create family account") { Task { await live.createAccount(name: accountName, role: role) } }
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Join with invite code") { Task { await live.joinAccount(code: inviteCode, role: role) } }
                        .disabled(inviteCode.isEmpty)
                }
            }

            if live.hasAccount && !live.hasSenior {
                Section("Monitored senior") {
                    TextField("Name", text: $seniorName)
                    Stepper("Age \(seniorAge)", value: $seniorAge, in: 50...110)
                    TextField("City", text: $seniorCity)
                    Button("Add senior (Asia/Kathmandu)") {
                        Task {
                            await live.addSenior(name: seniorName, age: seniorAge, city: seniorCity, timeZone: "Asia/Kathmandu")
                            await live.restore()
                        }
                    }
                }
            }

            if live.hasSenior, let repository = live.repository {
                Section {
                    if let linked = live.linkedSenior {
                        LabeledContent("This login is", value: linked.name)
                    } else {
                        ForEach(repository.snapshot.seniors.filter { $0.profileID == nil }) { senior in
                            Button("I am \(senior.name)") { Task { await live.claimSenior(id: senior.id) } }
                                .accessibilityIdentifier("live.claimSenior")
                        }
                    }
                } header: {
                    Text("Senior device")
                } footer: {
                    Text("Only a member who joined as Senior can link. Only the linked senior's phone can share Apple Health data.")
                }

                Section("Live data") {
                    if (live.repository?.snapshot.medications.isEmpty ?? true) {
                        Button("Add starter medications and visit") {
                            Task {
                                await live.addStarterCarePlan()
                                await live.restore()
                            }
                        }
                    }
                    if live.isLive {
                        Button("Return to demo data") { Task { await live.returnToDemo(); dismiss() } }
                    } else {
                        Button("Use live data in the app") { Task { await live.goLive(); dismiss() } }
                            .accessibilityIdentifier("live.goLive")
                    }
                }
            }

            if live.isSignedIn {
                Section {
                    Button("Sign out", role: .destructive) { Task { await live.signOut() } }
                }
            }
        }
        .navigationTitle("Live Supabase")
        .disabled(live.isBusy)
        .overlay { if live.isBusy { ProgressView() } }
        .alert("Live Supabase", isPresented: Binding(get: { live.message != nil }, set: { if !$0 { live.message = nil } })) {
            Button("OK") { live.message = nil }
        } message: {
            Text(live.message ?? "")
        }
        .task { await live.restore() }
    }
}
