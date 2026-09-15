import CareCore
import SwiftUI

/// The caregiver's experience: dashboard, health, alerts, visits, messages and profile.
struct FamilyRootView: View {
    @Environment(AppState.self) private var state
    @State private var showSettings = false

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if state.familyTab == .messages {
                        MessagesScreen()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                switch state.familyTab {
                                case .dashboard: FamilyHome(showSettings: $showSettings)
                                case .health: HealthTimelineView()
                                case .alerts: AlertsView()
                                case .appointments: FamilyVisitsView()
                                case .profile: FamilyProfileView(showSettings: $showSettings)
                                case .messages: EmptyView()
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, state.familyTab == .dashboard ? 22 : 24)
                            .padding(.bottom, 24)
                        }
                        .refreshable { await state.refresh() }
                    }
                }
                .frame(maxHeight: .infinity)
                ReferenceBottomBar(
                    items: [
                        (.dashboard, "Home", "square.grid.2x2", nil),
                        (.health, "Health", "waveform.path.ecg", nil),
                        (.alerts, "Alerts", "bell", state.activeAlertCount > 0 ? state.activeAlertCount : nil),
                        (.appointments, "Visits", "calendar", nil),
                        (.messages, "Messages", "bubble.left.and.bubble.right", nil),
                        (.profile, "Profile", "person.crop.circle", nil)
                    ],
                    selection: $state.familyTab
                )
            }
            .background {
                if state.familyTab == .dashboard {
                    FamilyHomeBackdrop().ignoresSafeArea()
                } else {
                    CareTheme.background.ignoresSafeArea()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showSettings) { SettingsView().environment(state) }
    }
}

// MARK: - Home

private struct FamilyHome: View {
    @Environment(AppState.self) private var state
    @Binding var showSettings: Bool
    @State private var showAddSenior = false
    @State private var detailSeniorID: String?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        guard let me = state.currentMember, !me.name.isEmpty else { return part }
        return "\(part),\n\(me.name.split(separator: " ").first.map(String.init) ?? me.name)"
    }

    var body: some View {
        let indexed = Array(state.seniorSummaries.enumerated())
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting)
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .foregroundStyle(CareTheme.heading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("family.title")
                    Text(state.snapshot.account.name.isEmpty ? "Together for what matters most." : state.snapshot.account.name)
                        .font(.subheadline)
                        .foregroundStyle(CareTheme.mutedText)
                }
                Spacer(minLength: 0)
                Button { showSettings = true } label: {
                    Text(state.currentMember?.name.first.map { String($0).uppercased() } ?? "·")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(CareTheme.heading)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("family.settings")
            }
            .padding(.bottom, 6)

            if let selected = state.selectedSummary {
                FamilyStatusCard(summary: selected) {
                    if selected.hasEmergency || state.activeAlertCount > 0 {
                        state.familyTab = .alerts
                    } else {
                        detailSeniorID = selected.id
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(indexed, id: \.element.id) { index, summary in
                    Button {
                        state.selectSenior(id: summary.id)
                        detailSeniorID = summary.id
                    } label: {
                        FamilyProfileTile(summary: summary, color: CareTheme.seniorColor(at: index),
                                          isSelected: summary.id == state.selectedSeniorID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(summary.senior.name), \(FamilyProfileTile.status(for: summary).text)")
                    .accessibilityAddTraits(summary.id == state.selectedSeniorID ? .isSelected : [])
                    .accessibilityIdentifier("family.senior.\(summary.firstName.lowercased())")
                }
                Button { showAddSenior = true } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(CareTheme.sageDark)
                            .frame(width: 80, height: 80)
                            .background(CareTheme.sagePale.opacity(0.7), in: Circle())
                        Text("Add")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(CareTheme.heading)
                        Text("Someone you care for")
                            .font(.caption)
                            .foregroundStyle(CareTheme.mutedText)
                    }
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(CareTheme.sage.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a senior")
                .accessibilityIdentifier("family.addSenior")
            }

            if let selected = state.selectedSummary {
                Button { detailSeniorID = selected.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 20))
                            .foregroundStyle(CareTheme.sageDark)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Care insight")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(CareTheme.heading)
                            Text("A little context for \(selected.firstName)'s day")
                                .font(.caption)
                                .foregroundStyle(CareTheme.mutedText)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CareTheme.sageDark)
                    }
                    .padding(14)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("family.insightTeaser")
            }

            Text("A little closer, every day.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(CareTheme.heading.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 6)
        }
        .navigationDestination(item: $detailSeniorID) { _ in
            FamilyCareDetailView()
        }
        .sheet(isPresented: $showAddSenior) { AddSeniorSheet().environment(state) }
    }
}

/// The selected senior's day in one sentence, leading to alerts or their care details.
private struct FamilyStatusCard: View {
    let summary: SeniorCareSummary
    let action: () -> Void

    private var title: String {
        if summary.hasEmergency { return "\(summary.firstName) sent an SOS" }
        return summary.isCheckedIn ? "\(summary.firstName) checked in today" : "Waiting to hear from \(summary.firstName)"
    }

    private var detail: String {
        if summary.hasEmergency { return "Open the alert to respond." }
        guard let first = summary.attentionItems.first(where: { !$0.hasPrefix("no check-in") }) ?? summary.attentionItems.first else {
            return "You're up to date on \(summary.firstName)'s day."
        }
        let extra = summary.attentionItems.count - 1
        return first.prefix(1).uppercased() + first.dropFirst() + (extra > 0 ? " and \(extra) more." : ".")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: summary.hasEmergency ? "exclamationmark.triangle.fill" : "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(summary.hasEmergency ? .white : CareTheme.coral)
                    .frame(width: 44, height: 44)
                    .background(summary.hasEmergency ? CareTheme.coral : CareTheme.coralPale, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(CareTheme.heading)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(CareTheme.mutedText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CareTheme.mutedText)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(summary.hasEmergency ? CareTheme.coral : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("family.status")
    }
}

private struct FamilyProfileTile: View {
    let summary: SeniorCareSummary
    let color: Color
    let isSelected: Bool

    static func status(for summary: SeniorCareSummary) -> (text: String, color: Color, icon: String) {
        if summary.hasEmergency { return ("SOS needs attention", CareTheme.coral, "exclamationmark") }
        if !summary.isCheckedIn { return ("No check-in yet", CareTheme.mutedText, "clock") }
        if summary.needsAttention { return ("Needs attention", CareTheme.goldDark, "exclamationmark") }
        return ("Checked in today", CareTheme.sageDark, "checkmark")
    }

    var body: some View {
        let status = Self.status(for: summary)
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                SeniorAvatar(name: summary.senior.name, initials: summary.initials, color: color, size: 74)
                    .padding(3)
                    .background(CareTheme.coralPale.opacity(0.65), in: Circle())
                Image(systemName: status.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(status.color, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .accessibilityHidden(true)
            Text(summary.firstName)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(CareTheme.heading)
                .lineLimit(1)
            Text(status.text)
                .font(.caption)
                .foregroundStyle(status.color)
                .accessibilityIdentifier(isSelected ? "family.tileStatus" : "")
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(isSelected ? CareTheme.sage.opacity(0.6) : .clear, lineWidth: 2))
        .shadow(color: CareTheme.ink.opacity(0.035), radius: 12, y: 5)
    }
}

/// The selected senior's full daily summary and care insight.
private struct FamilyCareDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let indexed = Array(state.seniorSummaries.enumerated())
        let index = indexed.first { $0.element.id == state.selectedSeniorID }?.offset ?? 0
        ScrollView {
            VStack(spacing: 20) {
                if let summary = state.selectedSummary {
                    SeniorSummaryCard(summary: summary, color: CareTheme.seniorColor(at: index), isSelected: true)
                    CareInsightCard(onViewTimeline: { dismiss() })
                }
            }
            .padding(20)
        }
        .refreshable { await state.refresh() }
        .background(CareTheme.background.ignoresSafeArea())
        .navigationTitle(state.selectedSummary.map { "\($0.firstName)'s care" } ?? "Care")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct FamilyHomeBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                CareTheme.background
                Circle()
                    .fill(CareTheme.coralPale)
                    .frame(width: 82, height: 82)
                    .offset(x: -24, y: 70)
                FamilyLandscapeWave()
                    .fill(CareTheme.bluePale.opacity(0.45))
                    .frame(height: 115)
                    .offset(y: 96)
                VStack(spacing: 0) {
                    Spacer()
                    ZStack {
                        FamilyLandscapeWave()
                            .fill(CareTheme.coralPale.opacity(0.55))
                            .scaleEffect(x: -1, y: 1)
                            .offset(y: -22)
                        FamilyLandscapeWave()
                            .fill(CareTheme.bluePale.opacity(0.65))
                    }
                    .frame(height: geometry.size.height * 0.19)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FamilyLandscapeWave: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: rect.height * 0.4))
            path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.25),
                          control1: CGPoint(x: rect.width * 0.35, y: -rect.height * 0.25),
                          control2: CGPoint(x: rect.width * 0.62, y: rect.height * 1.1))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }
    }
}

private struct AddSeniorSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var age = 70
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SeniorDetailsFields(name: $name, age: $age, city: $city, timeZone: $timeZone)
                    Text("If they'll use CareCompanion on their own iPhone, share your invite code so they can join and link themselves.")
                        .font(.system(size: 14))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                .padding(20)
            }
            .background(CareTheme.background)
            .navigationTitle("Add a senior")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            isSaving = true
                            let added = await state.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZone)
                            isSaving = false
                            if added { dismiss() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }
}

private struct CareInsightCard: View {
    @Environment(AppState.self) private var state
    var onViewTimeline: (() -> Void)? = nil

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CareTheme.gold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Care insight").font(.system(size: 15, weight: .black))
                    if let insight = state.careInsight {
                        Text(insight.summary)
                            .font(.system(size: 16))
                            .lineSpacing(4)
                            .foregroundStyle(CareTheme.mutedText)
                        ForEach(insight.observations, id: \.self) { observation in
                            Label(observation, systemImage: "checkmark.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(CareTheme.secondaryText)
                        }
                        Text(insight.suggestion)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CareTheme.sageDark)
                    } else {
                        ProgressView()
                    }
                    Button {
                        state.familyTab = .health
                        onViewTimeline?()
                    } label: {
                        Label("View health timeline", systemImage: "chevron.right")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(CareTheme.sageDark)
                    }
                    .accessibilityIdentifier("insight.timeline")
                }
            }
        }
        .accessibilityIdentifier("insight.card")
        .task(id: state.selectedSummary) {
            await state.loadCareInsight()
        }
    }
}

private struct SeniorSummaryCard: View {
    @Environment(\.openURL) private var openURL
    let summary: SeniorCareSummary
    let color: Color
    let isSelected: Bool

    private var zone: TimeZone { TimeZone(identifier: summary.senior.timeZoneIdentifier) ?? .current }
    private var subtitle: String {
        [summary.senior.city, "\(summary.senior.age) years"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    private var checkInText: String {
        guard let date = summary.checkInDate else { return "No check-in yet today" }
        let suffix = zone.identifier == TimeZone.current.identifier ? "" : " their time"
        return "Checked in at \(timeText(date, in: zone))\(suffix)"
    }
    private var moodEmoji: String {
        switch summary.mood {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        case nil: "·"
        }
    }
    private var status: (text: String, color: Color, fill: Color) {
        if summary.hasEmergency { return ("SOS open", CareTheme.coralDark, CareTheme.coralPale) }
        if summary.needsAttention { return ("Needs attention", CareTheme.goldDark, CareTheme.goldPale) }
        return ("All good", CareTheme.sageDark, CareTheme.sagePale)
    }
    private func stat(_ value: Int?, _ format: (Int) -> String) -> String {
        guard let value, value > 0 else { return "—" }
        return format(value)
    }
    private var healthNotice: String {
        guard let latest = summary.latestHealth else {
            return summary.linkedMember == nil
                ? "\(summary.firstName) hasn't joined on their iPhone yet, so Apple Health can't sync."
                : "Waiting for \(summary.firstName) to share Apple Health."
        }
        let day = latest.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt))
        return latest.source == "healthkit" ? "From Apple Health · \(day)" : "Source: \(latest.source) · \(day)"
    }

    var body: some View {
        LovableCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    SeniorAvatar(name: summary.senior.name, initials: summary.initials, color: color, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.senior.name).font(.system(size: 20, weight: .black)).foregroundStyle(CareTheme.ink)
                            .lineLimit(2)
                        Text(subtitle).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    Spacer()
                    PlainPill(text: status.text, icon: "circle.fill", color: status.color, fill: status.fill)
                        .fixedSize()
                }
                HStack {
                    Image(systemName: "clock")
                    Text(checkInText)
                        .font(.system(size: 15, weight: .black))
                        .accessibilityIdentifier(isSelected ? "family.checkedIn" : "")
                    Spacer()
                    Text(moodEmoji).font(.system(size: 24)).accessibilityLabel(summary.mood?.rawValue ?? "No mood recorded")
                }
                .foregroundStyle(CareTheme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .background(CareTheme.grayPill, in: Capsule())
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    SmallMetric(title: "Medications",
                                value: summary.medicationsTotal == 0 ? "None added" : "\(summary.medicationsTaken) of \(summary.medicationsTotal) taken",
                                icon: "pills", color: CareTheme.gold, identifier: isSelected ? "family.medications" : nil)
                    SmallMetric(title: "Mood", value: summary.mood?.rawValue ?? "Not recorded", icon: "face.smiling", color: CareTheme.sage)
                    SmallMetric(title: "Steps", value: stat(summary.latestHealth?.steps) { $0.formatted() },
                                icon: "shoeprints.fill", color: CareTheme.blue, identifier: isSelected ? "family.steps" : nil)
                    SmallMetric(title: "Sleep", value: stat(summary.latestHealth?.sleepMinutes) { SeniorCareSummary.duration(minutes: $0) },
                                icon: "moon", color: CareTheme.blue, identifier: isSelected ? "family.sleep" : nil)
                    SmallMetric(title: "Resting heart rate", value: stat(summary.latestHealth?.restingHeartRate) { "\($0) bpm" },
                                icon: "heart", color: CareTheme.coral, identifier: isSelected ? "family.heartRate" : nil)
                }
                HStack {
                    Text(healthNotice)
                        .font(.system(size: 12))
                        .foregroundStyle(CareTheme.mutedText)
                    Spacer()
                    if let phone = summary.phone, let url = PhoneLinks.call(phone) {
                        Button { openURL(url) } label: {
                            Label("Call", systemImage: "phone.fill")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(CareTheme.sage, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Call \(summary.firstName)")
                    }
                }
            }
        }
    }
}

// MARK: - Health

private enum HealthDay {
    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .gmt).weekday(.abbreviated))
    }
}

private struct HealthTimelineView: View {
    @Environment(AppState.self) private var state

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var history: [HealthSnapshot] { Array((care?.healthHistory ?? []).prefix(7).reversed()) }
    private var notice: String {
        guard let care else { return "" }
        guard let latest = care.latestHealth else {
            return care.linkedMember == nil
                ? "Health data syncs from \(care.firstName)'s own iPhone once they join with your invite code and allow Apple Health."
                : "Waiting for \(care.firstName) to allow Apple Health on their iPhone."
        }
        return latest.source == "healthkit" ? "Daily totals shared from Apple Health." : "Source: \(latest.source)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenTitle(title: "Health", subtitle: care.map { "\($0.senior.name) · last \(history.count) synced \(history.count == 1 ? "day" : "days")" })
            Text(notice)
                .font(.system(size: 13))
                .foregroundStyle(CareTheme.mutedText)
                .accessibilityIdentifier("timeline.healthDataNotice")
            SleepChartCard(history: history, average: care?.averageSleepMinutes)
            StepsChartCard(history: history, baseline: care?.baselineSteps)
            HeartChartCard(history: history, range: care?.restingHeartRateRange)
            AdherenceCard(care: care)
            MoodTrendCard(moods: care?.moodHistory ?? [])
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
        return "\(SeniorCareSummary.duration(minutes: minutes)) last night"
    }

    var body: some View {
        let longest = max(history.map(\.sleepMinutes).max() ?? 0, 1)
        LovableCard {
            VStack(alignment: .leading, spacing: 18) {
                ChartHeader(title: "Sleep", icon: "moon", value: latestText)
                if history.isEmpty {
                    ChartFootnote(text: "Sleep appears here after the first Apple Health sync.")
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(history) { day in
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(day.sleepMinutes > 0 ? CareTheme.sage.opacity(0.82) : CareTheme.grayPill)
                                    .frame(height: 12 + CGFloat(day.sleepMinutes) / CGFloat(longest) * 100)
                                Text(HealthDay.weekday(day.date)).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(HealthDay.weekday(day.date)): \(day.sleepMinutes > 0 ? SeniorCareSummary.duration(minutes: day.sleepMinutes) : "no data")")
                        }
                    }
                    .frame(height: 136, alignment: .bottom)
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
                .frame(height: 130)
                .accessibilityElement()
                .accessibilityLabel("Trend of \(values.count) days, from \(values.first ?? 0) to \(values.last ?? 0)")
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
            let location = { (index: Int, point: CGFloat) in
                CGPoint(x: CGFloat(index) / CGFloat(points.count - 1) * width, y: (1 - point) * height)
            }
            Path { path in
                for (index, point) in points.enumerated() {
                    index == 0 ? path.move(to: location(index, point)) : path.addLine(to: location(index, point))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 0, y: height))
                for (index, point) in points.enumerated() {
                    path.addLine(to: location(index, point))
                }
                path.addLine(to: CGPoint(x: width, y: height))
            }
            .fill(color.opacity(0.12))
        }
    }
}

private struct AdherenceCard: View {
    let care: SeniorCareSummary?

    var body: some View {
        let week = care?.adherence
        let fraction = week?.fraction ?? 0
        LovableCard {
            HStack(spacing: 22) {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(CareTheme.sage, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-90))
                    .background(Circle().stroke(CareTheme.sage.opacity(0.18), lineWidth: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Medicines this week").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    if let week, week.expected > 0 {
                        Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 30, weight: .black))
                        Text("\(week.taken) of \(week.expected) doses marked taken").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                    } else {
                        Text("—").font(.system(size: 30, weight: .black))
                        Text("No medicines added yet").font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MoodTrendCard: View {
    let moods: [MoodEntry]

    private func emoji(_ mood: Mood) -> String {
        switch mood {
        case .great: "😊"
        case .okay: "😐"
        case .low: "😔"
        }
    }

    var body: some View {
        LovableCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Mood").font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                if moods.isEmpty {
                    ChartFootnote(text: "No moods recorded yet.")
                } else {
                    HStack {
                        ForEach(moods) { entry in
                            VStack(spacing: 6) {
                                Text(emoji(entry.mood)).font(.system(size: 24))
                                Text(entry.date.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(entry.date.formatted(.dateTime.weekday(.wide))): \(entry.mood.rawValue)")
                        }
                    }
                    if let note = moods.last?.note, !note.isEmpty {
                        Text("“\(note)”")
                            .font(.system(size: 14))
                            .italic()
                            .foregroundStyle(CareTheme.mutedText)
                    }
                }
            }
        }
    }
}

// MARK: - Alerts

private struct AlertsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openURL) private var openURL
    @State private var dismissed: Set<String> = []

    private var care: SeniorCareSummary? { state.selectedSummary }
    private var name: String { care?.firstName ?? "Your senior" }
    private var callURL: URL? {
        if let phone = care?.phone, let url = PhoneLinks.call(phone) { return url }
        return care?.contacts.compactMap { PhoneLinks.call($0.phone) }.first
    }
    private func key(_ kind: String) -> String { "\(state.selectedSeniorID)-\(kind)" }

    private var showsEmergency: Bool { care?.hasEmergency == true }
    private var missedMedications: [Medication] { dismissed.contains(key("medication")) ? [] : (care?.missedMedications ?? []) }
    private var lowActivity: (steps: Int, baseline: Int)? {
        guard !dismissed.contains(key("health")), let care, care.isStepsBelowBaseline,
              let steps = care.latestHealth?.steps, let baseline = care.baselineSteps else { return nil }
        return (steps, baseline)
    }
    private var showsCheckIn: Bool { care?.isCheckedIn == false && !dismissed.contains(key("checkin")) }
    private var visibleCount: Int { [showsEmergency, !missedMedications.isEmpty, lowActivity != nil, showsCheckIn].filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScreenTitle(title: "Alerts", subtitle: "\(visibleCount) active · \(care?.senior.name ?? "")")
                .accessibilityIdentifier("alerts.title")
            if showsEmergency {
                AlertRow(kind: "EMERGENCY", when: care?.openAlertDate.map { timeText($0, in: state.selectedTimeZone) } ?? "Now",
                         title: "SOS alert from \(name)", detail: "\(name) asked for help. Call them, then mark the alert as handled.",
                         color: CareTheme.coral, fill: CareTheme.coralPale, icon: "exclamationmark.triangle",
                         dismissTitle: "Handled", callURL: callURL, openURL: openURL,
                         onMessage: { state.familyTab = .messages },
                         onDismiss: { Task { await state.acknowledgeEmergency() } })
                    .accessibilityIdentifier("alerts.sos")
            }
            if let first = missedMedications.first {
                AlertRow(kind: "MEDICATION", when: "Today",
                         title: missedMedications.count == 1 ? "\(name) hasn't taken \(first.name) yet" : "\(name) hasn't taken \(missedMedications.count) medicines yet",
                         detail: missedMedications.map { "\($0.name) (\($0.scheduledTime))" }.joined(separator: ", "),
                         color: CareTheme.gold, fill: .white, icon: "pills", dismissTitle: "Dismiss", callURL: callURL, openURL: openURL,
                         onMessage: { state.familyTab = .messages },
                         onDismiss: { dismissed.insert(key("medication")) })
            }
            if let lowActivity {
                AlertRow(kind: "ACTIVITY", when: "Latest synced day", title: "Fewer steps than usual",
                         detail: "\(lowActivity.steps.formatted()) steps vs. a \(lowActivity.baseline.formatted())-step average on earlier days.",
                         color: CareTheme.blue, fill: CareTheme.bluePale, icon: "figure.walk", dismissTitle: "Dismiss",
                         callURL: callURL, openURL: openURL,
                         onMessage: { state.familyTab = .messages },
                         onDismiss: { dismissed.insert(key("health")) })
            }
            if showsCheckIn {
                AlertRow(kind: "CHECK-IN", when: "Today", title: "No check-in yet today", detail: "\(name) hasn't tapped \"I'm okay\" today.",
                         color: CareTheme.gold, fill: CareTheme.grayPill.opacity(0.45), icon: "clock", dismissTitle: "Dismiss",
                         callURL: callURL, openURL: openURL,
                         onMessage: { state.familyTab = .messages },
                         onDismiss: { dismissed.insert(key("checkin")) })
            }
            if visibleCount == 0 {
                LovableCard(fill: CareTheme.sagePale, stroke: CareTheme.sage.opacity(0.3)) {
                    Label("All clear", systemImage: "checkmark.circle")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(CareTheme.sageDark)
                }
            }
            if callURL == nil, visibleCount > 0 {
                Text("Add \(name)'s phone or an emergency contact in Profile to call from here.")
                    .font(.system(size: 13))
                    .foregroundStyle(CareTheme.secondaryText)
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
    let dismissTitle: String
    let callURL: URL?
    let openURL: OpenURLAction
    let onMessage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        LovableCard(fill: fill, stroke: color.opacity(0.28)) {
            HStack(alignment: .top, spacing: 14) {
                CircleIcon(systemName: icon, color: color, size: 42, iconSize: 18, fillOpacity: 0.22)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(kind) · \(when)").font(.system(size: 11, weight: .black)).foregroundStyle(CareTheme.secondaryText)
                    Text(title).font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.ink)
                    Text(detail).font(.system(size: 15)).foregroundStyle(CareTheme.mutedText)
                    HStack(spacing: 8) {
                        if let callURL {
                            Button { openURL(callURL) } label: {
                                PlainPill(text: "Call", icon: "phone", color: .white, fill: CareTheme.sage)
                            }
                            .buttonStyle(.plain)
                        }
                        Button(action: onMessage) {
                            PlainPill(text: "Message", icon: "bubble.right", color: CareTheme.ink, fill: .white)
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        Button(action: onDismiss) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CareTheme.mutedText)
                                .frame(width: 40, height: 40)
                                .background(.white.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(dismissTitle)
                    }
                }
            }
        }
    }
}

// MARK: - Visits

private struct FamilyVisitsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScreenTitle(title: "Visits", subtitle: state.selectedSenior?.name)
            CalendarCard(appointmentDates: state.appointments.map(\.date), timeZone: state.selectedTimeZone)
            AppointmentListSection()
            if let next = state.nextAppointment {
                if let prep = state.appointmentPrep {
                    AppointmentPrepCard(prep: prep)
                } else {
                    Button {
                        Task { await state.prepareAppointment(id: next.id) }
                    } label: {
                        Label("Prepare questions for \(next.title)", systemImage: "sparkles")
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
}

private struct CalendarCard: View {
    let appointmentDates: [Date]
    let timeZone: TimeZone

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        let calendar = calendar
        let now = Date()
        let today = calendar.component(.day, from: now)
        let month = calendar.dateInterval(of: .month, for: now)
        let days = calendar.range(of: .day, in: .month, for: now) ?? 1..<2
        let offset = month.map { (calendar.component(.weekday, from: $0.start) + 5) % 7 } ?? 0
        let slots: [Int?] = Array(repeating: nil, count: offset) + days.map { $0 }
        let marked = Set(appointmentDates.filter { calendar.isDate($0, equalTo: now, toGranularity: .month) }
            .map { calendar.component(.day, from: $0) })

        LovableCard {
            VStack(spacing: 12) {
                Text(now.formatted(Date.FormatStyle(timeZone: timeZone).month(.wide).year()))
                    .font(.system(size: 16, weight: .black))
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                        Text(day).font(.system(size: 12, weight: .bold)).foregroundStyle(CareTheme.secondaryText).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                    ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                        if let day = slot {
                            Text("\(day)")
                                .font(.system(size: 15, weight: day == today ? .black : .regular))
                                .foregroundStyle(day == today ? .white : CareTheme.mutedText)
                                .frame(width: 34, height: 34)
                                .background(day == today ? CareTheme.ink : (marked.contains(day) ? CareTheme.sagePale : .clear), in: Circle())
                        } else {
                            Color.clear.frame(width: 34, height: 34)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(marked.count) visits this month")
    }
}

private struct AppointmentPrepCard: View {
    let prep: AppointmentPrep

    var body: some View {
        LovableCard(fill: CareTheme.goldPale, stroke: CareTheme.gold.opacity(0.35)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(prep.title).font(.system(size: 18, weight: .black))
                    .accessibilityIdentifier("appointment.prep.ready")
                Text("Recent observations").font(.system(size: 14, weight: .black)).foregroundStyle(CareTheme.goldDark)
                ForEach(prep.observations, id: \.self) { observation in
                    Label(observation, systemImage: "checkmark.circle").font(.system(size: 13)).foregroundStyle(CareTheme.mutedText)
                }
                Text("Questions to ask").font(.system(size: 14, weight: .black)).foregroundStyle(CareTheme.goldDark)
                ForEach(prep.questions, id: \.self) { question in
                    Label(question, systemImage: "questionmark.circle").font(.system(size: 14))
                }
                Text(prep.safetyNote).font(.system(size: 12)).foregroundStyle(CareTheme.secondaryText)
            }
        }
    }
}

// MARK: - Profile

private struct FamilyProfileView: View {
    @Environment(AppState.self) private var state
    @Binding var showSettings: Bool
    @State private var showEditSenior = false
    @State private var showMedications = false
    @State private var editingContact: EmergencyContact?
    @State private var addingContact = false
    @State private var confirmRemove = false

    private var care: SeniorCareSummary? { state.selectedSummary }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                ScreenTitle(title: "Profile", subtitle: "Care plan and family")
                    .accessibilityIdentifier("profile.title")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CareTheme.mutedText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }

            if let care {
                LovableCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            SeniorAvatar(name: care.senior.name, initials: care.initials, color: CareTheme.gold, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(care.senior.name).font(.system(size: 20, weight: .black))
                                Text([care.senior.city, "\(care.senior.age) years"].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                                Text(TimeZoneListView.label(for: care.senior.timeZoneIdentifier))
                                    .font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                            }
                            Spacer()
                        }
                        Text(care.linkedMember == nil
                             ? "\(care.firstName) isn't using the app on their own iPhone yet. Share the invite code so they can check in and share Apple Health."
                             : "\(care.firstName) uses CareCompanion on their iPhone.")
                            .font(.system(size: 13))
                            .foregroundStyle(CareTheme.mutedText)
                        Button { showEditSenior = true } label: {
                            Label("Edit details", systemImage: "pencil")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(CareTheme.sageDark)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(CareTheme.sagePale, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.edit")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Emergency contacts")
                    Spacer()
                    Button { addingContact = true } label: { Label("Add", systemImage: "plus").font(.system(size: 15, weight: .bold)) }
                        .accessibilityIdentifier("profile.addContact")
                }
                LovableCard {
                    VStack(alignment: .leading, spacing: 4) {
                        if care?.contacts.isEmpty ?? true {
                            Text("Add people to call in an emergency. They appear on \(care?.firstName ?? "the senior")'s SOS screen.")
                                .font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                        }
                        ForEach(care?.contacts ?? []) { contact in
                            Button { editingContact = contact } label: {
                                ContactRow(name: contact.name, detail: contact.relation.isEmpty ? contact.phone : "\(contact.relation) · \(contact.phone)",
                                           phone: contact.phone)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(text: "Medicines")
                    Spacer()
                    Button { showMedications = true } label: { Label("Edit", systemImage: "pencil").font(.system(size: 15, weight: .bold)) }
                        .accessibilityIdentifier("profile.manageMedications")
                }
                LovableCard { MedicineListView(title: "Today", large: false) }
            }

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "Family members")
                LovableCard {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.snapshot.members) { member in
                            let isMe = member.profileID == state.currentProfileID
                            ContactRow(name: (member.name.isEmpty ? "Family member" : member.name) + (isMe ? " (you)" : ""),
                                       detail: [member.role == .senior ? "Senior" : "Family", member.city].filter { !$0.isEmpty }.joined(separator: " · "),
                                       phone: isMe ? "" : member.phone)
                        }
                    }
                }
                InviteCodeCard()
            }

            if let care {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Health baseline")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        SmallMetric(title: "Resting heart rate", value: care.restingHeartRateRange.map { $0.lowerBound == $0.upperBound ? "\($0.lowerBound) bpm" : "\($0.lowerBound)–\($0.upperBound) bpm" } ?? "—",
                                    icon: "heart", color: CareTheme.coral)
                        SmallMetric(title: "Average sleep", value: care.averageSleepMinutes.map { SeniorCareSummary.duration(minutes: $0) } ?? "—",
                                    icon: "moon", color: CareTheme.blue)
                        SmallMetric(title: "Daily steps", value: care.averageSteps.map { $0.formatted() } ?? "—",
                                    icon: "shoeprints.fill", color: CareTheme.blue)
                        SmallMetric(title: "Medicines this week", value: care.adherence.map { $0.expected == 0 ? "—" : "\(Int(($0.fraction * 100).rounded()))%" } ?? "—",
                                    icon: "pills", color: CareTheme.gold)
                    }
                }

                Button(role: .destructive) { confirmRemove = true } label: {
                    Text("Remove \(care.firstName) from the family")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(CareTheme.coralDark)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Remove \(care.senior.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        Task { await state.removeSenior(id: care.id) }
                    }
                } message: {
                    Text("Their check-ins, medicines and visits stop showing for everyone in the family.")
                }
            }
        }
        .sheet(isPresented: $showEditSenior) { EditSeniorProfileView().environment(state) }
        .sheet(isPresented: $showMedications) { MedicationManagementView().environment(state) }
        .sheet(isPresented: $addingContact) { EmergencyContactFormView(contact: nil).environment(state) }
        .sheet(item: $editingContact) { EmergencyContactFormView(contact: $0).environment(state) }
    }
}
