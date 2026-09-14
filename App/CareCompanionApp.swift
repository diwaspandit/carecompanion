import SwiftUI
import CareCore

private enum CareRuntime {
    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    static var fastSOS: Bool { ProcessInfo.processInfo.arguments.contains("--fast-sos") }
}

@main
struct CareCompanionApp: App {
    @State private var state: AppState = {
        let repository = DemoCareRepository()
        #if targetEnvironment(simulator) || os(iOS)
        // Enable HealthKit integration for real health data sync
        let healthProvider: (any HealthDataProvider)? = HealthKitHealthDataProvider()
        #else
        let healthProvider: (any HealthDataProvider)? = nil
        #endif
        return AppState(repository: repository, healthProvider: healthProvider)
    }()
    @State private var live = LiveModeController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(live.isLive)
                .environment(live.liveState ?? state)
                .environment(live)
                .preferredColorScheme(.light)
                .onOpenURL { url in Task { await live.handleOpenURL(url) } }
        }
    }
}

private struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDemoMenu = false
    @State private var didApplyUITestReset = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            ZStack(alignment: .bottom) {
                switch state.screen {
                case .onboarding:
                    OnboardingView(showDemoMenu: $showDemoMenu)
                case .seniorHome:
                    SeniorHomeView(showDemoMenu: $showDemoMenu)
                case .familyDashboard:
                    FamilyDashboardView(showDemoMenu: $showDemoMenu)
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
        .tint(CareTheme.sageDark)
        .sheet(isPresented: $showDemoMenu) { DemoMenuView() }
        .sheet(item: $state.paywallContext) { context in
            PaywallFallbackView(context: context)
                .presentationDetents([.medium, .large])
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.screen)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toastMessage)
        .onAppear {
            if CareRuntime.isUITesting, !didApplyUITestReset {
                didApplyUITestReset = true
                Task { await state.resetDemo() }
            }

            // Set up automatic health sync on app launch
            Task {
                await state.setupAutomaticHealthSync()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Sync health data when app becomes active
            if newPhase == .active {
                Task {
                    await state.syncHealthData()
                }
            }
        }
    }
}

private struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @Binding var showDemoMenu: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleIcon(systemName: "heart.text.square", color: CareTheme.sageDark, size: 56, iconSize: 25, fillOpacity: 0.20)
                .padding(.top, 70)
                .padding(.bottom, 32)
                .onLongPressGesture { showDemoMenu = true }

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
    @Binding var showDemoMenu: Bool
    @State private var showSOS = false
    @State private var showHealthPermissions = false

    var body: some View {
        if state.seniorTab == .mood {
            EnhancedMoodView()
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
                            .onLongPressGesture { showDemoMenu = true }
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
                        Text("Good morning,\nMaya")
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
    @State private var showingMedicationManagement = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Medicines")
                            .font(.system(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(CareTheme.ink)
                            .accessibilityIdentifier("senior.medicines.title")
                        Spacer()
                        Button {
                            showingMedicationManagement = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 24))
                                .foregroundStyle(CareTheme.sage)
                        }
                    }
                    .padding(.top, 26)

                    MedicineListView()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            SeniorBottomBar()
        }
        .background(CareTheme.background)
        .sheet(isPresented: $showingMedicationManagement) {
            MedicationManagementView()
        }
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
                            Text("Maya and Diwas").font(.system(size: 19, weight: .black))
                            Text("Messaging is intentionally light for the demo. The care story focuses on check-ins, alerts, and appointment prep.")
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
                state.showDemoToast("Medicine reminder will ring on Maya's phone at 8:00 PM.")
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
            Text("Diwas and Sunita received your\nalert. Someone will call you very\nsoon.")
                .font(.system(size: 23))
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 24)
            Spacer()
            Button {
                state.showDemoToast("Calling Diwas now...")
            } label: {
                Label("Call Diwas now", systemImage: "phone.connection")
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
    @Binding var showDemoMenu: Bool

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch state.familyTab {
                    case .dashboard:
                        FamilyHome(showDemoMenu: $showDemoMenu)
                    case .health:
                        HealthTimelineView()
                    case .appointments:
                        AppointmentsView()
                    case .emergency:
                        AlertsView(showDemoMenu: $showDemoMenu)
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
                    (.emergency, "Alerts", "bell", state.activeDemoAlertCount),
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

private struct FamilyHome: View {
    @Environment(AppState.self) private var state
    @Binding var showDemoMenu: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Family")
                        .font(.system(size: 28, weight: .black))
                        .accessibilityIdentifier("family.title")
                    Text("Good evening, Diwas · Austin, Texas")
                        .font(.system(size: 15))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Text("D")
                    .font(.system(size: 16, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(CareTheme.grayPill, in: Circle())
                    .onLongPressGesture { showDemoMenu = true }
                    .accessibilityIdentifier("family.avatar")
            }

            HStack(spacing: 10) {
                Button {
                    state.showDemoToast("Maya selected.")
                } label: {
                    FamilyChip(initials: "MS", name: "Maya", color: CareTheme.gold, selected: true)
                }
                .buttonStyle(.plain)
                Button {
                    state.showDemoToast("Ramesh is included as sample future multi-senior context.")
                } label: {
                    FamilyChip(initials: "RS", name: "Ramesh", color: CareTheme.sage, selected: true)
                }
                .buttonStyle(.plain)
                Button {
                    state.showDemoToast("Plus supports up to 5 monitored seniors.")
                    state.showPaywall(for: .careInsight)
                } label: {
                    VStack(spacing: 8) {
                        AvatarCircle(text: "+", color: CareTheme.secondaryText, size: 58)
                        Text("Add").font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
            }

            AIInsightReferenceCard()
            SeniorReferenceCard()
            RameshCard()
            Button {
                state.familyTab = .emergency
            } label: {
                HStack(spacing: 16) {
                    Text("\(state.activeDemoAlertCount)")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(CareTheme.coral, in: Circle())
                    Text("Maya missed her evening\nmedication")
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

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CareTheme.gold)
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI insight")
                        .font(.system(size: 15, weight: .black))
                    Text(state.hasPremiumAccess ? (state.careInsight?.summary ?? "Maya checked in and her routine looks mostly steady today. There are a few small changes worth discussing at the next appointment.") : "Maya has been less active than usual this week and slept about 2 hours less than her average. Her resting heart rate is also slightly up. Consider checking in with her today.")
                        .font(.system(size: 16))
                        .lineSpacing(5)
                        .foregroundStyle(CareTheme.mutedText)
                    if state.hasPremiumAccess, let insight = state.careInsight {
                        ForEach(insight.observations.prefix(2), id: \.self) { observation in
                            Label(observation, systemImage: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
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
        .task {
            if state.hasPremiumAccess && state.careInsight == nil {
                await state.loadCareInsight()
            }
        }
    }
}

private struct SeniorReferenceCard: View {
    @Environment(AppState.self) private var state

    private var stepsDisplay: String {
        guard let health = state.latestHealth else { return "2,840" }
        return health.steps.formatted()
    }
    private var sleepDisplay: String {
        guard let health = state.latestHealth else { return "6h 20min" }
        return Self.sleepText(minutes: health.sleepMinutes)
    }
    private var dataSourceNotice: String {
        state.latestHealth?.source == "healthkit"
            ? "Steps and sleep synced from Apple Health."
            : "Steps and sleep are demo data for this preview, not synced from HealthKit."
    }
    private static func sleepText(minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)min"
    }

    var body: some View {
        LovableCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    AvatarCircle(text: "MS", color: CareTheme.gold, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Maya Sharma").font(.system(size: 20, weight: .black))
                        Text("Grandmother ·\nKathmandu, Nepal")
                            .font(.system(size: 13))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                    Spacer()
                    PlainPill(text: "Needs attention", icon: "circle.fill", color: Color(red: 107/255, green: 85/255, blue: 43/255), fill: CareTheme.goldPale)
                }
                HStack {
                    Image(systemName: "clock")
                    Text(state.isCheckedIn ? "Checked in 2 hours ago" : "No check-in yet")
                        .font(.system(size: 15, weight: .black))
                        .accessibilityIdentifier("family.checkedIn")
                    Spacer()
                    Text(state.isCheckedIn ? "🙂" : "😐").font(.system(size: 24))
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(CareTheme.grayPill, in: Capsule())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SmallMetric(title: "Medications", value: "\(state.medicationsTakenCount) of 4 taken", icon: "capsule", color: CareTheme.gold, identifier: "family.medications")
                    SmallMetric(title: "Mood today", value: state.currentMood?.rawValue ?? "Okay", icon: "waveform.path.ecg", color: CareTheme.sage)
                    SmallMetric(title: "Steps", value: stepsDisplay, icon: "shoeprints.fill", color: CareTheme.blue, identifier: "family.steps")
                    SmallMetric(title: "Sleep", value: sleepDisplay, icon: "moon", color: CareTheme.blue, identifier: "family.sleep")
                }
                Text(dataSourceNotice)
                    .font(.system(size: 11))
                    .foregroundStyle(CareTheme.mutedText)
                    .accessibilityIdentifier("family.demoDataNotice")
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
    @State private var showSettings = false
    @State private var showEditProfile = false

    private struct EmergencyContact: Identifiable {
        let id = UUID()
        let name: String
        let relation: String
        let phone: String
    }

    private let contacts: [EmergencyContact] = [
        EmergencyContact(name: "Diwas Sharma", relation: "Son — Austin, Texas", phone: "+1 512 555 0142"),
        EmergencyContact(name: "Sunita Sharma", relation: "Daughter — Pokhara", phone: "+977 98 4100 2233"),
        EmergencyContact(name: "Dr. Anil Rana", relation: "Cardiologist — Norvic Hospital", phone: "+977 1 4258 554")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Senior Profile")
                        .font(.system(size: 28, weight: .black))
                        .accessibilityIdentifier("profile.title")
                    Text("Settings & care plan")
                        .font(.system(size: 15))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 24))
                        .foregroundStyle(CareTheme.sage)
                }
                .accessibilityIdentifier("profile.settings")
            }

            LovableCard {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        AvatarCircle(text: "MS", color: CareTheme.gold, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Maya Sharma").font(.system(size: 20, weight: .black))
                            Text("74 years · Grandmother").font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            Text("Kathmandu, Nepal").font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                        }
                        Spacer()
                    }
                    Button {
                        showEditProfile = true
                    } label: {
                        Label("Edit Profile", systemImage: "pencil")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CareTheme.sageDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(CareTheme.sagePale, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.edit")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Emergency contacts").font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                LovableCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(contacts.enumerated()), id: \.element.id) { index, contact in
                            HStack(spacing: 14) {
                                CircleIcon(systemName: "phone.fill", color: CareTheme.coral, size: 40, iconSize: 16, fillOpacity: 0.16)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).font(.system(size: 16, weight: .black))
                                    Text(contact.relation).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                                }
                                Spacer()
                                Text(contact.phone).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                            }
                            .padding(.vertical, 10)
                            if index < contacts.count - 1 {
                                Divider()
                            }
                        }
                        Button {
                            state.showDemoToast("Adding a contact will open a form in a future build.")
                        } label: {
                            Label("Add contact", systemImage: "plus")
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
                Text("Demo data for this preview, not synced from HealthKit.")
                    .font(.system(size: 12))
                    .foregroundStyle(CareTheme.mutedText)
                    .accessibilityIdentifier("profile.demoDataNotice")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SmallMetric(title: "Resting heart rate", value: "69 bpm", icon: "heart", color: CareTheme.coral)
                    SmallMetric(title: "Average sleep", value: "7h 15min", icon: "moon", color: CareTheme.blue)
                    SmallMetric(title: "Daily steps", value: "4,100", icon: "shoeprints.fill", color: CareTheme.blue)
                    SmallMetric(title: "Check-in time", value: "around 8:00 AM", icon: "clock", color: CareTheme.gold)
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showEditProfile) {
            EditSeniorProfileView()
        }
    }
}

private struct RameshCard: View {
    var body: some View {
        LovableCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    AvatarCircle(text: "RS", color: CareTheme.sage, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ramesh Sharma").font(.system(size: 19, weight: .black))
                        Text("Father · Kathmandu, Nepal").font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                    }
                    Spacer()
                    PlainPill(text: "All good", icon: "circle.fill", color: CareTheme.sageDark, fill: CareTheme.sagePale)
                }
                HStack {
                    Image(systemName: "clock")
                    Text("Checked in 20 minutes ago").font(.system(size: 15, weight: .black))
                    Spacer()
                    Text("😊").font(.system(size: 24))
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(CareTheme.grayPill, in: Capsule())
                HStack(spacing: 12) {
                    SmallMetric(title: "Medications", value: "2 of 2 taken", icon: "capsule", color: CareTheme.sage)
                    SmallMetric(title: "Steps", value: "6,120", icon: "shoeprints.fill", color: CareTheme.blue)
                }
            }
        }
    }
}

private struct AppointmentsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Appointments").font(.system(size: 28, weight: .black))
                    Text("September 2026 · Maya Sharma").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Button {
                    state.showDemoToast("Appointment creation is available after the hackathon demo.")
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(CareTheme.sage, in: Capsule())
                }
            }
            CalendarCard()
            Text("Upcoming")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(CareTheme.secondaryText)
            AppointmentRow(day: "FRI\n4", title: "Dr. Rana - Heart check-up", time: "10:30 AM · Norvic Hospital, Thapathali", note: "Bring the blood pressure diary.")
            AppointmentRow(day: "MON\n7", title: "Physiotherapy session", time: "4:00 PM · Home visit", note: "Knee mobility exercises.")
            AppointmentRow(day: "THU\n17", title: "Eye clinic - annual screening", time: "9:15 AM · Tilganga Institute", note: "Routine yearly check.")

            if state.hasPremiumAccess, let prep = state.appointmentPrep {
                AppointmentPrepCard(prep: prep)
            } else {
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
    private let days = Array(1...30)
    private let marked: Set<Int> = [4, 7, 17]

    var body: some View {
        LovableCard {
            VStack(spacing: 14) {
                HStack {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { day in
                        Text(day).font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 14) {
                    ForEach(days, id: \.self) { day in
                        Text("\(day)")
                            .font(.system(size: 15, weight: day == 2 ? .black : .regular))
                            .foregroundStyle(day == 2 ? .white : CareTheme.mutedText)
                            .frame(width: 34, height: 34)
                            .background(day == 2 ? CareTheme.ink : (marked.contains(day) ? CareTheme.sagePale : Color.clear), in: Circle())
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
    @Binding var showDemoMenu: Bool
    @State private var dismissedAlerts: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Alert Center").font(.system(size: 28, weight: .black))
                .onLongPressGesture { showDemoMenu = true }
                .accessibilityIdentifier("alerts.title")
            Text("\(visibleAlertCount) recent alerts · newest first").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
            if state.hasEmergency && !dismissedAlerts.contains("emergency-active") {
                AlertRow(kind: "EMERGENCY", title: "SOS alert from Maya", detail: "Maya triggered SOS just now. Core safety is available on every plan.", color: CareTheme.coral, fill: CareTheme.coralPale, icon: "exclamationmark.triangle") {
                    state.showDemoToast("Calling Maya now...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    Task {
                        await state.acknowledgeEmergency()
                        dismissedAlerts.insert("emergency-active")
                    }
                }
                .accessibilityIdentifier("alerts.sos")
            }
            if !dismissedAlerts.contains("medication") && state.medicationsTakenCount < 4 {
                AlertRow(kind: "MEDICATION", title: "Maya missed her evening medication", detail: "Atorvastatin 10 mg was due at 8:00 PM - 1 hour ago.", color: CareTheme.gold, fill: .white, icon: "capsule") {
                    state.showDemoToast("Calling Maya about Atorvastatin...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert("medication")
                    state.showDemoToast("Medication alert dismissed for the demo.")
                }
            }
            if !dismissedAlerts.contains("health") {
                AlertRow(kind: "HEALTH", title: "Activity below baseline", detail: "2,840 steps today vs. a 4,100 step average.", color: CareTheme.blue, fill: CareTheme.bluePale, icon: "waveform.path.ecg") {
                    state.showDemoToast("Calling Maya to check in...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert("health")
                }
            }
            if !dismissedAlerts.contains("checkin") && !state.isCheckedIn {
                AlertRow(kind: "CHECK-IN", title: "Late daily check-in", detail: "Maya has not checked in at her usual time.", color: CareTheme.gold, fill: CareTheme.grayPill.opacity(0.45), icon: "clock") {
                    state.showDemoToast("Calling Maya about check-in...")
                } onMessage: {
                    state.familyTab = .chats
                } onDismiss: {
                    dismissedAlerts.insert("checkin")
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

    private var visibleAlertCount: Int {
        var count = 0
        if state.hasEmergency && !dismissedAlerts.contains("emergency-active") { count += 1 }
        if state.medicationsTakenCount < 4 && !dismissedAlerts.contains("medication") { count += 1 }
        if !dismissedAlerts.contains("health") { count += 1 }
        if !state.isCheckedIn && !dismissedAlerts.contains("checkin") { count += 1 }
        return count
    }
}

private struct AlertRow: View {
    let kind: String
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
                    Text("\(kind) · 1 hour ago")
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

private struct HealthTimelineView: View {
    @Environment(AppState.self) private var state

    private var dataSourceNotice: String {
        state.latestHealth?.source == "healthkit"
            ? "Synced from Apple Health."
            : "Demo data for this preview, not synced from HealthKit."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Health Timeline").font(.system(size: 28, weight: .black))
            Text("Maya Sharma · last 7 days").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
            Text(dataSourceNotice)
                .font(.system(size: 12))
                .foregroundStyle(CareTheme.mutedText)
                .accessibilityIdentifier("timeline.demoDataNotice")
            AIInsightReferenceCard()
            SleepChartCard(latestHealth: state.latestHealth)
            StepsChartCard(latestHealth: state.latestHealth)
            HeartChartCard(latestHealth: state.latestHealth)
            AdherenceCard()
            MoodTrendCard()
        }
    }
}

private struct SleepChartCard: View {
    let latestHealth: HealthSnapshot?
    let values: [CGFloat] = [7.4, 7.1, 6.8, 7.2, 6.1, 5.9, 6.3]

    private var sleepDisplay: String {
        guard let health = latestHealth else { return "6h 20min" }
        return "\(health.sleepMinutes / 60)h \(health.sleepMinutes % 60)min"
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Sleep", systemImage: "moon").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Spacer()
                    Text("\(sleepDisplay) last night").font(.system(size: 15, weight: .black))
                }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(CareTheme.sage.opacity(0.82))
                            .frame(height: 28 + value * 12)
                    }
                }
                .frame(height: 120, alignment: .bottom)
                HStack {
                    ForEach(["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"], id: \.self) { day in
                        Text(day).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                    }
                }
                Text("Weekly average 6.7h").font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
            }
        }
    }
}

private struct StepsChartCard: View {
    let latestHealth: HealthSnapshot?

    private var stepsDisplay: String {
        guard let health = latestHealth else { return "2,840" }
        return health.steps.formatted()
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Steps", systemImage: "shoeprints.fill").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Spacer()
                    Text("\(stepsDisplay) today").font(.system(size: 15, weight: .black))
                }
                MiniLineChart(color: CareTheme.sage)
                    .frame(height: 140)
            }
        }
    }
}

private struct HeartChartCard: View {
    let latestHealth: HealthSnapshot?

    private var heartRateDisplay: String {
        guard let health = latestHealth else { return "72 bpm" }
        return "\(health.restingHeartRate) bpm"
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Resting heart rate", systemImage: "heart").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Spacer()
                    Text(heartRateDisplay).font(.system(size: 15, weight: .black))
                }
                MiniLineChart(color: CareTheme.coral)
                    .frame(height: 140)
                Text("Range 67 bpm - 74 bpm").font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
            }
        }
    }
}

private struct MiniLineChart: View {
    let color: Color
    private let points: [CGFloat] = [0.58, 0.54, 0.68, 0.43, 0.32, 0.18, 0.22]

    var body: some View {
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
    var body: some View {
        LovableCard {
            HStack(spacing: 22) {
                Circle()
                    .trim(from: 0, to: 0.92)
                    .stroke(CareTheme.sage, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-90))
                    .background(Circle().stroke(CareTheme.sage.opacity(0.18), lineWidth: 9))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Medication adherence").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Text("92%").font(.system(size: 30, weight: .black))
                    Text("22 of 24 doses this week").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                }
            }
        }
    }
}

private struct MoodTrendCard: View {
    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mood trend").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                HStack {
                    ForEach(Array(["😊", "😊", "😊", "😐", "😐", "😔", "😐"].enumerated()), id: \.offset) { _, emoji in
                        Text(emoji).font(.system(size: 24)).frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    ForEach(["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"], id: \.self) { day in
                        Text(day).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

private struct ChatsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Chats").font(.system(size: 28, weight: .black))
            LovableCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Maya and Diwas").font(.system(size: 19, weight: .black))
                    Text("Messaging is intentionally light for the demo. The care story focuses on check-ins, alerts, and appointment prep.")
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

private struct DemoMenuView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Demo scenarios") {
                    ForEach(DemoScenario.allCases, id: \.self) { scenario in
                        Button(scenario.rawValue) {
                            Task {
                                await DemoScenarioController(state: state).apply(scenario)
                                dismiss()
                            }
                        }
                    }
                }
                Section("Controls") {
                    Button("Reset complete demo") {
                        Task {
                            await state.resetDemo()
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("demo.reset")
                    Button("Unlock premium preview") {
                        state.unlockPremiumPreview()
                        dismiss()
                    }
                }
                #if DEBUG
                Section("Developer") {
                    NavigationLink("Live Supabase") { LiveModeView() }
                        .accessibilityIdentifier("demo.liveSupabase")
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
/// Enhanced mood recording with optional notes
struct EnhancedMoodView: View {
    @Environment(AppState.self) private var state
    @State private var selectedMood: Mood?
    @State private var note = ""
    @FocusState private var noteFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 100)

            Text("How are you feeling\ntoday?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .lineSpacing(1)
                .foregroundStyle(CareTheme.ink)

            Text("Tap one face, add a note if you like.")
                .font(.system(size: 18))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 18)
                .padding(.bottom, 32)

            VStack(spacing: 16) {
                moodButton("😊", title: "Great", mood: .great)
                moodButton("😐", title: "Okay", mood: .okay)
                moodButton("😔", title: "Not great", mood: .low)
            }

            if selectedMood != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add a note (optional)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CareTheme.secondaryText)

                    TextField("How are things going?", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                        .focused($noteFieldFocused)

                    Button {
                        Task {
                            await state.recordMood(selectedMood!, note: note.isEmpty ? nil : note)
                            state.switchToFamily()
                        }
                    } label: {
                        Text("Save Mood")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(CareTheme.sage, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .background(CareTheme.background)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedMood)
    }

    private func moodButton(_ emoji: String, title: String, mood: Mood) -> some View {
        Button {
            if selectedMood == mood {
                // If already selected and no note, record immediately
                if note.isEmpty {
                    Task {
                        await state.recordMood(mood)
                        state.switchToFamily()
                    }
                }
            } else {
                selectedMood = mood
                noteFieldFocused = true
            }
        } label: {
            HStack(spacing: 26) {
                Text(emoji).font(.system(size: 42))
                Text(title).font(.system(size: 28, weight: .black))
                Spacer()
                if selectedMood == mood {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(CareTheme.sage)
                }
            }
            .padding(.horizontal, 30)
            .frame(height: 100)
            .background(selectedMood == mood ? CareTheme.sagePale : .white,
                       in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(selectedMood == mood ? CareTheme.sage : CareTheme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Family view of mood history with notes
struct MoodHistoryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private var moodEntries: [MoodEntry] {
        state.snapshot.moods
            .filter { $0.seniorID == state.selectedSeniorID }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                if moodEntries.isEmpty {
                    ContentUnavailableView(
                        "No Mood Entries",
                        systemImage: "face.smiling",
                        description: Text("Mood entries will appear here")
                    )
                } else {
                    ForEach(moodEntries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entry.mood.rawValue)
                                    .font(.system(size: 17, weight: .bold))
                                Spacer()
                                Text(entry.date, style: .date)
                                    .font(.system(size: 14))
                                    .foregroundStyle(CareTheme.secondaryText)
                            }

                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 15))
                                    .foregroundStyle(CareTheme.secondaryText)
                                    .padding(.top, 4)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Mood History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
/// Full medication CRUD with add, edit, delete, and adherence tracking
struct MedicationManagementView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddMedication = false
    @State private var editingMedication: Medication?

    private var medications: [Medication] {
        state.snapshot.medications.filter { $0.seniorID == state.selectedSeniorID }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if medications.isEmpty {
                        ContentUnavailableView(
                            "No Medications",
                            systemImage: "capsule",
                            description: Text("Add medications to track daily adherence")
                        )
                    } else {
                        ForEach(medications) { medication in
                            MedicationRowView(medication: medication, onEdit: {
                                editingMedication = medication
                            })
                        }
                    }
                }

                Section {
                    Button {
                        showingAddMedication = true
                    } label: {
                        Label("Add Medication", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddMedication) {
                AddMedicationView()
            }
            .sheet(item: $editingMedication) { medication in
                EditMedicationView(medication: medication)
            }
        }
    }
}

private struct MedicationRowView: View {
    @Environment(AppState.self) private var state
    let medication: Medication
    let onEdit: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack {
            Button {
                Task { await state.toggleMedication(id: medication.id) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: medication.taken ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(medication.taken ? CareTheme.sage : CareTheme.secondaryText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(medication.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CareTheme.ink)
                        Text(medication.scheduledTime)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(CareTheme.secondaryText)
            }
        }
        .confirmationDialog("Delete Medication", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                Task { await state.deleteMedication(id: medication.id) }
            }
        } message: {
            Text("Are you sure you want to delete \(medication.name)?")
        }
    }
}

private struct AddMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var scheduledTime = "8:00 AM"

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name", text: $name)
                    TextField("Scheduled Time", text: $scheduledTime)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Add Medication") {
                        Task {
                            await state.addMedication(name: name, scheduledTime: scheduledTime)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || scheduledTime.isEmpty)
                }
            }
            .navigationTitle("Add Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct EditMedicationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    let medication: Medication
    @State private var name = ""
    @State private var scheduledTime = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Medication Details") {
                    TextField("Name", text: $name)
                    TextField("Scheduled Time", text: $scheduledTime)
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button("Save Changes") {
                        Task {
                            await state.updateMedication(id: medication.id, name: name, scheduledTime: scheduledTime)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || scheduledTime.isEmpty)
                }
            }
            .navigationTitle("Edit Medication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                name = medication.name
                scheduledTime = medication.scheduledTime
            }
        }
    }
}
/// App settings: sign out, demo reset, privacy controls, about
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(LiveModeController.self) private var live
    @Environment(\.dismiss) private var dismiss
    @State private var showingResetConfirmation = false
    @State private var showingSignOutConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                // Account Section (if signed in)
                if live.isSignedIn {
                    Section("Account") {
                        if let email = live.signedInEmail {
                            LabeledContent("Email", value: email)
                        }

                        if live.hasAccount, let account = state.snapshot.account.name as String? {
                            LabeledContent("Family", value: account)
                        }

                        if live.isLive, let repo = live.repository {
                            LabeledContent("Invite Code", value: repo.inviteCode)
                                .textSelection(.enabled)
                        }

                        Button(role: .destructive) {
                            showingSignOutConfirmation = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }

                // Demo Section
                Section("Demo") {
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Demo", systemImage: "arrow.counterclockwise")
                    }
                }

                // Privacy Section
                Section("Privacy") {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy & Data", systemImage: "hand.raised")
                    }
                }

                // About Section
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                    Link(destination: URL(string: "https://carecompanion.example.com")!) {
                        Label("Website", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset Demo", isPresented: $showingResetConfirmation) {
                Button("Reset", role: .destructive) {
                    Task { await state.resetDemo() }
                }
            } message: {
                Text("This will reset all demo data to the initial state.")
            }
            .confirmationDialog("Sign Out", isPresented: $showingSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    Task { await live.signOut() }
                }
            } message: {
                Text("You'll need to sign in again to access your care data.")
            }
        }
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Text("CareCompanion processes health and care data locally on your device. Data is synced securely to your family account when you're signed in.")
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }

            Section("Data Collection") {
                LabeledContent("Health Data", value: "With Permission")
                LabeledContent("Location", value: "Never")
                LabeledContent("Analytics", value: "None")
            }

            Section("Your Rights") {
                Button("Delete My Data") {
                    // Placeholder for data deletion
                }
                Button("Export My Data") {
                    // Placeholder for data export
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
/// Edit senior profile details
struct EditSeniorProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var name = ""
    @State private var age = 65
    @State private var city = ""
    @State private var timeZone = "UTC"

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    TextField("Name", text: $name)
                    Stepper("Age: \(age)", value: $age, in: 1...130)
                    TextField("City", text: $city)
                }

                Section("Location") {
                    Picker("Time Zone", selection: $timeZone) {
                        Text("Asia/Kathmandu").tag("Asia/Kathmandu")
                        Text("America/Chicago").tag("America/Chicago")
                        Text("America/New_York").tag("America/New_York")
                        Text("America/Los_Angeles").tag("America/Los_Angeles")
                        Text("Europe/London").tag("Europe/London")
                        Text("UTC").tag("UTC")
                    }
                }

                Section {
                    Button("Save Changes") {
                        Task {
                            await state.updateSeniorProfile(
                                name: name,
                                age: age,
                                city: city,
                                timeZone: timeZone
                            )
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty || city.isEmpty)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let senior = state.selectedSenior {
                    name = senior.name
                    age = senior.age
                    city = senior.city
                    timeZone = senior.timeZoneIdentifier
                }
            }
        }
    }
}

/// Emergency contacts management
struct EmergencyContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingAddContact = false

    // Demo contacts (in production, these would come from the repository)
    struct EmergencyContact: Identifiable {
        let id = UUID()
        var name: String
        var relation: String
        var phone: String
    }

    @State private var contacts: [EmergencyContact] = [
        EmergencyContact(name: "Diwas Sharma", relation: "Son", phone: "+1 512 555 0142"),
        EmergencyContact(name: "Sunita Sharma", relation: "Daughter", phone: "+977 98 4100 2233")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.name)
                            .font(.system(size: 17, weight: .semibold))
                        Text(contact.relation)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                        Text(contact.phone)
                            .font(.system(size: 14))
                            .foregroundStyle(CareTheme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    contacts.remove(atOffsets: indexSet)
                }
            }
            .navigationTitle("Emergency Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddContact = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddContact) {
                AddEmergencyContactView { contact in
                    contacts.append(contact)
                }
            }
        }
    }
}

private struct AddEmergencyContactView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (EmergencyContactsView.EmergencyContact) -> Void

    @State private var name = ""
    @State private var relation = ""
    @State private var phone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Details") {
                    TextField("Name", text: $name)
                    TextField("Relation", text: $relation)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }

                Section {
                    Button("Add Contact") {
                        onAdd(EmergencyContactsView.EmergencyContact(
                            name: name,
                            relation: relation,
                            phone: phone
                        ))
                        dismiss()
                    }
                    .disabled(name.isEmpty || relation.isEmpty || phone.isEmpty)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
