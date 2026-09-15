import CareCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(SessionController.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var city = ""
    @State private var phone = ""
    @State private var isSavingProfile = false
    @State private var showHealth = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var isDeleting = false

    private var profileChanged: Bool {
        guard let me = state.currentMember else { return false }
        return name != me.name || city != me.city || phone != me.phone
    }

    private var inviteText: String {
        "Join \(state.snapshot.account.name) on CareCompanion with invite code \(state.snapshot.account.inviteCode)."
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    TextField("Phone number", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    Button(isSavingProfile ? "Saving…" : "Save profile") {
                        Task {
                            isSavingProfile = true
                            await state.updateProfile(displayName: name, city: city, phone: phone)
                            isSavingProfile = false
                        }
                    }
                    .disabled(!profileChanged || name.trimmingCharacters(in: .whitespaces).isEmpty || isSavingProfile)
                } header: {
                    Text("Your profile")
                } footer: {
                    Text("Family members can call you with this number.")
                }

                Section("Family") {
                    LabeledContent("Name", value: state.snapshot.account.name)
                    LabeledContent("You are", value: state.role == .senior ? "The senior" : "A family member")
                    LabeledContent("Invite code") {
                        Text(state.snapshot.account.inviteCode)
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .textSelection(.enabled)
                    }
                    ShareLink("Share invite code", item: inviteText)
                }

                if state.role == .senior {
                    Section("Apple Health") {
                        Button("Health data sharing") { showHealth = true }
                    }
                }

                Section("Privacy") {
                    NavigationLink("How your data is used") { PrivacyInfoView() }
                }

                Section {
                    Button("Sign out") { confirmSignOut = true }
                        .accessibilityIdentifier("settings.signOut")
                }

                Section {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        if isDeleting { ProgressView() } else { Text("Delete account") }
                    }
                    .disabled(isDeleting)
                    .accessibilityIdentifier("settings.deleteAccount")
                } footer: {
                    Text("Permanently deletes your login and profile. If nobody else is in \(state.snapshot.account.name), the family and all of its care data are deleted too.")
                }

                if let error = session.errorMessage {
                    Section { FormErrorText(message: error) }
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    if let email = session.signedInUser?.email {
                        LabeledContent("Signed in as", value: email)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                session.errorMessage = nil
                name = state.currentMember?.name ?? ""
                city = state.currentMember?.city ?? ""
                phone = state.currentMember?.phone ?? ""
            }
            .sheet(isPresented: $showHealth) { HealthPermissionsView().environment(state) }
            .confirmationDialog("Sign out of CareCompanion?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
            .alert("Delete your account?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    Task {
                        isDeleting = true
                        _ = await session.deleteAccount()
                        isDeleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

private struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("What CareCompanion stores") {
                Text("Your name, city and phone number; your family's name and members; the senior's details, check-ins, moods and notes, medicines, visits, emergency contacts, SOS alerts and family messages.")
            }
            Section("Apple Health") {
                Text("Only on the senior's own iPhone, and only after they allow it. CareCompanion reads steps, sleep and resting heart rate and shares one daily total for each with their family. Individual Health samples never leave the phone, and nothing is written to Apple Health.")
            }
            Section("Who can see it") {
                Text("Only people who have joined your family with its invite code. Access is enforced by the database for every request.")
            }
            Section("Deleting your data") {
                Text("Settings › Delete account removes your login and profile immediately. If you're the last member of your family, the family and all its care data are deleted too.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
