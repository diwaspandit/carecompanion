import CareCore
import SwiftUI

/// The senior's own experience: large controls, one thing per screen.
struct SeniorRootView: View {
    @Environment(AppState.self) private var state
    @State private var showSOS = false
    @State private var showSettings = false
    @State private var moodPrompt = MoodPromptAlert.shared

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
        .overlay {
            if moodPrompt.isShowing {
                MoodCheckCover()
            }
        }
        .onChange(of: state.snapshot) { _, _ in
            Task { await MedicationReminderCenter.shared.sync(from: state) }
        }
    }
}

/// Mood check with no way out except choosing one. Answering here clears the phone and the watch.
private struct MoodCheckCover: View {
    @Environment(AppState.self) private var state
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 16) {
            Text("How are you?")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(CareTheme.ink)
            Text("Choose one to tell your family.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CareTheme.secondaryText)
            moodChoice("😊", "Good", .great)
            moodChoice("😐", "Okay", .okay)
            moodChoice("😔", "Not great", .low)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareTheme.background.ignoresSafeArea())
    }

    private func moodChoice(_ emoji: String, _ title: String, _ mood: Mood) -> some View {
        Button {
            guard !isSaving else { return }
            Task {
                isSaving = true
                _ = await state.recordMood(mood)
                isSaving = false
            }
        } label: {
            HStack(spacing: 16) {
                Text(emoji).font(.system(size: 36))
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(CareTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CareTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel(title)
        .accessibilityIdentifier("mood.prompt.\(mood.rawValue.lowercased())")
    }
}

private struct SeniorHomeScreen: View {
    @Environment(AppState.self) private var state
    @Binding var showSOS: Bool
    @Binding var showSettings: Bool
    @State private var isSavingMood = false

    private var zone: TimeZone { state.selectedTimeZone }
    private var greeting: String {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
    }
    private var medicineEmptyTitle: String {
        if state.medications.isEmpty { return "No medicines" }
        let due = state.medications.filter { CareSchedule.medicationIsDue($0, on: Date(), timeZone: zone) }
        return due.isEmpty ? "No medicines today" : "All medicines taken"
    }

    private var nextMedicine: Medication? {
        MedicationTime.sorted(state.medications.filter { medication in
            !medication.taken && CareSchedule.medicationIsDue(medication, on: Date(), timeZone: zone)
        }).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(greeting)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CareTheme.secondaryText)
                        .lineLimit(1)
                    Text(state.selectedSummary?.firstName ?? "")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(CareTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CareTheme.mutedText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("senior.settings")
                Button { showSOS = true } label: {
                    Label("SOS", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(CareTheme.danger, in: Capsule())
                }
                .accessibilityLabel("SOS, alert your family")
                .accessibilityIdentifier("senior.sos")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How are you?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CareTheme.ink)
                HStack(spacing: 8) {
                    moodButton("😊", "Good", mood: .great)
                    moodButton("😐", "Okay", mood: .okay)
                    moodButton("😔", "Not great", mood: .low)
                }
            }
            .accessibilityIdentifier("senior.mood")

            medicineCard
            visitCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityIdentifier("senior.checkIn")
    }

    private func moodButton(_ emoji: String, _ title: String, mood: Mood) -> some View {
        let selected = state.currentMood == mood
        return Button {
            guard !isSavingMood else { return }
            Task {
                isSavingMood = true
                await state.recordMood(mood)
                isSavingMood = false
            }
        } label: {
            VStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 34))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CareTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(selected ? CareTheme.sagePale : CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? CareTheme.sage : CareTheme.hairline, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSavingMood)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("senior.mood.\(mood.rawValue.lowercased())")
    }

    private var medicineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Medicine")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CareTheme.secondaryText)
            if let medicine = nextMedicine {
                Text(medicine.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CareTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text([medicine.scheduledTime, medicine.dosage].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CareTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    Button {
                        Task { await state.markMedicationTaken(id: medicine.id) }
                    } label: {
                        Text("Taken")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(CareTheme.action, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("senior.home.taken")
                    Button { state.seniorTab = .medicines } label: {
                        Text("All")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CareTheme.ink)
                            .frame(minWidth: 64, minHeight: 44)
                            .background(CareTheme.grayPill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("All medicines")
                }
            } else {
                Text(medicineEmptyTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CareTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .padding(.vertical, 4)
                Button { state.seniorTab = .medicines } label: {
                    Text("See medicines")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CareTheme.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(CareTheme.grayPill, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CareTheme.hairline, lineWidth: 1)
        }
    }

    private var visitCard: some View {
        Button { state.seniorTab = .visits } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Visit")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CareTheme.secondaryText)
                if let visit = state.nextAppointment {
                    Text(visit.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(CareTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(visit.clinician)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CareTheme.secondaryText)
                        .lineLimit(1)
                        .opacity(visit.clinician.isEmpty ? 0 : 1)
                    Text([
                        visit.date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day()),
                        timeText(visit.date, in: zone)
                    ].joined(separator: " · "))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CareTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("No visits")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(CareTheme.ink)
                        .padding(.vertical, 4)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CareTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("senior.home.visit")
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
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(CareTheme.ink)
                    Spacer()
                    Button("Edit") { showManage = true }
                        .font(.system(size: 18, weight: .bold))
                        .accessibilityIdentifier("senior.medicines.manage")
                }
                .padding(.top, 26)
                MedicineListView(title: "Tap each one when you take it")
                if let adherence = state.selectedSummary?.adherence, adherence.expected > 0 {
                    LovableCard {
                        Text("This week: \(adherence.taken) of \(adherence.expected) doses taken")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(CareTheme.ink)
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
                    .font(.system(size: 32, weight: .bold))
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
        .background(CareTheme.card)
        .overlay(Rectangle().fill(CareTheme.hairline).frame(height: 1), alignment: .top)
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
            .foregroundStyle(active ? CareTheme.ink : CareTheme.secondaryText)
            .padding(.vertical, 9)
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

    private var savedContacts: [Person] {
        (state.selectedSummary?.contacts ?? []).map { Person(id: $0.id, name: $0.name, phone: $0.phone) }
    }

    private var people: [Person] {
        let contacts = savedContacts
        let family = state.snapshot.members
            .filter { member in
                member.profileID != state.currentProfileID
                    && PhoneLinks.call(member.phone) != nil
                    && !contacts.contains { PhoneLinks.sameNumber($0.phone, member.phone) }
            }
            .map { Person(id: $0.id, name: $0.name.isEmpty ? "Family member" : $0.name, phone: $0.phone) }
        return contacts + family
    }

    private var sosDetail: String {
        if failed { return "Call someone directly below." }
        if let contact = savedContacts.first {
            return "\(contact.name) is being called, and everyone in \(state.snapshot.account.name) who uses the app is notified."
        }
        return "Everyone in \(state.snapshot.account.name) who uses the app is notified. Add an SOS contact in Settings to call them from here."
    }

    var body: some View {
        ZStack {
            (sent ? CareTheme.action : CareTheme.danger).ignoresSafeArea()
            if sent { sentBody } else { countdownBody }
        }
        .task {
            while seconds > 0 && !sent {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                seconds -= 1
            }
            await state.triggerSOS()
            guard !Task.isCancelled else { return }
            failed = !state.hasEmergency
            sent = true
            if !failed, let contact = savedContacts.first, let url = PhoneLinks.call(contact.phone) {
                openURL(url)
            }
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
                    .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
            .accessibilityIdentifier("sos.cancel")
            Text("Next time, say “Send SOS in CareCompanion.”")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
        }
    }

    private var sentBody: some View {
        ScrollView {
            VStack(spacing: 18) {
                CircleIcon(systemName: failed ? "wifi.exclamationmark" : "checkmark", color: .white, size: 104, iconSize: 50, fillOpacity: 0.24)
                    .padding(.top, 60)
                Text(failed ? "Couldn't reach the internet" : (savedContacts.isEmpty ? "Your family has been\nnotified" : "Calling \(savedContacts[0].name)"))
                    .font(.system(size: 32, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("sos.notified.title")
                Text(sosDetail)
                    .font(.system(size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.92))
                ForEach(people) { person in
                    if let url = PhoneLinks.video(person.phone) {
                        Button { openURL(url) } label: {
                            Label("FaceTime \(person.name)", systemImage: "video.fill")
                                .font(.system(size: 23, weight: .black))
                                .foregroundStyle(CareTheme.sageDark)
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if let url = PhoneLinks.call(person.phone) {
                        Button { openURL(url) } label: {
                            Label("Call \(person.name)", systemImage: "phone.fill")
                                .font(.system(size: 23, weight: .black))
                                .foregroundStyle(CareTheme.sageDark)
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .background(CareTheme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
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
