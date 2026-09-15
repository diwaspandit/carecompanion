import SwiftUI
import CareCore

private enum CareRuntime {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    static var fastSOS: Bool { ProcessInfo.processInfo.arguments.contains("--fast-sos") }
}

@main
struct CareCompanionApp: App {
    @State private var live = LiveModeController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(live)
                .preferredColorScheme(.light)
                .onOpenURL { url in Task { await live.handleOpenURL(url) } }
        }
    }
}

private struct RootView: View {
    @Environment(LiveModeController.self) private var live
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDevMenu = false
    @State private var didRestoreSession = false

    var body: some View {
        Group {
            // Database-only: Show auth flow if not signed in or not ready
            if !didRestoreSession {
                // Still checking session
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CareTheme.background)
            } else if !live.isSignedIn {
                // Not signed in - show sign in
                AuthFlowView()
            } else if !live.hasAccount {
                // Signed in but no account - show create/join
                AccountSetupView()
            } else if !live.hasSenior {
                // Has account but no senior - show add senior
                AddSeniorFlowView()
            } else if !live.isLive {
                // Has everything, connecting to database...
                ProgressView("Connecting to database...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CareTheme.background)
                    .task {
                        await live.goLive()
                        // Request health permissions and sync after going live
                        if let liveState = live.liveState {
                            try? await liveState.requestHealthPermissions()
                            await liveState.syncHealthData()
                        }
                    }
            } else if let state = live.liveState {
                // Fully connected - show main app with real data
                MainAppView(state: state, showDevMenu: $showDevMenu)
            }
        }
        .task {
            // Restore session on app launch
            await live.restore()
            didRestoreSession = true
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Sync health data when app becomes active
            if newPhase == .active, let state = live.liveState {
                Task {
                    await state.syncHealthData()
                }
            }
        }
    }
}

private struct MainAppView: View {
    let state: AppState
    @Binding var showDevMenu: Bool

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            ZStack(alignment: .bottom) {
                switch state.screen {
                case .onboarding:
                    OnboardingView(showDevMenu: $showDevMenu)
                        .environment(state)
                case .seniorHome:
                    SeniorHomeView(showDevMenu: $showDevMenu)
                        .environment(state)
                case .familyDashboard:
                    FamilyDashboardView(showDevMenu: $showDevMenu)
                        .environment(state)
                }
                if let message = state.toastMessage {
                    ToastView(message: message)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 84)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            state.clearToast()
                        }
                }
            }
            .background(CareTheme.background.ignoresSafeArea())
        }
        .environment(state)
        .tint(CareTheme.sageDark)
        .sheet(isPresented: $showDevMenu) { DevMenuView().environment(state) }
        .sheet(item: $state.paywallContext) { context in
            PaywallFallbackView(context: context)
                .environment(state)
                .presentationDetents([.medium, .large])
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.screen)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toastMessage)
        .task {
            // Set up automatic health sync
            await state.setupAutomaticHealthSync()
        }
    }
}

// MARK: - Auth Flow Views

private struct AuthFlowView: View {
    @Environment(LiveModeController.self) private var live
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            CircleIcon(systemName: "heart.text.square", color: CareTheme.sageDark, size: 56, iconSize: 25, fillOpacity: 0.20)

            Text("Welcome to\nCareCompanion")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
                .multilineTextAlignment(.center)

            Text("Care that travels across time zones")
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.secondaryText)

            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                Button {
                    Task { await live.signIn(email: email, password: password) }
                } label: {
                    Text("Sign In")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(email.isEmpty || password.isEmpty || live.isBusy)
                .opacity((email.isEmpty || password.isEmpty) ? 0.6 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)

            if let message = live.message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            if live.isBusy {
                ProgressView()
            }

            Spacer()
        }
        .background(CareTheme.background)
    }
}

private struct AccountSetupView: View {
    @Environment(LiveModeController.self) private var live
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var showJoin = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Set Up Your Account")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)

            Text("Signed in as \(live.signedInEmail ?? "")")
                .font(.system(size: 14))
                .foregroundStyle(CareTheme.secondaryText)

            VStack(spacing: 16) {
                if !showJoin {
                    TextField("Family Name (e.g., Sharma family)", text: $familyName)
                        .padding()
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                    Button {
                        Task { await live.createAccount(name: familyName, role: .family) }
                    } label: {
                        Text("Create Family Account")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(familyName.isEmpty || live.isBusy)

                    Button("Have an invite code?") {
                        showJoin = true
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.sageDark)
                } else {
                    TextField("Invite Code", text: $inviteCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                    Button {
                        Task { await live.joinAccount(code: inviteCode, role: .family) }
                    } label: {
                        Text("Join Account")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(inviteCode.isEmpty || live.isBusy)

                    Button("Create new account instead") {
                        showJoin = false
                    }
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.sageDark)
                }
            }
            .padding(.horizontal, 24)

            if let message = live.message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            if live.isBusy {
                ProgressView()
            }

            Spacer()

            Button("Sign Out") {
                Task { await live.signOut() }
            }
            .font(.system(size: 14))
            .foregroundStyle(CareTheme.secondaryText)
            .padding(.bottom, 32)
        }
        .background(CareTheme.background)
    }
}

private struct AddSeniorFlowView: View {
    @Environment(LiveModeController.self) private var live
    @State private var name = ""
    @State private var age = 74
    @State private var city = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Add a Senior")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)

            Text("Who will you be caring for?")
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.secondaryText)

            VStack(spacing: 16) {
                TextField("Senior's Name", text: $name)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                HStack {
                    Text("Age")
                        .foregroundStyle(CareTheme.ink)
                    Spacer()
                    Stepper("\(age)", value: $age, in: 50...110)
                }
                .padding()
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                TextField("City (e.g., Kathmandu, Nepal)", text: $city)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CareTheme.cardStroke))

                Button {
                    Task {
                        await live.addSenior(name: name, age: age, city: city, timeZone: TimeZone.current.identifier)
                        await live.restore()
                    }
                } label: {
                    Text("Add Senior")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                }
                .disabled(name.isEmpty || city.isEmpty || live.isBusy)
            }
            .padding(.horizontal, 24)

            if let message = live.message {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }

            if live.isBusy {
                ProgressView()
            }

            Spacer()

            Button("Sign Out") {
                Task { await live.signOut() }
            }
            .font(.system(size: 14))
            .foregroundStyle(CareTheme.secondaryText)
            .padding(.bottom, 32)
        }
        .background(CareTheme.background)
    }
}

private struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Binding var showDevMenu: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleIcon(systemName: "heart.text.square", color: CareTheme.sageDark, size: 56, iconSize: 25, fillOpacity: 0.20)
                .padding(.top, 70)
                .padding(.bottom, 32)
                .onLongPressGesture { showDevMenu = true }

            Text("Care that travels\nacross time zones.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .lineSpacing(1)
                .foregroundStyle(CareTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.title")

            Text("CareCompanion connects elders at home\nwith the family looking after them from far\naway.")
                .font(.system(size: 17, weight: .regular))
                .lineSpacing(7)
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 16)

            Spacer(minLength: 110)

            Text("Are you a senior or a family member?")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CareTheme.mutedText)
                .padding(.bottom, 16)

            Button {
                state.chooseRole(.senior)
            } label: {
                RoleChoiceRow(iconText: "🌿", title: "I am a senior", subtitle: "Simple screens, big buttons", fill: CareTheme.sage, foreground: .white, iconFill: .white.opacity(0.18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.senior")

            Button {
                state.chooseRole(.family)
            } label: {
                RoleChoiceRow(iconName: "person.2", title: "I am a family member", subtitle: "Dashboard, health data and\nalerts", fill: .white, foreground: CareTheme.ink, iconFill: CareTheme.grayPill)
            }
            .buttonStyle(.plain)
            .padding(.top, 18)

            Text("You can switch roles later in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(CareTheme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CareTheme.background)
    }
}

private struct RoleChoiceRow: View {
    var iconText: String?
    var iconName: String?
    let title: String
    let subtitle: String
    let fill: Color
    let foreground: Color
    let iconFill: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(iconFill)
                if let iconText {
                    Text(iconText).font(.system(size: 26))
                } else if let iconName {
                    Image(systemName: iconName).font(.system(size: 25, weight: .bold))
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(.system(size: 14))
                    .lineLimit(3)
                    .lineSpacing(2)
                    .opacity(0.72)
            }
            .layoutPriority(1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 20, weight: .bold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 20)
        .frame(height: 100)
        .background(fill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(fill == .white ? CareTheme.cardStroke : Color.clear))
        .shadow(color: fill == .white ? CareTheme.shadow : CareTheme.sage.opacity(0.25), radius: 14, y: 8)
    }
}

private struct SeniorHomeView: View {
    @Environment(AppState.self) private var state
    @Binding var showDevMenu: Bool
    @State private var showSOS = false
    @State private var showHealthPermissions = false

    var body: some View {
        if state.seniorTab == .mood {
            MoodScreen()
        } else if state.seniorTab == .medicines {
            SeniorMedicinesScreen()
        } else if state.seniorTab == .visits {
            SeniorVisitsScreen()
        } else if state.seniorTab == .messages {
            SeniorMessagesScreen()
        } else {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("CareCompanion")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(CareTheme.ink)
                            .onLongPressGesture { showDevMenu = true }
                            .accessibilityIdentifier("app.logo")
                        Spacer()
                        Button {
                            showHealthPermissions = true
                        } label: {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(CareTheme.sage)
                        }
                        .accessibilityIdentifier("senior.healthSettings")
                        Button {
                            showSOS = true
                        } label: {
                            Label("SOS", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .background(CareTheme.coral, in: Capsule())
                        }
                        .accessibilityIdentifier("senior.sos")
                    }
                    .padding(.top, 26)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hello,\n\(state.selectedSummary?.firstName ?? "there")")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(CareTheme.ink)
                            .lineSpacing(0)
                        Text("Wednesday, 2 September")
                            .font(.system(size: 22))
                            .foregroundStyle(CareTheme.secondaryText)
                    }

            Button {
                Task { await state.checkIn() }
            } label: {
                VStack(spacing: 22) {
                    CircleIcon(systemName: state.isCheckedIn ? "checkmark" : "heart", color: .white, size: 82, iconSize: 44, fillOpacity: 0.24)
                    Text(state.isCheckedIn ? "I'm okay" : "I'm okay")
                        .font(.system(size: 32, weight: .black))
                    Text(state.isCheckedIn ? "Shared with your family" : "Tap to tell your family")
                        .font(.system(size: 19))
                        .opacity(0.92)
                }
            }
                    .buttonStyle(ReferenceButtonStyle(fill: CareTheme.sage, height: 260))
                    .accessibilityIdentifier("senior.checkIn")
                    .simultaneousGesture(TapGesture().onEnded {
                        if CareRuntime.isUITesting {
                            Task { await state.checkIn() }
                        }
                    })

                    MedicineListView()
                    NextVisitCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            SeniorBottomBar()
        }
        .background(CareTheme.background)
        .fullScreenCover(isPresented: $showSOS) {
            SOSFlowView(isPresented: $showSOS)
        }
        .sheet(isPresented: $showHealthPermissions) {
            HealthPermissionsView()
        }
        }
    }
}

private struct SeniorBottomBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            SeniorBarButton(title: "Home", icon: "house", active: state.seniorTab == .home) { state.seniorTab = .home }
            SeniorBarButton(title: "Medicines", icon: "capsule", active: state.seniorTab == .medicines) { state.seniorTab = .medicines }
            SeniorBarButton(title: "Visits", icon: "calendar", active: state.seniorTab == .visits) { state.seniorTab = .visits }
            SeniorBarButton(title: "Messages", icon: "bubble.right", active: state.seniorTab == .messages) { state.seniorTab = .messages }
        }
        .padding(.top, 10)
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .background(.white)
        .overlay(Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1), alignment: .top)
    }
}

private struct SeniorBarButton: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 24, weight: .medium))
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(active ? CareTheme.sageDark : CareTheme.secondaryText)
            .padding(.vertical, 9)
            .background(active ? CareTheme.sagePale : Color.clear, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("senior.tab.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
    }
}

private struct SeniorMedicinesScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Medicines")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(CareTheme.ink)
                        .padding(.top, 26)
                        .accessibilityIdentifier("senior.medicines.title")
                    MedicineListView()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            SeniorBottomBar()
        }
        .background(CareTheme.background)
    }
}

private struct SeniorVisitsScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Visits")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(CareTheme.ink)
                        .padding(.top, 26)
                        .accessibilityIdentifier("senior.visits.title")
                    NextVisitCard()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            SeniorBottomBar()
        }
        .background(CareTheme.background)
    }
}

private struct SeniorMessagesScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Messages")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(CareTheme.ink)
                        .padding(.top, 26)
                        .accessibilityIdentifier("senior.messages.title")
                    LovableCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("\(state.selectedSummary?.firstName ?? "You") and family").font(.system(size: 19, weight: .black))
                            Text("Messaging features are coming soon. The current focus is on check-ins, alerts, and appointment preparation.")
                                .font(.system(size: 15))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            SeniorBottomBar()
        }
        .background(CareTheme.background)
    }
}

private struct MedicineListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today's medicines")
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(CareTheme.ink)
            ForEach(state.snapshot.medications.filter { $0.seniorID == state.selectedSeniorID }) { medication in
                MedicineRow(medication: medication)
            }
            Button {
                let next = state.selectedSummary?.missedMedications.first
                state.showToast(next.map { "Next reminder: \($0.name) at \($0.scheduledTime)." } ?? "All of today's medicines are marked taken.")
            } label: {
                Label("See medicine reminder", systemImage: "bell")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(CareTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(CareTheme.grayPill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MedicineRow: View {
    @Environment(AppState.self) private var state
    let medication: Medication

    var body: some View {
        Button {
            Task { await state.toggleMedication(id: medication.id) }
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(medication.taken ? CareTheme.sage : .white)
                        .overlay(Circle().stroke(medication.taken ? CareTheme.sage : Color.black.opacity(0.18), lineWidth: 2))
                    if medication.taken {
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text(medication.name)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(CareTheme.ink)
                    Text(doseText(for: medication))
                        .font(.system(size: 18))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
            }
            .padding(20)
            .background(medication.taken ? CareTheme.sagePale : .white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(medication.taken ? CareTheme.sage.opacity(0.38) : CareTheme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func doseText(for medication: Medication) -> String {
        switch medication.name {
        case "Amlodipine": return "5 mg - 1 tablet · \(medication.scheduledTime)"
        case "Metformin": return "500 mg - 1 tablet · \(medication.scheduledTime)"
        case "Calcium + D3": return "1 tablet · \(medication.scheduledTime)"
        default: return "10 mg - 1 tablet · \(medication.scheduledTime)"
        }
    }
}

private struct NextVisitCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Next Visit")
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(CareTheme.ink)
            Button {
                state.seniorTab = .visits
            } label: {
                LovableCard {
                HStack(alignment: .top, spacing: 18) {
                    CircleIcon(systemName: "calendar", color: CareTheme.blue, size: 48, iconSize: 22, fillOpacity: 0.18)
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Fri, 4 Sep")
                            .font(.system(size: 24, weight: .black))
                        Text("Dr. Rana - Heart check-up")
                            .font(.system(size: 22, weight: .bold))
                        Text("10:30 AM · Norvic Hospital,\nThapathali")
                            .font(.system(size: 18))
                            .lineSpacing(5)
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                }
            }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct MoodScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 145)
            Text("How are you feeling\ntoday?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .lineSpacing(1)
            Text("Tap one face.")
                .font(.system(size: 22))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 18)
                .padding(.bottom, 44)
            moodButton("😊", title: "Good", mood: .great)
            moodButton("😐", title: "Okay", mood: .okay)
                .padding(.top, 16)
            moodButton("😔", title: "Not great", mood: .low)
                .padding(.top, 16)
            Spacer()
            SeniorBottomBar()
        }
        .padding(.horizontal, 24)
        .background(CareTheme.background)
    }

    private func moodButton(_ emoji: String, title: String, mood: Mood) -> some View {
        Button {
            Task {
                await state.recordMood(mood)
                state.switchToFamily()
            }
        } label: {
            HStack(spacing: 26) {
                Text(emoji).font(.system(size: 42))
                Text(title).font(.system(size: 28, weight: .black))
                Spacer()
            }
            .padding(.horizontal, 30)
            .frame(height: 118)
            .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mood.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
        .simultaneousGesture(TapGesture().onEnded {
            if CareRuntime.isUITesting {
                Task {
                    await state.recordMood(mood)
                    state.switchToFamily()
                }
            }
        })
    }
}

private struct SOSFlowView: View {
    @Environment(AppState.self) private var state
    @Binding var isPresented: Bool
    @State private var seconds = 5
    @State private var notified = false

    private var familyNames: [String] {
        state.snapshot.members.filter { $0.role == .family && !$0.name.isEmpty }.map(\.name)
    }

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _seconds = State(initialValue: CareRuntime.fastSOS ? 1 : 5)
    }

    var body: some View {
        ZStack {
            (notified ? CareTheme.sage : CareTheme.coral).ignoresSafeArea()
            if notified {
                notifiedBody
            } else {
                countdownBody
            }
        }
        .task {
            while seconds > 0 && !notified {
                try? await Task.sleep(for: .seconds(1))
                seconds -= 1
            }
            if !notified {
                await state.triggerSOS()
                notified = true
            }
        }
    }

    private var countdownBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 98)
            CircleIcon(systemName: "exclamationmark.triangle", color: .white, size: 110, iconSize: 52, fillOpacity: 0.24)
            Text("Sending alert to your\nfamily...")
                .font(.system(size: 34, weight: .black))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .foregroundStyle(.white)
                .padding(.top, 34)
            Text("Stay calm. Help is on the way.")
                .font(.system(size: 23))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 24)
            Text("\(seconds)")
                .font(.system(size: 92, weight: .black))
                .foregroundStyle(.white)
                .padding(.top, 60)
                .accessibilityIdentifier("sos.countdown")
            Spacer()
            Button {
                isPresented = false
            } label: {
                Text("Cancel")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(Color(red: 130/255, green: 53/255, blue: 43/255))
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    private var notifiedBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 96)
            CircleIcon(systemName: "checkmark", color: .white, size: 112, iconSize: 54, fillOpacity: 0.24)
            Text("Your family has been\nnotified")
                .font(.system(size: 33, weight: .black))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .foregroundStyle(.white)
                .padding(.top, 36)
                .accessibilityIdentifier("sos.notified.title")
            Text("\(familyNames.isEmpty ? "Your family" : familyNames.formatted(.list(type: .and))) received your alert. Someone will call you very soon.")
                .font(.system(size: 23))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 24)
            Spacer()
            Button {
                state.showToast("Calling \(familyNames.first ?? "your family") now...")
            } label: {
                Label("Call \(familyNames.first ?? "family") now", systemImage: "phone.connection")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(CareTheme.sageDark)
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(.white, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
            .padding(.horizontal, 28)
            Button {
                isPresented = false
                state.switchToFamily(tab: .emergency)
            } label: {
                Text("Back to home")
                    .font(.system(size: 21, weight: .black))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .overlay(RoundedRectangle(cornerRadius: 27).stroke(.white.opacity(0.38), lineWidth: 2))
            }
            .accessibilityIdentifier("sos.backToFamily")
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
    }
}

private struct FamilyDashboardView: View {
    @Environment(AppState.self) private var state
    @Binding var showDevMenu: Bool

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch state.familyTab {
                    case .dashboard:
                        FamilyHome(showDevMenu: $showDevMenu)
                    case .health:
                        HealthTimelineView()
                    case .appointments:
                        AppointmentsView()
                    case .emergency:
                        AlertsView(showDevMenu: $showDevMenu)
                    case .chats:
                        ChatsView()
                    case .profile:
                        FamilyProfileView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)
                .padding(.bottom, 106)
            }
            ReferenceBottomBar(
                items: [
                    (.dashboard, "Home", "square.grid.2x2", nil),
                    (.health, "Health", "waveform.path.ecg", nil),
                    (.emergency, "Alerts", "bell", (state.activeAlertCount > 0 ? state.activeAlertCount : nil) as Int?),
                    (.appointments, "Visits", "calendar", nil),
                    (.profile, "Profile", "person.crop.circle", nil)
                ],
                selection: $state.familyTab
            )
        }
        .background(CareTheme.background)
        .task {
            if state.hasPremiumAccess && state.careInsight == nil {
                await state.loadCareInsight()
            }
        }
    }
}

private enum SeniorPalette {
    static func color(at index: Int) -> Color {
        [CareTheme.gold, CareTheme.sage, CareTheme.blue, CareTheme.coral][index % 4]
    }
}

private struct FamilyHome: View {
    @Environment(AppState.self) private var state
    @Binding var showDevMenu: Bool

    private var caregiver: AccountMember? {
        state.snapshot.members.first { $0.role == .family && !$0.name.isEmpty }
    }
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        guard let caregiver else { return "\(part) · \(state.snapshot.account.name)" }
        return caregiver.city.isEmpty ? "\(part), \(caregiver.name)" : "\(part), \(caregiver.name) · \(caregiver.city)"
    }

    var body: some View {
        let indexed = Array(state.seniorSummaries.enumerated())
        let ordered = indexed.filter { $0.element.id == state.selectedSeniorID }
            + indexed.filter { $0.element.id != state.selectedSeniorID }
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Family")
                        .font(.system(size: 28, weight: .black))
                        .accessibilityIdentifier("family.title")
                    Text(greeting)
                        .font(.system(size: 15))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Text(caregiver?.name.first.map { String($0).uppercased() }
                     ?? state.snapshot.account.name.first.map { String($0).uppercased() } ?? "·")
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(CareTheme.grayPill, in: Circle())
                    .onLongPressGesture { showDevMenu = true }
                    .accessibilityIdentifier("family.avatar")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(indexed, id: \.element.id) { index, summary in
                        Button {
                            state.selectSenior(id: summary.id)
                        } label: {
                            FamilyChip(initials: summary.initials, name: summary.firstName,
                                       color: SeniorPalette.color(at: index),
                                       selected: summary.id == state.selectedSeniorID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("family.senior.\(summary.id)")
                    }
                    Button {
                        state.showToast("Plus supports up to 5 monitored seniors.")
                        state.showPaywall(for: .careInsight)
                    } label: {
                        VStack(spacing: 8) {
                            AvatarCircle(text: "+", color: CareTheme.secondaryText, size: 58)
                            Text("Add").font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if indexed.isEmpty {
                LovableCard {
                    Text("No seniors are linked to this account yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(CareTheme.secondaryText)
                }
            } else {
                AIInsightReferenceCard()
                ForEach(ordered, id: \.element.id) { index, summary in
                    Button {
                        state.selectSenior(id: summary.id)
                    } label: {
                        SeniorReferenceCard(summary: summary, color: SeniorPalette.color(at: index),
                                            isSelected: summary.id == state.selectedSeniorID)
                    }
                    .buttonStyle(.plain)
                }
                if let selected = state.selectedSummary, let item = selected.attentionItems.first {
                    Button {
                        state.familyTab = .emergency
                    } label: {
                        HStack(spacing: 16) {
                            Text("\(state.activeAlertCount)")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(CareTheme.coral, in: Circle())
                            Text("\(selected.firstName): \(item)")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(Color(red: 151/255, green: 61/255, blue: 48/255))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(Color(red: 151/255, green: 61/255, blue: 48/255))
                        }
                        .padding(16)
                        .background(CareTheme.coralPale, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(CareTheme.coral.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FamilyChip: View {
    let initials: String
    let name: String
    let color: Color
    let selected: Bool

    var body: some View {
        VStack(spacing: 7) {
            AvatarCircle(text: initials, color: color, size: 58, selected: selected)
            Text(name).font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
        }
    }
}

private struct AIInsightReferenceCard: View {
    @Environment(AppState.self) private var state

    private struct Inputs: Equatable {
        let premium: Bool
        let summary: SeniorCareSummary?
    }

    private var bodyText: String {
        guard let care = state.selectedSummary else { return "Add a senior to see care insights." }
        if state.hasPremiumAccess {
            return state.careInsight?.summary ?? "Reviewing \(care.firstName)'s latest care data…"
        }
        let count = care.attentionItems.count
        return count == 0
            ? "\(care.firstName)'s routine looks steady today. Unlock the full insight for observations and suggested follow-ups."
            : "\(count) \(count == 1 ? "thing is" : "things are") worth a look for \(care.firstName) today. Unlock the full insight to see the details."
    }

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CareTheme.gold)
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI insight")
                        .font(.system(size: 15, weight: .black))
                    Text(bodyText)
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(CareTheme.mutedText)
                    if state.hasPremiumAccess, let insight = state.careInsight {
                        ForEach(insight.observations, id: \.self) { observation in
                            Label(observation, systemImage: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                        Text(insight.suggestion)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CareTheme.sageDark)
                        Text("Full premium insight ready")
                            .font(.system(size: 1))
                            .foregroundStyle(.clear)
                            .accessibilityIdentifier("insight.full")
                    }
                    Button {
                        if state.hasPremiumAccess {
                            state.familyTab = .health
                        } else {
                            state.showPaywall(for: .careInsight)
                        }
                    } label: {
                        Label(state.hasPremiumAccess ? "View health timeline" : "Unlock full insight", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(CareTheme.sageDark)
                    }
                    .accessibilityIdentifier(state.hasPremiumAccess ? "insight.timeline" : "insight.unlock")
                }
            }
        }
        .task(id: Inputs(premium: state.hasPremiumAccess, summary: state.selectedSummary)) {
            if state.hasPremiumAccess && state.selectedSummary != nil {
                await state.loadCareInsight()
            }
        }
    }
}

private struct SeniorReferenceCard: View {
    let summary: SeniorCareSummary
    let color: Color
    let isSelected: Bool

    private var subtitle: String {
        summary.senior.city.isEmpty ? "\(summary.senior.age) years" : "\(summary.senior.age) years · \(summary.senior.city)"
    }
    private var checkInText: String {
        guard let date = summary.checkInDate else { return "No check-in yet today" }
        let zone = TimeZone(identifier: summary.senior.timeZoneIdentifier) ?? .current
        let time = date.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
        return zone.identifier == TimeZone.current.identifier ? "Checked in at \(time)" : "Checked in at \(time) their time"
    }
    private var moodEmoji: String {
        switch summary.mood {
        case .great: "😊"
        case .okay: "🙂"
        case .low: "😔"
        case nil: "😐"
        }
    }
    private var status: (text: String, color: Color, fill: Color) {
        if summary.hasEmergency { return ("SOS open", CareTheme.coral, CareTheme.coralPale) }
        if summary.needsAttention { return ("Needs attention", Color(red: 107/255, green: 85/255, blue: 43/255), CareTheme.goldPale) }
        return ("All good", CareTheme.sageDark, CareTheme.sagePale)
    }
    private var medicationText: String {
        summary.medicationsTotal == 0 ? "None set up" : "\(summary.medicationsTaken) of \(summary.medicationsTotal) taken"
    }
    private var stepsText: String {
        guard let steps = summary.latestHealth?.steps, steps > 0 else { return "—" }
        return steps.formatted()
    }
    private var sleepText: String {
        guard let minutes = summary.latestHealth?.sleepMinutes, minutes > 0 else { return "—" }
        return SeniorCareSummary.duration(minutes: minutes)
    }
    private var dataSourceNotice: String {
        guard let latest = summary.latestHealth else { return "No health data synced yet. Grant Health access to sync." }
        let day = latest.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        return latest.source == "healthkit"
            ? "Steps and sleep from Apple Health · \(day)"
            : "Steps and sleep source: \(latest.source) · \(day)"
    }
    private func identifier(_ name: String) -> String? { isSelected ? "family.\(name)" : nil }

    var body: some View {
        LovableCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    AvatarCircle(text: summary.initials, color: color, size: 48, selected: isSelected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.senior.name).font(.system(size: 20, weight: .black))
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                    Spacer()
                    PlainPill(text: status.text, icon: "circle.fill", color: status.color, fill: status.fill)
                }
                HStack {
                    Image(systemName: "clock")
                    Text(checkInText)
                        .font(.system(size: 15, weight: .black))
                        .accessibilityIdentifier(identifier("checkedIn") ?? "")
                    Spacer()
                    Text(moodEmoji).font(.system(size: 24))
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(CareTheme.grayPill, in: Capsule())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SmallMetric(title: "Medications", value: medicationText, icon: "capsule", color: CareTheme.gold, identifier: identifier("medications"))
                    SmallMetric(title: "Latest mood", value: summary.mood?.rawValue ?? "Not recorded", icon: "waveform.path.ecg", color: CareTheme.sage)
                    SmallMetric(title: "Steps", value: stepsText, icon: "shoeprints.fill", color: CareTheme.blue, identifier: identifier("steps"))
                    SmallMetric(title: "Sleep", value: sleepText, icon: "moon", color: CareTheme.blue, identifier: identifier("sleep"))
                }
                Text(dataSourceNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(CareTheme.mutedText)
                    .accessibilityIdentifier(identifier("healthDataNotice") ?? "")
            }
        }
    }
}

private struct SmallMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CareTheme.secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(CareTheme.ink)
                .accessibilityIdentifier(identifier ?? "metric.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(CareTheme.grayPill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tint(color)
    }
}

private struct FamilyProfileView: View {
    @Environment(AppState.self) private var state
    @State private var showHealthPermissions = false

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var members: [AccountMember] { state.snapshot.members }
    private var zone: TimeZone { care.flatMap { TimeZone(identifier: $0.senior.timeZoneIdentifier) } ?? .current }

    private func memberDetail(_ member: AccountMember) -> String {
        let role = member.role == .family ? "Family" : "Senior"
        return member.city.isEmpty ? role : "\(role) · \(member.city)"
    }
    private var heartRateText: String {
        guard let range = care?.restingHeartRateRange else { return "—" }
        return range.lowerBound == range.upperBound ? "\(range.lowerBound) bpm" : "\(range.lowerBound)–\(range.upperBound) bpm"
    }
    private var averageStepsText: String {
        let values = (care?.healthHistory ?? []).map(\.steps).filter { $0 > 0 }
        guard !values.isEmpty else { return "—" }
        return (values.reduce(0, +) / values.count).formatted()
    }
    private var checkInText: String {
        guard let date = care?.checkInDate else { return "Not yet" }
        return date.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
    }
    private var healthNotice: String {
        guard let care, let latest = care.latestHealth else { return "No health data synced yet." }
        let source = latest.source == "healthkit" ? "Apple Health" : latest.source
        let days = care.healthHistory.count
        return "Based on \(days) synced \(days == 1 ? "day" : "days") of \(source) data."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Senior Profile")
                    .font(.system(size: 28, weight: .black))
                    .accessibilityIdentifier("profile.title")
                Text("Settings & care plan")
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }

            if let care {
                LovableCard {
                    HStack(spacing: 14) {
                        AvatarCircle(text: care.initials, color: CareTheme.gold, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(care.senior.name).font(.system(size: 20, weight: .black))
                            Text("\(care.senior.age) years").font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            if !care.senior.city.isEmpty {
                                Text(care.senior.city).font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Family members").font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                LovableCard {
                    VStack(alignment: .leading, spacing: 0) {
                        if members.isEmpty {
                            Text("No family members yet.")
                                .font(.system(size: 15))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                        ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                            HStack(spacing: 14) {
                                CircleIcon(systemName: "person.fill", color: CareTheme.sage, size: 40, iconSize: 16, fillOpacity: 0.16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name.isEmpty ? "Family member" : member.name).font(.system(size: 16, weight: .black))
                                    Text(memberDetail(member)).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            if index < members.count - 1 {
                                Divider()
                            }
                        }
                        Button {
                            state.showToast("Share your account invite code to add family members.")
                        } label: {
                            Label("Add family member", systemImage: "plus")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(CareTheme.sageDark)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.addContact")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Medications").font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                LovableCard {
                    MedicineListView()
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Baseline health stats").font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                Text(healthNotice)
                    .font(.system(size: 12))
                    .foregroundStyle(CareTheme.mutedText)
                    .accessibilityIdentifier("profile.healthDataNotice")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SmallMetric(title: "Resting heart rate", value: heartRateText, icon: "heart", color: CareTheme.coral)
                    SmallMetric(title: "Average sleep", value: care?.averageSleepMinutes.map { SeniorCareSummary.duration(minutes: $0) } ?? "—", icon: "moon", color: CareTheme.blue)
                    SmallMetric(title: "Daily steps", value: averageStepsText, icon: "shoeprints.fill", color: CareTheme.blue)
                    SmallMetric(title: "Check-in today", value: checkInText, icon: "clock", color: CareTheme.gold)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Settings").font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                VStack(spacing: 0) {
                    Button {
                        showHealthPermissions = true
                    } label: {
                        HStack {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.red)
                                .frame(width: 32)
                            Text("Health Data Permissions")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CareTheme.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                        .padding(16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CareTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.healthPermissions")
                }
            }

            Button {
                state.switchToSenior()
            } label: {
                HStack {
                    Text("Switch role").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                }
                .padding(20)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CareTheme.cardStroke))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.switchRole")
        }
        .sheet(isPresented: $showHealthPermissions) {
            HealthPermissionsView()
        }
    }
}

private struct AppointmentsView: View {
    @Environment(AppState.self) private var state

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var zone: TimeZone { care.flatMap { TimeZone(identifier: $0.senior.timeZoneIdentifier) } ?? .current }
    private var appointments: [Appointment] {
        state.snapshot.appointments.filter { $0.seniorID == state.selectedSeniorID }.sorted { $0.date < $1.date }
    }
    private var subtitle: String {
        [Date().formatted(.dateTime.month(.wide).year()), care?.senior.name].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Appointments").font(.system(size: 28, weight: .black))
                    Text(subtitle).font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Button {
                    state.showToast("Appointment creation coming soon.")
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(CareTheme.sage, in: Capsule())
                }
            }
            CalendarCard(appointmentDates: appointments.map(\.date))
            Text("Upcoming")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(CareTheme.secondaryText)
            if appointments.isEmpty {
                LovableCard {
                    Text("No appointments scheduled for \(care?.firstName ?? "this senior").")
                        .font(.system(size: 15))
                        .foregroundStyle(CareTheme.secondaryText)
                }
            }
            ForEach(appointments) { appointment in
                AppointmentRow(
                    day: appointment.date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)).uppercased()
                        + "\n" + appointment.date.formatted(Date.FormatStyle(timeZone: zone).day()),
                    title: appointment.clinician.isEmpty ? appointment.title : "\(appointment.title) · \(appointment.clinician)",
                    time: [appointment.date.formatted(Date.FormatStyle(timeZone: zone).hour().minute()), appointment.location]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    note: appointment.notes
                )
            }

            if state.hasPremiumAccess, let prep = state.appointmentPrep {
                AppointmentPrepCard(prep: prep)
            } else if !appointments.isEmpty {
                Button {
                    Task { await state.prepareAppointment() }
                } label: {
                    Label("Prepare with CareCompanion AI", systemImage: "sparkles")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(CareTheme.sage, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appointment.prepare")
            }
        }
    }
}

private struct CalendarCard: View {
    let appointmentDates: [Date]
    private let calendar = Calendar.current

    private var slots: [Int?] {
        let now = Date()
        guard let month = calendar.dateInterval(of: .month, for: now),
              let days = calendar.range(of: .day, in: .month, for: now) else { return [] }
        let mondayFirstOffset = (calendar.component(.weekday, from: month.start) + 5) % 7
        return Array(repeating: nil, count: mondayFirstOffset) + days.map { $0 }
    }
    private var marked: Set<Int> {
        Set(appointmentDates
            .filter { calendar.isDate($0, equalTo: Date(), toGranularity: .month) }
            .map { calendar.component(.day, from: $0) })
    }

    var body: some View {
        let today = calendar.component(.day, from: Date())
        LovableCard {
            VStack(spacing: 14) {
                HStack {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                        Text(day).font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 14) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        if let day = slot {
                            Text("\(day)")
                                .font(.system(size: 15, weight: day == today ? .black : .regular))
                                .foregroundStyle(day == today ? .white : CareTheme.mutedText)
                                .frame(width: 34, height: 34)
                                .background(day == today ? CareTheme.ink : (marked.contains(day) ? CareTheme.sagePale : Color.clear), in: Circle())
                        } else {
                            Color.clear.frame(width: 34, height: 34)
                        }
                    }
                }
            }
        }
    }
}

private struct AppointmentRow: View {
    let day: String
    let title: String
    let time: String
    let note: String

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 18) {
                Text(day)
                    .font(.system(size: 13, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CareTheme.ink)
                    .frame(width: 58, height: 58)
                    .background(CareTheme.grayPill, in: Circle())
                VStack(alignment: .leading, spacing: 9) {
                    Text(title).font(.system(size: 18, weight: .black))
                    Text(time).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                    Text(note).font(.system(size: 14)).foregroundStyle(CareTheme.mutedText)
                    Label("Reminder on senior's phone", systemImage: "bell")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CareTheme.sageDark)
                }
            }
        }
    }
}

private struct AppointmentPrepCard: View {
    let prep: AppointmentPrep

    var body: some View {
        LovableCard(fill: CareTheme.goldPale, stroke: CareTheme.gold.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(prep.title).font(.system(size: 18, weight: .black))
                    .accessibilityIdentifier("appointment.prep.ready")
                ForEach(prep.observations, id: \.self) { observation in
                    Label(observation, systemImage: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                ForEach(prep.questions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle")
                        .font(.system(size: 14))
                }
                Text(prep.safetyNote).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText)
            }
        }
    }
}

private struct AlertsView: View {
    @Environment(AppState.self) private var state
    @Binding var showDevMenu: Bool
    @State private var dismissedAlerts: Set<String> = []

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var name: String { care?.firstName ?? "Your senior" }
    private var zone: TimeZone { care.flatMap { TimeZone(identifier: $0.senior.timeZoneIdentifier) } ?? .current }
    private var openSOSTime: String {
        state.snapshot.alerts
            .filter { $0.seniorID == state.selectedSeniorID && !$0.acknowledged }
            .map(\.date).max()
            .map { $0.formatted(Date.FormatStyle(timeZone: zone).hour().minute()) } ?? "Now"
    }
    private func key(_ kind: String) -> String { "\(state.selectedSeniorID)-\(kind)" }

    private var showsEmergency: Bool { care?.hasEmergency == true && !dismissedAlerts.contains(key("emergency")) }
    private var missedMedications: [Medication] {
        dismissedAlerts.contains(key("medication")) ? [] : (care?.missedMedications ?? [])
    }
    private var lowActivity: (steps: Int, baseline: Int)? {
        guard !dismissedAlerts.contains(key("health")), let care, care.isStepsBelowBaseline,
              let steps = care.latestHealth?.steps, let baseline = care.baselineSteps else { return nil }
        return (steps, baseline)
    }
    private var showsCheckIn: Bool { care?.isCheckedIn == false && !dismissedAlerts.contains(key("checkin")) }
    private var visibleAlertCount: Int {
        [showsEmergency, !missedMedications.isEmpty, lowActivity != nil, showsCheckIn].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alert Center").font(.system(size: 28, weight: .black))
                .onLongPressGesture { showDevMenu = true }
                .accessibilityIdentifier("alerts.title")
            Text("\(visibleAlertCount) active \(visibleAlertCount == 1 ? "alert" : "alerts") · \(care?.senior.name ?? "no senior selected")")
                .font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
            if showsEmergency {
                AlertRow(kind: "EMERGENCY", when: openSOSTime, title: "SOS alert from \(name)", detail: "\(name) triggered SOS. Core safety is available on every plan.", color: CareTheme.coral, fill: CareTheme.coralPale, icon: "exclamationmark.triangle") {
                    state.showToast("Calling \(name) now...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    let dismissKey = key("emergency")
                    Task {
                        await state.acknowledgeEmergency()
                        dismissedAlerts.insert(dismissKey)
                    }
                }
                .accessibilityIdentifier("alerts.sos")
            }
            if let first = missedMedications.first {
                AlertRow(kind: "MEDICATION", when: "Today",
                         title: missedMedications.count == 1 ? "\(name) hasn't taken \(first.name) yet" : "\(name) hasn't taken \(missedMedications.count) medications yet",
                         detail: missedMedications.map { "\($0.name) (\($0.scheduledTime))" }.joined(separator: ", "),
                         color: CareTheme.gold, fill: .white, icon: "capsule") {
                    state.showToast("Calling \(name) about \(first.name)...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert(key("medication"))
                    state.showToast("Medication alert dismissed.")
                }
            }
            if let lowActivity {
                AlertRow(kind: "HEALTH", when: "Latest synced day", title: "Activity below recent average",
                         detail: "\(lowActivity.steps.formatted()) steps vs. a \(lowActivity.baseline.formatted())-step average on earlier days.",
                         color: CareTheme.blue, fill: CareTheme.bluePale, icon: "waveform.path.ecg") {
                    state.showToast("Calling \(name) to check in...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert(key("health"))
                }
            }
            if showsCheckIn {
                AlertRow(kind: "CHECK-IN", when: "Today", title: "No check-in yet today", detail: "\(name) hasn't checked in yet today.", color: CareTheme.gold, fill: CareTheme.grayPill.opacity(0.45), icon: "clock") {
                    state.showToast("Calling \(name) about check-in...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert(key("checkin"))
                }
            }
            if visibleAlertCount == 0 {
                LovableCard(fill: CareTheme.sagePale, stroke: CareTheme.sage.opacity(0.3)) {
                    Label("All alerts are clear", systemImage: "checkmark.circle")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(CareTheme.sageDark)
                }
            }
        }
    }
}

private struct AlertRow: View {
    let kind: String
    let when: String
    let title: String
    let detail: String
    let color: Color
    let fill: Color
    let icon: String
    let onCall: () -> Void
    let onMessage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        LovableCard(fill: fill, stroke: color.opacity(0.28)) {
            HStack(alignment: .top, spacing: 14) {
                CircleIcon(systemName: icon, color: color, size: 42, iconSize: 18, fillOpacity: 0.22)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(kind) · \(when)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(CareTheme.secondaryText)
                    Text(title).font(.system(size: 17, weight: .black))
                    Text(detail).font(.system(size: 16)).foregroundStyle(CareTheme.mutedText)
                    HStack(spacing: 10) {
                        Button(action: onCall) {
                            PlainPill(text: "Call\nnow", icon: "phone", color: .white, fill: CareTheme.sage)
                        }
                        .buttonStyle(.plain)
                        Button(action: onMessage) {
                            PlainPill(text: "Message", icon: "bubble.right", color: CareTheme.ink, fill: .white)
                        }
                        .buttonStyle(.plain)
                        Button(action: onDismiss) {
                            PlainPill(text: "Dismiss", icon: "xmark", color: CareTheme.secondaryText, fill: .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private enum HealthDay {
    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
    }
}

private struct HealthTimelineView: View {
    @Environment(AppState.self) private var state

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var history: [HealthSnapshot] { Array((care?.healthHistory ?? []).prefix(7).reversed()) }
    private var moods: [MoodEntry] { care?.moodHistory ?? [] }
    private var dataSourceNotice: String {
        guard let latest = care?.latestHealth else { return "No health data synced yet. Grant Health access from the Profile tab." }
        return latest.source == "healthkit" ? "Synced from Apple Health." : "Source: \(latest.source)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Health Timeline").font(.system(size: 28, weight: .black))
            Text("\(care?.senior.name ?? "No senior selected") · last \(history.count) synced \(history.count == 1 ? "day" : "days")")
                .font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
            Text(dataSourceNotice)
                .font(.system(size: 12))
                .foregroundStyle(CareTheme.mutedText)
                .accessibilityIdentifier("timeline.healthDataNotice")
            AIInsightReferenceCard()
            SleepChartCard(history: history, average: care?.averageSleepMinutes)
            StepsChartCard(history: history, baseline: care?.baselineSteps)
            HeartChartCard(history: history, range: care?.restingHeartRateRange)
            AdherenceCard(care: care)
            MoodTrendCard(moods: moods)
        }
    }
}

private struct ChartHeader: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon).font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
            Spacer()
            Text(value).font(.system(size: 15, weight: .black))
        }
    }
}

private struct ChartFootnote: View {
    let text: String

    var body: some View {
        Text(text).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
    }
}

private struct SleepChartCard: View {
    let history: [HealthSnapshot]
    let average: Int?

    private var latestText: String {
        guard let minutes = history.last?.sleepMinutes, minutes > 0 else { return "No data" }
        return "\(SeniorCareSummary.duration(minutes: minutes)) latest"
    }

    var body: some View {
        let longest = max(history.map(\.sleepMinutes).max() ?? 0, 1)
        LovableCard {
            VStack(alignment: .leading, spacing: 20) {
                ChartHeader(title: "Sleep", icon: "moon", value: latestText)
                if history.isEmpty {
                    ChartFootnote(text: "Sleep will appear here after the first Apple Health sync.")
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(history) { day in
                            RoundedRectangle(cornerRadius: 14)
                                .fill(day.sleepMinutes > 0 ? CareTheme.sage.opacity(0.82) : CareTheme.grayPill)
                                .frame(height: 12 + CGFloat(day.sleepMinutes) / CGFloat(longest) * 100)
                        }
                    }
                    .frame(height: 120, alignment: .bottom)
                    HStack {
                        ForEach(history) { day in
                            Text(HealthDay.weekday(day.date)).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                        }
                    }
                    ChartFootnote(text: average.map { "Average \(SeniorCareSummary.duration(minutes: $0)) across synced days" } ?? "No sleep recorded yet")
                }
            }
        }
    }
}

private struct StepsChartCard: View {
    let history: [HealthSnapshot]
    let baseline: Int?

    private var values: [Int] { history.map(\.steps).filter { $0 > 0 } }
    private var latestText: String {
        guard let steps = history.last?.steps, steps > 0 else { return "No data" }
        return "\(steps.formatted()) latest"
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 14) {
                ChartHeader(title: "Steps", icon: "shoeprints.fill", value: latestText)
                TrendChart(values: values, color: CareTheme.sage)
                ChartFootnote(text: baseline.map { "Earlier-day average \($0.formatted()) steps" } ?? "Not enough step history for an average yet")
            }
        }
    }
}

private struct HeartChartCard: View {
    let history: [HealthSnapshot]
    let range: ClosedRange<Int>?

    private var values: [Int] { history.map(\.restingHeartRate).filter { $0 > 0 } }
    private var latestText: String {
        guard let rate = history.last?.restingHeartRate, rate > 0 else { return "No data" }
        return "\(rate) bpm"
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 14) {
                ChartHeader(title: "Resting heart rate", icon: "heart", value: latestText)
                TrendChart(values: values, color: CareTheme.coral)
                ChartFootnote(text: range.map { "Range \($0.lowerBound)–\($0.upperBound) bpm" } ?? "No resting heart rate recorded yet")
            }
        }
    }
}

private struct TrendChart: View {
    let values: [Int]
    let color: Color

    var body: some View {
        if values.count < 2 {
            ChartFootnote(text: "Not enough synced days for a trend yet.")
        } else {
            MiniLineChart(values: values, color: color)
                .frame(height: 140)
        }
    }
}

private struct MiniLineChart: View {
    let values: [Int]
    let color: Color

    private var points: [CGFloat] {
        guard let low = values.min(), let high = values.max(), high > low else { return values.map { _ in 0.5 } }
        return values.map { 0.15 + 0.7 * CGFloat($0 - low) / CGFloat(high - low) }
    }

    var body: some View {
        let points = points
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            Path { path in
                for (index, point) in points.enumerated() {
                    let x = CGFloat(index) / CGFloat(points.count - 1) * width
                    let y = (1 - point) * height
                    index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                for (index, point) in points.enumerated() {
                    let x = CGFloat(index) / CGFloat(points.count - 1) * width
                    let y = (1 - point) * height
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: width, y: height))
            }
            .fill(color.opacity(0.12))
        }
    }
}

private struct AdherenceCard: View {
    let care: SeniorCareSummary?

    private var total: Int { care?.medicationsTotal ?? 0 }
    private var taken: Int { care?.medicationsTaken ?? 0 }
    private var fraction: Double { total == 0 ? 0 : Double(taken) / Double(total) }

    var body: some View {
        LovableCard {
            HStack(spacing: 22) {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(CareTheme.sage, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-90))
                    .background(Circle().stroke(CareTheme.sage.opacity(0.18), lineWidth: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Medication adherence today").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Text(total == 0 ? "—" : "\(Int((fraction * 100).rounded()))%").font(.system(size: 30, weight: .black))
                    Text(total == 0 ? "No medications set up" : "\(taken) of \(total) doses taken today").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                }
            }
        }
    }
}

private struct MoodTrendCard: View {
    let moods: [MoodEntry]

    private func emoji(_ mood: Mood) -> String {
        switch mood {
        case .great: "😊"
        case .okay: "🙂"
        case .low: "😔"
        }
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mood trend").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                if moods.isEmpty {
                    ChartFootnote(text: "No moods recorded yet.")
                } else {
                    HStack {
                        ForEach(moods) { entry in
                            Text(emoji(entry.mood)).font(.system(size: 24)).frame(maxWidth: .infinity)
                        }
                    }
                    HStack {
                        ForEach(moods) { entry in
                            Text(entry.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
}

private struct ChatsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Chats").font(.system(size: 28, weight: .black))
            LovableCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(state.selectedSummary?.firstName ?? "Your senior") and family").font(.system(size: 19, weight: .black))
                    Text("Messaging features are coming soon. The current focus is on check-ins, alerts, and appointment preparation.")
                        .font(.system(size: 15))
                        .foregroundStyle(CareTheme.secondaryText)
                }
            }
        }
    }
}

private struct PaywallFallbackView: View {
    @Environment(AppState.self) private var state
    let context: PaywallContext

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PlainPill(text: "Plus plan", icon: "sparkles", color: CareTheme.gold, fill: CareTheme.goldPale)
            Text(context == .careInsight ? "Unlock premium care insight" : "Unlock appointment preparation")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
            Text("Plus includes AI Care Insights, AI Appointment Prep, and support for up to five monitored seniors.")
                .font(.system(size: 18))
                .lineSpacing(5)
                .foregroundStyle(CareTheme.secondaryText)
            Spacer()
            Button {
                state.unlockPremiumPreview()
                Task {
                    if context == .careInsight {
                        await state.loadCareInsight()
                    } else {
                        await state.prepareAppointment()
                    }
                }
            } label: {
                Text("Buy with Test Store")
            }
            .buttonStyle(ReferenceButtonStyle(fill: CareTheme.sage, height: 62, radius: 22))
            .accessibilityIdentifier("paywall.buy")
            Button("Not now") { state.paywallContext = nil }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(CareTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .padding(24)
        .background(CareTheme.background)
    }
}

private struct DevMenuView: View {
    @Environment(AppState.self) private var state
    @Environment(LiveModeController.self) private var live
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if let email = live.signedInEmail {
                        LabeledContent("Email", value: email)
                    }
                    if let repo = live.repository {
                        LabeledContent("Family", value: repo.snapshot.account.name)
                        LabeledContent("Invite Code", value: repo.inviteCode)
                            .textSelection(.enabled)
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await live.signOut()
                            dismiss()
                        }
                    }
                }

                Section("Health Data") {
                    Button("Sync Health Data Now") {
                        Task {
                            try? await state.requestHealthPermissions()
                            await state.syncHealthData()
                            dismiss()
                        }
                    }
                    #if DEBUG
                    Button("Seed HealthKit Test Data (Simulator)") {
                        Task {
                            let provider = HealthKitHealthDataProvider()
                            let results = await provider.seedSampleData()
                            for result in results {
                                print("HealthKit seed: \(result)")
                            }
                            state.showToast("Seeded: \(results.joined(separator: ", "))")
                            try? await state.requestHealthPermissions()
                            await state.syncHealthData()
                            dismiss()
                        }
                    }
                    #endif
                }

                Section("Premium") {
                    Button("Unlock Premium AI") {
                        state.unlockPremiumPreview()
                        dismiss()
                    }
                }

                #if DEBUG
                Section("Developer") {
                    LabeledContent("Data Source", value: live.isRealtimeConnected ? "Live · Realtime" : "Live")
                    Button("Refresh Data") {
                        Task {
                            await state.refresh()
                            dismiss()
                        }
                    }
                }
                #endif
            }
            .navigationTitle("CareCompanion")
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(CareTheme.ink, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
    }
}
