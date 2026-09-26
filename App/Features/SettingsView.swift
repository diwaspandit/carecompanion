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
    @State private var addingContact = false
    @State private var editingContact: EmergencyContact?
    @State private var savingMemberID: String?
    @AppStorage(CareAppearance.storageKey) private var appearance = CareAppearance.system.rawValue

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

                Section {
                    Picker("Theme", selection: $appearance) {
                        ForEach(CareAppearance.allCases, id: \.rawValue) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                    .accessibilityIdentifier("settings.appearance")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System follows the iPhone. The Apple Watch stays light unless Dark is chosen. Light and Dark use the same colors on the iPhone and the watch.")
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

                if state.role == .senior, state.linkedSenior != nil {
                    sosContactsSection
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
            .sheet(isPresented: $addingContact) { EmergencyContactFormView(contact: nil).environment(state) }
            .sheet(item: $editingContact) { EmergencyContactFormView(contact: $0).environment(state) }
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

private extension SettingsView {
    var sosContacts: [EmergencyContact] { state.selectedSummary?.contacts ?? [] }

    var familyCandidates: [AccountMember] {
        state.snapshot.members.filter { member in
            member.profileID != state.currentProfileID
                && !sosContacts.contains { PhoneLinks.sameNumber($0.phone, member.phone) }
        }
    }

    var sosContactsSection: some View {
        Section {
            if sosContacts.isEmpty {
                Text("No SOS contact yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(sosContacts) { contact in
                Button {
                    editingContact = contact
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                        Text(contact.relation.isEmpty ? contact.phone : "\(contact.relation) · \(contact.phone)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.sos.contact.\(contact.id)")
            }
            ForEach(familyCandidates) { member in
                let title = member.name.isEmpty ? "Family member" : member.name
                if PhoneLinks.call(member.phone) == nil {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text("No phone number yet. They can add one under Your profile in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(savingMemberID == member.id ? "Adding \(title)…" : "Add \(title)") {
                        Task { await addFamilyMember(member) }
                    }
                    .disabled(savingMemberID != nil)
                    .accessibilityIdentifier("settings.sos.add.\(member.id)")
                }
            }
            Button("Add someone else") { addingContact = true }
                .accessibilityIdentifier("settings.sos.addOther")
        } header: {
            Text("SOS contacts")
        } footer: {
            Text("When you press SOS, CareCompanion notifies your family and calls the first contact on this list. The iPhone’s own Emergency SOS list can’t be changed from an app, so these contacts are used inside CareCompanion.")
        }
    }

    func addFamilyMember(_ member: AccountMember) async {
        if let seniorID = state.linkedSenior?.id {
            state.selectSenior(id: seniorID)
        }
        savingMemberID = member.id
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await state.saveEmergencyContact(
            name: name.isEmpty ? "Family member" : name,
            relation: member.role == .senior ? "Senior" : "Family",
            phone: member.phone
        )
        savingMemberID = nil
    }
}

private struct PrivacyInfoView: View {
    var body: some View {
        List {
            Section("What CareCompanion stores") {
                Text("Your name, city and phone number; your family's name and members; the senior's details, check-ins, moods and notes, medicines, visits, emergency contacts, SOS alerts, and family messages, including voice messages.")
            }
            Section("Apple Health") {
                Text("The senior's Apple Watch reads heart rate, blood pressure, sleep and steps and sends them to their iPhone. Whether the watch is being worn is sent as it changes. The iPhone saves the health totals for the family once an hour. Nothing is written to Apple Health.")
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
