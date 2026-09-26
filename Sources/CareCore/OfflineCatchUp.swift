import Foundation

/// Medicines and visits whose time passed while a phone or watch had no connection.
/// The app posts these once the account can be read again, so the dose or visit can still be logged.
public enum OfflineCatchUp {
    /// Wait this long after the scheduled moment so the on-time alert and the catch-up are not the same bell.
    public static let grace: TimeInterval = 2 * 60
    /// Visits older than this are left alone.
    public static let visitLookback: TimeInterval = 36 * 3600

    public static func medications(_ medications: [Medication], now: Date, timeZone: TimeZone) -> [Medication] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return medications.filter { medication in
            guard !medication.taken else { return false }
            if let until = medication.snoozeUntil, until > now { return false }
            guard CareSchedule.medicationIsDue(medication, on: now, timeZone: timeZone) else { return false }
            guard let due = dueDate(for: medication.scheduledTime, on: now, calendar: calendar) else { return false }
            if let createdAt = medication.createdAt, createdAt > due { return false }
            return now.timeIntervalSince(due) >= grace
        }
    }

    public static func visits(_ appointments: [Appointment], now: Date, timeZone: TimeZone) -> [Appointment] {
        appointments.compactMap { visit in
            guard let occurrence = CareSchedule.occurrenceNeedingLog(visit, now: now, timeZone: timeZone,
                                                                     lookback: visitLookback, grace: grace) else { return nil }
            var due = visit
            due.date = occurrence
            return due
        }
    }

    /// Clock time on the same local day as `now`. "8:00 AM" stays 8:00 in `calendar`'s time zone.
    public static func dueDate(for scheduledTime: String, on now: Date, calendar: Calendar) -> Date? {
        guard let clock = clock(from: scheduledTime) else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = clock.hour
        parts.minute = clock.minute
        parts.second = 0
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts)
    }

    static func clock(from scheduledTime: String) -> (hour: Int, minute: Int)? {
        let cleaned = scheduledTime
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .uppercased()
        let pieces = cleaned.split(separator: " ").map(String.init)
        guard pieces.count == 2 else { return nil }
        let hm = pieces[0].split(separator: ":").map(String.init)
        guard hm.count == 2, var hour = Int(hm[0]), let minute = Int(hm[1]) else { return nil }
        switch pieces[1] {
        case "PM" where hour < 12: hour += 12
        case "AM" where hour == 12: hour = 0
        case "AM", "PM": break
        default: return nil
        }
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        return (hour, minute)
    }
}
