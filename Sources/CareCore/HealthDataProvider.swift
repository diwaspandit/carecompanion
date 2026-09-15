import Foundation

public enum HealthPermissionStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case authorized
    case restricted
}

/// Reads the signed-in senior's own health data (Apple Health in production).
public protocol HealthDataProvider: Sendable {
    func permissionStatus() async -> HealthPermissionStatus
    func requestPermission() async throws
    /// Daily snapshots for the seven local days ending on `date`, newest first. Days without data are omitted.
    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot]
    func startBackgroundSync() async throws
    func stopBackgroundSync() async
}

/// Day-bucketing rules for raw health samples. Pure so they are covered by `swift test`.
public enum HealthDayAggregator {
    public struct Interval: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    public struct Reading: Equatable, Sendable {
        public let date: Date
        public let value: Double

        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// The local calendar day of `date`, expressed as midnight UTC to match the database `date` column.
    public static func dayKey(for date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        return utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
    }

    /// Minutes asleep per day. Overlapping samples (iPhone and Apple Watch both recording) are merged
    /// so time is never double counted, and each sleep period counts toward the day it ended, so last
    /// night's sleep belongs to today. Days with no "asleep" samples fall back to time in bed.
    public static func sleepMinutesByDay(asleep: [Interval], inBed: [Interval], calendar: Calendar) -> [Date: Int] {
        let asleepTotals = minutesByEndDay(asleep, calendar: calendar)
        let inBedTotals = minutesByEndDay(inBed, calendar: calendar)
        return inBedTotals.merging(asleepTotals) { _, asleep in asleep }
    }

    /// The most recent reading on each day.
    public static func latestValueByDay(_ readings: [Reading], calendar: Calendar) -> [Date: Int] {
        Dictionary(grouping: readings) { dayKey(for: $0.date, calendar: calendar) }
            .compactMapValues { day in day.max { $0.date < $1.date }.map { Int($0.value.rounded()) } }
    }

    /// Combines per-day metrics into snapshots for the `days` local days ending on `end`, newest first.
    public static func snapshots(seniorID: String, steps: [Date: Int], sleepMinutes: [Date: Int],
                                 restingHeartRate: [Date: Int], days: Int = 7, endingAt end: Date,
                                 calendar: Calendar, source: String = "healthkit") -> [HealthSnapshot] {
        (0..<days).compactMap { offset -> HealthSnapshot? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = dayKey(for: day, calendar: calendar)
            let stepCount = steps[key] ?? 0
            let sleep = sleepMinutes[key] ?? 0
            let heartRate = restingHeartRate[key] ?? 0
            guard stepCount > 0 || sleep > 0 || heartRate > 0 else { return nil }
            return HealthSnapshot(id: "\(source)-\(seniorID)-\(CareRecords.dateOnly.string(from: key))",
                                  seniorID: seniorID, date: key, steps: stepCount, sleepMinutes: sleep,
                                  restingHeartRate: heartRate, source: source)
        }
    }

    static func merge(_ intervals: [Interval]) -> [Interval] {
        var merged: [Interval] = []
        for interval in intervals.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = Interval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func minutesByEndDay(_ intervals: [Interval], calendar: Calendar) -> [Date: Int] {
        var seconds: [Date: TimeInterval] = [:]
        for interval in merge(intervals) {
            seconds[dayKey(for: interval.end, calendar: calendar), default: 0] += interval.end.timeIntervalSince(interval.start)
        }
        return seconds.mapValues { Int(($0 / 60).rounded()) }
    }
}
