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
    /// Hourly heart rate, blood pressure, steps and sleep for the two days ending on `date`.
    func readings(seniorID: String, endingAt date: Date) async throws -> [HealthReading]
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

    /// The start of the local hour containing `date`.
    public static func hourStart(for date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: parts) ?? date
    }

    /// Average heart rate in each hour.
    public static func averageHeartRateByHour(_ readings: [Reading], calendar: Calendar) -> [Date: Int] {
        Dictionary(grouping: readings) { hourStart(for: $0.date, calendar: calendar) }
            .compactMapValues { hour in
                let values = hour.map(\.value).filter { $0 > 0 }
                guard !values.isEmpty else { return nil }
                return Int((values.reduce(0, +) / Double(values.count)).rounded())
            }
    }

    /// The latest blood-pressure pair in each hour. Systolic and diastolic samples within two minutes are one reading.
    public static func bloodPressureByHour(systolic: [Reading], diastolic: [Reading], calendar: Calendar) -> [Date: (Int, Int)] {
        let diastolicSorted = diastolic.sorted { $0.date < $1.date }
        var latest: [Date: (date: Date, pair: (Int, Int))] = [:]
        for sample in systolic.sorted(by: { $0.date < $1.date }) {
            guard let match = diastolicSorted.min(by: {
                abs($0.date.timeIntervalSince(sample.date)) < abs($1.date.timeIntervalSince(sample.date))
            }), abs(match.date.timeIntervalSince(sample.date)) <= 120 else { continue }
            let hour = hourStart(for: sample.date, calendar: calendar)
            let pair = (Int(sample.value.rounded()), Int(match.value.rounded()))
            if latest[hour] == nil || sample.date > latest[hour]!.date {
                latest[hour] = (sample.date, pair)
            }
        }
        return latest.mapValues(\.pair)
    }

    /// Minutes asleep in each hour. A night that crosses an hour is split so time is not counted twice.
    public static func sleepMinutesByHour(_ intervals: [Interval], calendar: Calendar) -> [Date: Int] {
        var seconds: [Date: TimeInterval] = [:]
        for interval in merge(intervals) {
            var cursor = interval.start
            while cursor < interval.end {
                let hour = hourStart(for: cursor, calendar: calendar)
                let next = calendar.date(byAdding: .hour, value: 1, to: hour) ?? interval.end
                let sliceEnd = min(interval.end, next)
                if sliceEnd <= cursor { break }
                seconds[hour, default: 0] += sliceEnd.timeIntervalSince(cursor)
                cursor = sliceEnd
            }
        }
        return seconds.compactMapValues { value in
            let minutes = Int((value / 60).rounded())
            return minutes > 0 ? minutes : nil
        }
    }

    /// Minutes the watch was worn in an hour, plus the time of the last heart-rate sample in that hour.
    public struct WearHour: Equatable, Sendable {
        public let minutes: Int
        public let lastSample: Date

        public init(minutes: Int, lastSample: Date) {
            self.minutes = minutes
            self.lastSample = lastSample
        }
    }

    /// Heart-rate samples only exist while the watch is on the wrist. Each 15-minute slice with a sample counts as worn.
    public static func wornByHour(_ sampleDates: [Date], calendar: Calendar) -> [Date: WearHour] {
        var quarters: [Date: Set<Int>] = [:]
        var lastInHour: [Date: Date] = [:]
        for date in sampleDates {
            let hour = hourStart(for: date, calendar: calendar)
            quarters[hour, default: []].insert(calendar.component(.minute, from: date) / 15)
            if lastInHour[hour] == nil || date > lastInHour[hour]! {
                lastInHour[hour] = date
            }
        }
        var result: [Date: WearHour] = [:]
        for (hour, slices) in quarters {
            guard let last = lastInHour[hour] else { continue }
            result[hour] = WearHour(minutes: min(60, slices.count * 15), lastSample: last)
        }
        return result
    }

    public static func hourlyReadings(seniorID: String, steps: [Date: Int], sleepMinutes: [Date: Int],
                                      heartRate: [Date: Int], bloodPressure: [Date: (Int, Int)],
                                      worn: [Date: WearHour] = [:],
                                      source: String = "healthkit") -> [HealthReading] {
        var readings: [HealthReading] = []
        let stamp = ISO8601DateFormatter()
        func add(_ kind: HealthReadingKind, _ hour: Date, _ value: Double, _ secondary: Double? = nil) {
            let id = "\(source)-\(seniorID)-\(kind.rawValue)-\(stamp.string(from: hour))"
            readings.append(HealthReading(id: id, seniorID: seniorID, recordedAt: hour, kind: kind,
                                          value: value, valueSecondary: secondary, source: source))
        }
        for (hour, count) in steps where count > 0 { add(.steps, hour, Double(count)) }
        for (hour, minutes) in sleepMinutes where minutes > 0 { add(.sleep, hour, Double(minutes)) }
        for (hour, bpm) in heartRate where bpm > 0 { add(.heartRate, hour, Double(bpm)) }
        for (hour, pair) in bloodPressure where pair.0 > 0 {
            add(.bloodPressure, hour, Double(pair.0), Double(pair.1))
        }
        for (hour, wear) in worn where wear.minutes > 0 {
            add(.worn, hour, Double(wear.minutes), wear.lastSample.timeIntervalSince1970)
        }
        return readings.sorted { $0.recordedAt > $1.recordedAt }
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

/// The watch's live on-wrist signal. One row per senior, updated as the watch reports, separate from the hourly totals.
public enum WatchPresence {
    /// A true report older than this is treated as off, so a watch that stopped sending does not stay "on".
    public static let freshInterval: TimeInterval = 25 * 60
    /// Far enough ahead that the live row stays in the recent-readings query, which keeps the newest rows.
    public static let recordedAt = Date(timeIntervalSince1970: 4_102_444_800)

    public static func isOnWrist(value: Double, reportedAt: Date, now: Date) -> Bool {
        value >= 1 && now.timeIntervalSince(reportedAt) <= freshInterval
    }

    public static func reading(seniorID: String, worn: Bool, reportedAt: Date) -> HealthReading {
        HealthReading(id: "watch-presence-\(seniorID)", seniorID: seniorID, recordedAt: recordedAt,
                      kind: .presence, value: worn ? 1 : 0, valueSecondary: reportedAt.timeIntervalSince1970,
                      source: "watch")
    }
}

/// Health totals go to the database once an hour. Wear status does not use this gate.
public enum HealthUploadSchedule {
    public static let interval: TimeInterval = 60 * 60
    /// A watch reading set older than this is stale, so the phone may read its own Health store instead.
    public static let watchFreshInterval: TimeInterval = 3 * 60 * 60
    private static let key = "com.carecompanion.health.lastDatabaseUpload"

    public static func shouldUpload(lastUpload: Date?, now: Date) -> Bool {
        guard let lastUpload else { return true }
        return now.timeIntervalSince(lastUpload) >= interval
    }

    public static func lastUpload() -> Date? {
        let stamp = UserDefaults.standard.double(forKey: key)
        return stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    public static func markUploaded(_ date: Date) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: key)
    }

    public static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// What the watch sends the paired iPhone. Readings are omitted on a wear-only update.
public struct WatchHealthReport: Codable, Equatable, Sendable {
    public var worn: Bool
    public var reportedAt: Date
    public var readings: [HealthReading]?
    public var snapshots: [HealthSnapshot]?

    public static let messageKind = "watchHealth"

    public init(worn: Bool, reportedAt: Date, readings: [HealthReading]? = nil, snapshots: [HealthSnapshot]? = nil) {
        self.worn = worn
        self.reportedAt = reportedAt
        self.readings = readings
        self.snapshots = snapshots
    }

    public func userInfo() -> [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return ["kind": Self.messageKind] }
        return ["kind": Self.messageKind, "payload": data]
    }

    public init?(userInfo: [String: Any]) {
        guard (userInfo["kind"] as? String) == Self.messageKind,
              let data = userInfo["payload"] as? Data,
              let report = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = report
    }

    public func stamped(seniorID: String) -> WatchHealthReport {
        WatchHealthReport(worn: worn, reportedAt: reportedAt,
                          readings: readings?.map { $0.assigned(to: seniorID) },
                          snapshots: snapshots?.map { $0.assigned(to: seniorID) })
    }
}
