import Foundation

/// How often a visit comes back. Medicines use weekdays instead, because they are a clock time each selected day.
public enum VisitRepeat: String, Codable, Equatable, Sendable, CaseIterable {
    case once
    case daily
    case weekly
    case biweekly
    case monthly

    public var label: String {
        switch self {
        case .once: "Does not repeat"
        case .daily: "Every day"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        }
    }
}

/// Which days a medicine or visit is active. An empty weekday list means every day. No end date means it keeps going.
public enum CareSchedule {
    /// Sunday is 1, matching `Calendar` weekday in the Gregorian calendar, through Saturday as 7.
    public static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func medicationIsDue(_ medication: Medication, on date: Date, timeZone: TimeZone) -> Bool {
        let calendar = gregorian(timeZone)
        if let endsOn = medication.endsOn, dayKey(date, calendar: calendar) > storedDay(endsOn) { return false }
        if medication.weekdays.isEmpty { return true }
        return medication.weekdays.contains(calendar.component(.weekday, from: date))
    }

    /// Extra line for a medicine that is not simply every day forever.
    public static func medicationScheduleText(_ medication: Medication) -> String? {
        guard !medication.weekdays.isEmpty || medication.endsOn != nil else { return nil }
        var parts: [String] = []
        if medication.weekdays.isEmpty {
            parts.append("Every day")
        } else {
            let names = medication.weekdays.sorted().compactMap { day in
                (1...7).contains(day) ? weekdaySymbols[day - 1] : nil
            }
            if !names.isEmpty { parts.append(names.joined(separator: ", ")) }
        }
        if let endsOn = medication.endsOn { parts.append("until \(endText(endsOn))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static func visitScheduleText(_ visit: Appointment) -> String? {
        guard visit.repeatRule != .once || visit.endsOn != nil else { return nil }
        var text = visit.repeatRule.label
        if let endsOn = visit.endsOn { text += " · until \(endText(endsOn))" }
        return text
    }

    /// The next time this visit happens, including one that started within the last hour.
    public static func nextOccurrence(of visit: Appointment, after now: Date, timeZone: TimeZone) -> Date? {
        let from = now.addingTimeInterval(-3600)
        return occurrences(of: visit, from: from, through: from.addingTimeInterval(370 * 24 * 3600), timeZone: timeZone, limit: 1).first
    }

    /// Future visit times to notify for, within the next two weeks.
    public static func notificationOccurrences(of visit: Appointment, now: Date, timeZone: TimeZone) -> [Date] {
        occurrences(of: visit, from: now.addingTimeInterval(1), through: now.addingTimeInterval(14 * 24 * 3600),
                    timeZone: timeZone, limit: 16)
            .filter { !isLogged($0, visit: visit) }
    }

    /// The latest visit time that already passed and has not been logged.
    public static func occurrenceNeedingLog(_ visit: Appointment, now: Date, timeZone: TimeZone,
                                            lookback: TimeInterval = 36 * 3600, grace: TimeInterval = 2 * 60) -> Date? {
        let ready = occurrences(of: visit, from: now.addingTimeInterval(-lookback), through: now.addingTimeInterval(-grace),
                                timeZone: timeZone, limit: 8)
        guard let latest = ready.last, !isLogged(latest, visit: visit) else { return nil }
        return latest
    }

    /// Dose times still ahead, for a medicine that is not every day forever. The open-ended daily case uses one repeating alert.
    public static func upcomingDoseTimes(_ medication: Medication, now: Date, timeZone: TimeZone, daysAhead: Int = 14) -> [Date] {
        let calendar = gregorian(timeZone)
        guard let clock = OfflineCatchUp.clock(from: medication.scheduledTime) else { return [] }
        var results: [Date] = []
        for offset in 0...daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
            var parts = calendar.dateComponents([.year, .month, .day], from: day)
            parts.hour = clock.hour
            parts.minute = clock.minute
            parts.second = 0
            parts.timeZone = timeZone
            guard let moment = calendar.date(from: parts), moment > now else { continue }
            guard medicationIsDue(medication, on: moment, timeZone: timeZone) else { continue }
            results.append(moment)
        }
        return results
    }

    public static func repeatsEveryDayForever(_ medication: Medication) -> Bool {
        medication.weekdays.isEmpty && medication.endsOn == nil
    }

    /// Calendar day stored as midnight UTC, so "Oct 12" does not shift when the phone's zone changes.
    public static func storedDay(from date: Date, timeZone: TimeZone) -> Date? {
        let key = dayKey(date, calendar: gregorian(timeZone))
        return CareRecords.dateOnly.date(from: key)
    }

    /// A stored day shown on a date picker in the senior's zone.
    public static func pickerDate(fromStored day: Date, timeZone: TimeZone) -> Date {
        let key = storedDay(day)
        let numbers = key.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3 else { return day }
        var parts = DateComponents()
        parts.year = numbers[0]
        parts.month = numbers[1]
        parts.day = numbers[2]
        return gregorian(timeZone).date(from: parts) ?? day
    }

    public static func weekdayList(from stored: String?) -> [Int] {
        guard let stored else { return [] }
        let days = stored.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...7).contains($0) }
        return Array(Set(days)).sorted()
    }

    public static func weekdayStorage(_ days: [Int]) -> String? {
        let clean = Array(Set(days.filter { (1...7).contains($0) })).sorted()
        guard !clean.isEmpty else { return nil }
        return clean.map(String.init).joined(separator: ",")
    }

    public static func occurrences(of visit: Appointment, from: Date, through: Date, timeZone: TimeZone, limit: Int = 16) -> [Date] {
        let calendar = gregorian(timeZone)
        guard var cursor = first(onOrAfter: from, visit: visit, calendar: calendar) else { return [] }
        var results: [Date] = []
        var steps = 0
        while cursor <= through, results.count < limit, steps < 500 {
            steps += 1
            if isAfterEnd(cursor, visit: visit, calendar: calendar) { break }
            results.append(cursor)
            if visit.repeatRule == .once { break }
            guard let next = advance(cursor, rule: visit.repeatRule, calendar: calendar), next > cursor else { break }
            cursor = next
        }
        return results
    }

    // MARK: - Private

    static func isLogged(_ occurrence: Date, visit: Appointment) -> Bool {
        if let loggedAt = visit.loggedAt { return abs(loggedAt.timeIntervalSince(occurrence)) < 90 }
        if visit.outcome != nil { return abs(visit.date.timeIntervalSince(occurrence)) < 90 }
        return false
    }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func storedDay(_ date: Date) -> String { CareRecords.dateOnly.string(from: date) }

    private static func endText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .gmt).month(.abbreviated).day().year())
    }

    private static func isAfterEnd(_ date: Date, visit: Appointment, calendar: Calendar) -> Bool {
        guard let endsOn = visit.endsOn else { return false }
        return dayKey(date, calendar: calendar) > storedDay(endsOn)
    }

    private static func first(onOrAfter from: Date, visit: Appointment, calendar: Calendar) -> Date? {
        if visit.date >= from { return visit.date }
        switch visit.repeatRule {
        case .once:
            return nil
        case .daily:
            return stepped(visit.date, from: from, days: 1, calendar: calendar)
        case .weekly:
            return stepped(visit.date, from: from, days: 7, calendar: calendar)
        case .biweekly:
            return stepped(visit.date, from: from, days: 14, calendar: calendar)
        case .monthly:
            let months = max(0, calendar.dateComponents([.month], from: visit.date, to: from).month ?? 0)
            guard var cursor = calendar.date(byAdding: .month, value: months, to: visit.date) else { return nil }
            if cursor < from { cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor }
            return cursor
        }
    }

    private static func stepped(_ anchor: Date, from: Date, days: Int, calendar: Calendar) -> Date? {
        let elapsed = from.timeIntervalSince(anchor)
        let jumps = max(0, Int(elapsed / (Double(days) * 86_400)))
        guard var cursor = calendar.date(byAdding: .day, value: jumps * days, to: anchor) else { return nil }
        var extra = 0
        while cursor < from, extra < 4 {
            guard let next = calendar.date(byAdding: .day, value: days, to: cursor) else { return nil }
            cursor = next
            extra += 1
        }
        return cursor
    }

    private static func advance(_ date: Date, rule: VisitRepeat, calendar: Calendar) -> Date? {
        switch rule {
        case .once: nil
        case .daily: calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: calendar.date(byAdding: .day, value: 7, to: date)
        case .biweekly: calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly: calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}
