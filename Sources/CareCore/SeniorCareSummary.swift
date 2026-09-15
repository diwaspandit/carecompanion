import Foundation

/// Everything the dashboards and AI summaries know about one senior, derived from the care snapshot.
public struct SeniorCareSummary: Identifiable, Equatable, Sendable {
    public struct Adherence: Equatable, Sendable {
        public let taken: Int
        public let expected: Int

        public var fraction: Double { expected == 0 ? 0 : Double(taken) / Double(expected) }
    }

    public let senior: AccountSenior
    /// The account member who is this senior, when they use the app on their own phone.
    public let linkedMember: AccountMember?
    public let checkInDate: Date?
    public let mood: Mood?
    public let moodNote: String?
    /// Latest mood per day in the senior's time zone, oldest first, at most seven days.
    public let moodHistory: [MoodEntry]
    public let medications: [Medication]
    /// Doses marked taken over the last seven local days, counted from the first recorded event.
    public let adherence: Adherence?
    /// One entry per day, newest first. HealthKit values win over other sources for the same day.
    public let healthHistory: [HealthSnapshot]
    public let hasEmergency: Bool
    public let openAlertDate: Date?
    public let nextAppointment: Appointment?
    public let contacts: [EmergencyContact]

    public init?(snapshot: CareSnapshot, seniorID: String, now: Date = Date()) {
        guard let senior = snapshot.seniors.first(where: { $0.id == seniorID }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: senior.timeZoneIdentifier) ?? .gmt

        self.senior = senior
        linkedMember = senior.profileID.flatMap { profileID in snapshot.members.first { $0.profileID == profileID } }
        checkInDate = snapshot.checkIns.filter { $0.seniorID == seniorID }.map(\.date).max()

        let seniorMoods = snapshot.moods.filter { $0.seniorID == seniorID }
        let latestMood = seniorMoods.max { $0.date < $1.date }
        mood = latestMood?.mood
        moodNote = latestMood?.note
        moodHistory = Array(Dictionary(grouping: seniorMoods) { calendar.startOfDay(for: $0.date) }
            .values
            .compactMap { entries in entries.max { $0.date < $1.date } }
            .sorted { $0.date < $1.date }
            .suffix(7))

        medications = snapshot.medications.filter { $0.seniorID == seniorID }
        adherence = Self.weeklyAdherence(medications: medications,
                                         events: snapshot.medicationEvents.filter { $0.seniorID == seniorID },
                                         calendar: calendar, now: now)
        healthHistory = Self.oneEntryPerDay(snapshot.health.filter { $0.seniorID == seniorID })

        let openAlerts = snapshot.alerts.filter { $0.seniorID == seniorID && !$0.acknowledged }
        hasEmergency = !openAlerts.isEmpty
        openAlertDate = openAlerts.map(\.date).max()
        nextAppointment = snapshot.appointments
            .filter { $0.seniorID == seniorID && $0.date >= now.addingTimeInterval(-3600) }
            .min { $0.date < $1.date }
        contacts = snapshot.contacts.filter { $0.seniorID == seniorID }
    }

    public var id: String { senior.id }
    public var firstName: String { senior.name.split(separator: " ").first.map(String.init) ?? senior.name }
    public var initials: String {
        String(senior.name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
    public var phone: String? {
        guard let phone = linkedMember?.phone, !phone.isEmpty else { return nil }
        return phone
    }
    public var isCheckedIn: Bool { checkInDate != nil }
    public var medicationsTaken: Int { medications.filter(\.taken).count }
    public var medicationsTotal: Int { medications.count }
    public var missedMedications: [Medication] { medications.filter { !$0.taken } }
    public var latestHealth: HealthSnapshot? { healthHistory.first }

    /// Average steps across the days before the latest one, ignoring days with no step data.
    public var baselineSteps: Int? { Self.average(healthHistory.dropFirst().map(\.steps)) }
    public var averageSleepMinutes: Int? { Self.average(healthHistory.map(\.sleepMinutes)) }
    public var averageSteps: Int? { Self.average(healthHistory.map(\.steps)) }
    public var restingHeartRateRange: ClosedRange<Int>? {
        let values = healthHistory.map(\.restingHeartRate).filter { $0 > 0 }
        guard let low = values.min(), let high = values.max() else { return nil }
        return low...high
    }
    public var isStepsBelowBaseline: Bool {
        guard let steps = latestHealth?.steps, steps > 0, let baseline = baselineSteps else { return false }
        return Double(steps) < Double(baseline) * 0.8
    }
    public var needsAttention: Bool {
        hasEmergency || !isCheckedIn || !missedMedications.isEmpty || isStepsBelowBaseline
    }

    /// Things a caregiver may want to follow up on, in priority order.
    public var attentionItems: [String] {
        var items: [String] = []
        if hasEmergency { items.append("an open SOS alert") }
        if !isCheckedIn { items.append("no check-in yet today") }
        if !missedMedications.isEmpty { items.append("\(Self.list(missedMedications.map(\.name))) not yet taken") }
        if isStepsBelowBaseline { items.append("fewer steps than usual") }
        return items
    }

    /// Plain observations only. No interpretation of what the numbers mean medically.
    public var observations: [String] {
        var lines: [String] = []
        lines.append(isCheckedIn ? "\(firstName) has checked in today." : "\(firstName) has not checked in yet today.")
        if medicationsTotal == 0 {
            lines.append("No medications are set up yet.")
        } else {
            var line = "\(medicationsTaken) of \(medicationsTotal) medications are marked taken today."
            if !missedMedications.isEmpty { line += " Not yet taken: \(Self.list(missedMedications.map(\.name)))." }
            lines.append(line)
        }
        if let adherence, adherence.expected > 0 {
            lines.append("\(adherence.taken) of \(adherence.expected) doses marked taken over the past week.")
        }
        if let mood {
            var line = "Latest mood recorded: \(mood.rawValue)."
            if let moodNote, !moodNote.isEmpty { line += " Note: \"\(moodNote)\"" }
            lines.append(line)
        } else {
            lines.append("No mood has been recorded yet.")
        }
        guard let latest = latestHealth else {
            lines.append("No health data has been synced yet.")
            return lines
        }
        if latest.steps > 0 {
            var line = "\(latest.steps.formatted()) steps on the latest synced day"
            if let baselineSteps { line += ", compared with a \(baselineSteps.formatted())-step average on earlier days" }
            lines.append(line + ".")
        } else {
            lines.append("No step data was recorded on the latest synced day.")
        }
        if latest.sleepMinutes > 0 {
            var line = "\(Self.duration(minutes: latest.sleepMinutes)) of sleep recorded"
            if let averageSleepMinutes, healthHistory.count > 1 {
                line += " (recent average \(Self.duration(minutes: averageSleepMinutes)))"
            }
            lines.append(line + ".")
        }
        if latest.restingHeartRate > 0 {
            var line = "Resting heart rate \(latest.restingHeartRate) bpm"
            if let range = restingHeartRateRange, range.lowerBound != range.upperBound {
                line += " (\(range.lowerBound)–\(range.upperBound) bpm across synced days)"
            }
            lines.append(line + ".")
        }
        if hasEmergency { lines.append("An SOS alert is still open.") }
        return lines
    }

    public static func duration(minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)min"
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    private static func average(_ values: [Int]) -> Int? {
        let recorded = values.filter { $0 > 0 }
        guard !recorded.isEmpty else { return nil }
        return recorded.reduce(0, +) / recorded.count
    }

    private static func oneEntryPerDay(_ entries: [HealthSnapshot]) -> [HealthSnapshot] {
        Dictionary(grouping: entries) { CareRecords.dateOnly.string(from: $0.date) }
            .values
            .compactMap { day in day.first { $0.source == "healthkit" } ?? day.max { $0.date < $1.date } }
            .sorted { $0.date > $1.date }
    }

    private static func weeklyAdherence(medications: [Medication], events: [MedicationEvent],
                                        calendar: Calendar, now: Date) -> Adherence? {
        guard !medications.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }
        let medicationIDs = Set(medications.map(\.id))
        let recent = events.filter { medicationIDs.contains($0.medicationID) && $0.date >= windowStart && $0.date <= now }
        let firstDay = recent.map { calendar.startOfDay(for: $0.date) }.min() ?? today
        let trackedDays = (calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 1
        let latestPerDose = Dictionary(grouping: recent) {
            "\($0.medicationID)|\(calendar.startOfDay(for: $0.date).timeIntervalSince1970)"
        }.compactMapValues { $0.max { $0.date < $1.date } }
        let taken = latestPerDose.values.filter { $0.status == .taken }.count
        return Adherence(taken: taken, expected: medications.count * trackedDays)
    }
}
