import CareCore
import SwiftUI

struct ProfileSetupView: View {
    @Environment(SessionController.self) private var session
    @State private var name = ""
    @State private var city = ""
    @State private var phone = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("About you")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .padding(.top, 56)
                Text("Your family sees your name, and can call you from the app with your phone number.")
                    .font(.system(size: 17))
                    .foregroundStyle(CareTheme.secondaryText)
                VStack(spacing: 14) {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .careField()
                        .accessibilityIdentifier("profile.name")
                    TextField("City (optional)", text: $city)
                        .textContentType(.addressCity)
                        .careField()
                    TextField("Phone number (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .careField()
                        .accessibilityIdentifier("profile.phone")
                }
                FormErrorText(message: session.errorMessage)
                PrimaryActionButton(title: "Continue", isLoading: session.isBusy,
                                    isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task { await session.saveProfile(displayName: name, city: city, phone: phone) }
                }
                .accessibilityIdentifier("profile.continue")
                SignedInFooter()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background.ignoresSafeArea())
        .onAppear {
            name = session.profile?.displayName ?? ""
            city = session.profile?.city ?? ""
            phone = session.profile?.phone ?? ""
        }
    }
}

struct AccountSetupView: View {
    private enum Choice: String, CaseIterable, Identifiable {
        case create = "Start a family"
        case join = "Join with a code"
        var id: String { rawValue }
    }

    @Environment(SessionController.self) private var session
    @State private var role: CareRole = .family
    @State private var choice: Choice = .create
    @State private var familyName = ""
    @State private var inviteCode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Who are you in the family?")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .padding(.top, 56)

                RoleCard(icon: "person.2", title: "I look after someone",
                         subtitle: "See their check-ins, medicines, visits and health.", selected: role == .family) {
                    role = .family
                }
                .accessibilityIdentifier("setup.role.family")
                RoleCard(icon: "leaf", title: "I'm the senior",
                         subtitle: "Big buttons to check in, record mood and call for help.", selected: role == .senior) {
                    role = .senior
                    choice = .join
                }
                .accessibilityIdentifier("setup.role.senior")

                Picker("Account", selection: $choice) {
                    ForEach(Choice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                if choice == .create {
                    TextField("Family name, e.g. Sharma family", text: $familyName)
                        .careField()
                        .accessibilityIdentifier("setup.familyName")
                    Text("You'll get an invite code to share with the rest of the family.")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.secondaryText)
                } else {
                    TextField("Invite code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .careField()
                        .accessibilityIdentifier("setup.inviteCode")
                    Text("Ask a family member for the code in their CareCompanion settings.")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.secondaryText)
                }

                FormErrorText(message: session.errorMessage)
                PrimaryActionButton(title: choice == .create ? "Create family" : "Join family", isLoading: session.isBusy,
                                    isDisabled: (choice == .create ? familyName : inviteCode).trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task {
                        if choice == .create {
                            await session.createAccount(name: familyName, role: role)
                        } else {
                            await session.joinAccount(code: inviteCode, role: role)
                        }
                    }
                }
                .accessibilityIdentifier("setup.submit")
                SignedInFooter()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background.ignoresSafeArea())
        .onChange(of: choice) { session.errorMessage = nil }
    }
}

private struct RoleCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CircleIcon(systemName: icon, color: selected ? .white : CareTheme.sageDark, size: 52, iconSize: 22,
                           fillOpacity: selected ? 0.22 : 0.16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 19, weight: .black))
                    Text(subtitle).font(.system(size: 14)).opacity(0.8)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
            }
            .foregroundStyle(selected ? .white : CareTheme.ink)
            .padding(18)
            .background(selected ? CareTheme.sage : .white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(selected ? .clear : CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SignedInFooter: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        VStack(spacing: 6) {
            if let email = session.signedInUser?.email {
                Text("Signed in as \(email)").font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
            }
            Button("Sign out") { Task { await session.signOut() } }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CareTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// A caregiver's family has no seniors yet.
struct AddFirstSeniorView: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var age = 70
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Who are you caring for?")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .padding(.top, 24)
                    Text("Their time zone decides what \"today\" means for check-ins and medicines.")
                        .font(.system(size: 16))
                        .foregroundStyle(CareTheme.secondaryText)
                    SeniorDetailsFields(name: $name, age: $age, city: $city, timeZone: $timeZone)
                    PrimaryActionButton(title: "Add senior", isLoading: isSaving,
                                        isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                        Task {
                            isSaving = true
                            await state.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZone)
                            isSaving = false
                        }
                    }
                    .accessibilityIdentifier("senior.form.save")
                    InviteCodeCard()
                    SignedInFooter()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CareTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// A senior member signed in on their own phone but isn't linked to a senior record yet.
struct SeniorLinkView: View {
    @Environment(AppState.self) private var state
    @State private var creatingOwnProfile = false
    @State private var name = ""
    @State private var age = 70
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier
    @State private var isSaving = false

    private var unlinked: [AccountSenior] { state.snapshot.seniors.filter { $0.profileID == nil } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(creatingOwnProfile || unlinked.isEmpty ? "Set up your profile" : "Which one is you?")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .padding(.top, 24)

                    if !creatingOwnProfile && !unlinked.isEmpty {
                        Text("Your family already added you. Tap your name to use CareCompanion on this iPhone.")
                            .font(.system(size: 17))
                            .foregroundStyle(CareTheme.secondaryText)
                        ForEach(unlinked) { senior in
                            Button {
                                Task {
                                    isSaving = true
                                    await state.claimSenior(id: senior.id)
                                    isSaving = false
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    AvatarCircle(text: String(senior.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased(),
                                                 color: CareTheme.gold, size: 52)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(senior.name).font(.system(size: 22, weight: .black))
                                        Text([senior.city, "\(senior.age) years"].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .foregroundStyle(CareTheme.ink)
                                .padding(18)
                                .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(CareTheme.cardStroke))
                            }
                            .buttonStyle(.plain)
                            .disabled(isSaving)
                        }
                        Button("I'm not listed") { creatingOwnProfile = true }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CareTheme.sageDark)
                    } else {
                        Text("Add your details so your family sees the right day and time for you.")
                            .font(.system(size: 17))
                            .foregroundStyle(CareTheme.secondaryText)
                        SeniorDetailsFields(name: $name, age: $age, city: $city, timeZone: $timeZone)
                        PrimaryActionButton(title: "Save", isLoading: isSaving,
                                            isDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty) {
                            Task {
                                isSaving = true
                                await state.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZone, isMe: true)
                                isSaving = false
                            }
                        }
                        if !unlinked.isEmpty {
                            Button("Back to the list") { creatingOwnProfile = false }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CareTheme.sageDark)
                        }
                    }
                    SignedInFooter()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .background(CareTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if name.isEmpty { name = state.currentMember?.name ?? "" }
                if city.isEmpty { city = state.currentMember?.city ?? "" }
            }
        }
    }
}

struct InviteCodeCard: View {
    @Environment(AppState.self) private var state

    private var shareText: String {
        "Join \(state.snapshot.account.name) on CareCompanion with invite code \(state.snapshot.account.inviteCode)."
    }

    var body: some View {
        LovableCard(fill: CareTheme.sagePale, stroke: CareTheme.sage.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Invite your family").font(.system(size: 17, weight: .black))
                Text("Anyone with this code can join \(state.snapshot.account.name), including the senior on their own iPhone.")
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.mutedText)
                HStack {
                    Text(state.snapshot.account.inviteCode)
                        .font(.system(size: 26, weight: .black, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("invite.code")
                    Spacer()
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            }
        }
    }
}
