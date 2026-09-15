import CareCore
import SwiftUI

/// The senior's own experience: large controls, one thing per screen.
struct SeniorRootView: View {
    @Environment(AppState.self) private var state
    @State private var showSOS = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch state.seniorTab {
                case .home: SeniorHomeScreen(showSOS: $showSOS, showSettings: $showSettings)
                case .mood: EnhancedMoodView()
                case .medicines: SeniorMedicinesScreen()
                case .visits: SeniorVisitsScreen()
                case .messages: MessagesScreen(large: true)
                }
            }
            .frame(maxHeight: .infinity)
            if state.seniorTab != .mood {
                SeniorBottomBar()
            }
        }
        .background(CareTheme.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showSOS) {
            SOSFlowView(isPresented: $showSOS).environment(state)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(state)
        }
    }
}

private struct SeniorHomeScreen: View {
    @Environment(AppState.self) private var state
    @Binding var showSOS: Bool
    @Binding var showSettings: Bool

    private var zone: TimeZone { state.selectedTimeZone }
    private var greeting: String {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    Text("CareCompanion")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(CareTheme.ink)
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CareTheme.mutedText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("senior.settings")
                    Button { showSOS = true } label: {
                        Label("SOS", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(CareTheme.coral, in: Capsule())
                    }
                    .accessibilityLabel("SOS, alert your family")
                    .accessibilityIdentifier("senior.sos")
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(greeting),\n\(state.selectedSummary?.firstName ?? "")")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(CareTheme.ink)
                    Text(Date().formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).day().month(.wide)))
                        .font(.system(size: 22))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                .accessibilityElement(children: .combine)

                CheckInButton()
                MoodPromptCard()
                MedicineListView()
                SeniorNextVisitCard()
                SeniorHealthCard()
                SeniorPeopleCard()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await state.refresh() }
    }
}

private struct CheckInButton: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let checkedInAt = state.selectedSummary?.checkInDate
        Button {
            Task { await state.checkIn() }
        } label: {
            VStack(spacing: 18) {
                CircleIcon(systemName: checkedInAt == nil ? "heart" : "checkmark", color: .white, size: 82, iconSize: 42, fillOpacity: 0.24)
                Text("I'm okay")
                    .font(.system(size: 34, weight: .black))
                Text(checkedInAt.map { "Shared with your family at \(timeText($0, in: state.selectedTimeZone))" } ?? "Tap to tell your family")
                    .font(.system(size: 19))
                    .opacity(0.92)
            }
        }
        .buttonStyle(ReferenceButtonStyle(fill: checkedInAt == nil ? CareTheme.sage : CareTheme.sageDark, height: 250))
        .disabled(checkedInAt != nil)
        .accessibilityLabel(checkedInAt == nil ? "I'm okay. Tap to tell your family" : "Checked in today")
        .accessibilityIdentifier("senior.checkIn")
    }
}

private struct MoodPromptCard: View {
    @Environment(AppState.self) private var state

    private func emoji(_ mood: Mood?) -> String {
        switch mood {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        case nil: "🙂"
        }
    }

    var body: some View {
        let summary = state.selectedSummary
        let recordedToday = summary?.moodHistory.last.map { Calendar.current.isDateInToday($0.date) } ?? false
        Button { state.seniorTab = .mood } label: {
            HStack(spacing: 18) {
                Text(emoji(recordedToday ? summary?.mood : nil)).font(.system(size: 42))
                VStack(alignment: .leading, spacing: 4) {
                    Text(recordedToday ? "Feeling \(summary?.mood?.rawValue.lowercased() ?? "")" : "How are you feeling?")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(CareTheme.ink)
                    Text(recordedToday ? "Tap to update" : "Share your mood with your family")
                        .font(.system(size: 17))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
            }
            .padding(22)
            .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(CareTheme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("senior.mood")
    }
}

private struct SeniorNextVisitCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next visit")
                .font(.system(size: 25, weight: .black))
                .foregroundStyle(CareTheme.ink)
            Button { state.seniorTab = .visits } label: {
                LovableCard {
                    HStack(alignment: .top, spacing: 16) {
                        CircleIcon(systemName: "calendar", color: CareTheme.blue, size: 48, iconSize: 22, fillOpacity: 0.18)
                        if let visit = state.nextAppointment {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(visit.date.formatted(Date.FormatStyle(timeZone: state.selectedTimeZone).weekday(.abbreviated).day().month(.abbreviated)))
                                    .font(.system(size: 22, weight: .black))
                                Text(visit.clinician.isEmpty ? visit.title : "\(visit.title) · \(visit.clinician)")
                                    .font(.system(size: 20, weight: .bold))
                                Text([timeText(visit.date, in: state.selectedTimeZone), visit.location].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 18))
                                    .foregroundStyle(CareTheme.secondaryText)
                            }
                        } else {
                            Text("No upcoming visits")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(CareTheme.ink)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SeniorHealthCard: View {
    @Environment(AppState.self) private var state
    @State private var showPermissions = false

    var body: some View {
        let latest = state.latestHealth
        Button { showPermissions = true } label: {
            LovableCard {
                HStack(spacing: 16) {
                    CircleIcon(systemName: "heart.text.square.fill", color: CareTheme.coral, size: 48, iconSize: 22, fillOpacity: 0.16)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apple Health").font(.system(size: 20, weight: .black)).foregroundStyle(CareTheme.ink)
                        if let latest, latest.source == "healthkit" {
                            Text([latest.steps > 0 ? "\(latest.steps.formatted()) steps" : nil,
                                  latest.sleepMinutes > 0 ? "\(SeniorCareSummary.duration(minutes: latest.sleepMinutes)) sleep" : nil]
                                    .compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 17))
                                .foregroundStyle(CareTheme.mutedText)
                            if let synced = state.healthSyncStatus.lastSyncDate {
                                Text("Shared \(synced.formatted(.relative(presentation: .named)))")
                                    .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            }
                        } else {
                            Text("Share steps, sleep and heart rate with your family")
                                .font(.system(size: 17))
                                .foregroundStyle(CareTheme.mutedText)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).foregroundStyle(CareTheme.secondaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("senior.health")
        .sheet(isPresented: $showPermissions) {
            HealthPermissionsView().environment(state)
        }
    }
}

private struct SeniorPeopleCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let family = state.snapshot.members.filter { $0.profileID != state.currentProfileID && !$0.phone.isEmpty }
        let contacts = state.selectedSummary?.contacts ?? []
        if !family.isEmpty || !contacts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your people")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(CareTheme.ink)
                LovableCard {
                    VStack(spacing: 4) {
                        ForEach(family) { member in
                            ContactRow(name: member.name.isEmpty ? "Family member" : member.name,
                                       detail: member.city.isEmpty ? "Family" : "Family · \(member.city)", phone: member.phone)
                        }
                        ForEach(contacts) { contact in
                            ContactRow(name: contact.name, detail: contact.relation.isEmpty ? "Emergency contact" : contact.relation,
                                       phone: contact.phone)
                        }
                    }
                }
            }
        }
    }
}

private struct SeniorMedicinesScreen: View {
    @Environment(AppState.self) private var state
    @State private var showManage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Medicines")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(CareTheme.ink)
                    Spacer()
                    Button("Edit") { showManage = true }
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityIdentifier("senior.medicines.manage")
                }
                .padding(.top, 26)
                MedicineListView(title: "Tap each one when you take it")
                if let adherence = state.selectedSummary?.adherence, adherence.expected > 0 {
                    LovableCard(fill: CareTheme.sagePale, stroke: CareTheme.sage.opacity(0.3)) {
                        Text("This week: \(adherence.taken) of \(adherence.expected) doses taken")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(CareTheme.sageDark)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await state.refresh() }
        .sheet(isPresented: $showManage) { MedicationManagementView().environment(state) }
    }
}

private struct SeniorVisitsScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Visits")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CareTheme.ink)
                    .padding(.top, 26)
                AppointmentListSection(large: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .refreshable { await state.refresh() }
    }
}

private struct SeniorBottomBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            SeniorBarButton(title: "Home", icon: "house", active: state.seniorTab == .home) { state.seniorTab = .home }
            SeniorBarButton(title: "Medicines", icon: "pills", active: state.seniorTab == .medicines) { state.seniorTab = .medicines }
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
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("senior.tab.\(title.lowercased())")
    }
}

struct SOSFlowView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @Binding var isPresented: Bool
    @State private var seconds = ProcessInfo.processInfo.arguments.contains("--fast-sos") ? 1 : 5
    @State private var sent = false
    @State private var failed = false

    private struct Person: Identifiable {
        let id: String
        let name: String
        let phone: String
    }

    private var people: [Person] {
        let family = state.snapshot.members
            .filter { $0.profileID != state.currentProfileID && PhoneLinks.call($0.phone) != nil }
            .map { Person(id: $0.id, name: $0.name.isEmpty ? "Family member" : $0.name, phone: $0.phone) }
        let contacts = (state.selectedSummary?.contacts ?? []).map { Person(id: $0.id, name: $0.name, phone: $0.phone) }
        return family + contacts
    }

    var body: some View {
        ZStack {
            (sent ? CareTheme.sage : CareTheme.coral).ignoresSafeArea()
            if sent { sentBody } else { countdownBody }
        }
        .task {
            while seconds > 0 && !sent {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                seconds -= 1
            }
            await state.triggerSOS()
            failed = !state.hasEmergency
            sent = true
        }
    }

    private var countdownBody: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 90)
            CircleIcon(systemName: "exclamationmark.triangle", color: .white, size: 110, iconSize: 52, fillOpacity: 0.24)
            Text("Sending alert to your\nfamily…")
                .font(.system(size: 34, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.top, 34)
            Text("\(seconds)")
                .font(.system(size: 92, weight: .black))
                .foregroundStyle(.white)
                .padding(.top, 40)
                .accessibilityLabel("Sending in \(seconds) seconds")
                .accessibilityIdentifier("sos.countdown")
            Spacer()
            Button { isPresented = false } label: {
                Text("Cancel")
                    .font(.system(size: 25, weight: .black))
                    .foregroundStyle(CareTheme.coralDark)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .accessibilityIdentifier("sos.cancel")
        }
    }

    private var sentBody: some View {
        ScrollView {
            VStack(spacing: 18) {
                CircleIcon(systemName: failed ? "wifi.exclamationmark" : "checkmark", color: .white, size: 104, iconSize: 50, fillOpacity: 0.24)
                    .padding(.top, 60)
                Text(failed ? "Couldn't reach the internet" : "Your family has been\nalerted")
                    .font(.system(size: 32, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("sos.notified.title")
                Text(failed ? "Call someone directly below." : "Everyone in \(state.snapshot.account.name) can see your alert. You can also call them now.")
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                ForEach(people) { person in
                    Button {
                        if let url = PhoneLinks.call(person.phone) { openURL(url) }
                    } label: {
                        Label("Call \(person.name)", systemImage: "phone.fill")
                            .font(.system(size: 23, weight: .black))
                            .foregroundStyle(CareTheme.sageDark)
                            .frame(maxWidth: .infinity, minHeight: 76)
                            .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isPresented = false
                    state.seniorTab = .home
                } label: {
                    Text("Back to home")
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.45), lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sos.backHome")
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }
}
