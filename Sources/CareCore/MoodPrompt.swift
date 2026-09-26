import Foundation

/// A mood check the senior still needs to answer. Morning and evening are the daily asks.
/// A family "ask now" stays up until a mood is saved after that moment.
public struct MoodPrompt: Equatable, Sendable {
    public let id: String
    /// When this ask became due. A mood saved at or after this time answers it.
    public let askedAt: Date

    public init(id: String, askedAt: Date) {
        self.id = id
        self.askedAt = askedAt
    }
}

public enum MoodPromptSchedule {
    public static let morningDefault = "9:00 AM"
    public static let eveningDefault = "6:00 PM"

    public static func due(now: Date, timeZone: TimeZone, morning: String, evening: String,
                           moodDates: [Date], askedAt: Date?) -> MoodPrompt? {
        if let askedAt, !moodDates.contains(where: { $0 >= askedAt }) {
            return MoodPrompt(id: "ask-\(Int(askedAt.timeIntervalSince1970))", askedAt: askedAt)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let slots = [morning, evening].compactMap { clock($0, on: now, calendar: calendar) }
            .filter { $0 <= now }
            .sorted()
        guard let slot = slots.last else { return nil }
        if moodDates.contains(where: { $0 >= slot }) { return nil }
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: slot)
        let id = String(format: "%04d%02d%02d-%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                        parts.hour ?? 0, parts.minute ?? 0)
        return MoodPrompt(id: id, askedAt: slot)
    }

    /// Today's date at the clock time in `text` ("9:00 AM"), in `calendar`'s time zone.
    public static func clock(_ text: String, on day: Date, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let parsed = formatter.date(from: text.uppercased()) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let time = utc.dateComponents([.hour, .minute], from: parsed)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = time.hour
        parts.minute = time.minute
        return calendar.date(from: parts)
    }
}
