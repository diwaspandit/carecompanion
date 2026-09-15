import Foundation

/// Where a stored health value came from. Seeded demo values must never read as Apple Health data.
public enum HealthDataOrigin: Equatable, Sendable {
    case healthKit, deviceImport, manual, demo

    public init(source: String) {
        switch source {
        case "healthkit": self = .healthKit
        case "device_import": self = .deviceImport
        case "manual": self = .manual
        default: self = .demo
        }
    }

    /// Higher wins when one day has values from several sources.
    fileprivate var priority: Int {
        switch self {
        case .healthKit: 3
        case .deviceImport: 2
        case .manual: 1
        case .demo: 0
        }
    }
}

/// One senior's last seven days of health snapshots, summarized for the Health Timeline.
/// Observations only; nothing here interprets the values.
public struct HealthTrend: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let date: Date
        public let steps: Int
        public let sleepMinutes: Int
        public let restingHeartRate: Int
        public let origin: HealthDataOrigin
    }

    /// Oldest first, at most seven days.
    public let days: [Day]

    public init(snapshots: [HealthSnapshot], seniorID: String) {
        let bestPerDay = Dictionary(grouping: snapshots.filter { $0.seniorID == seniorID }, by: \.date)
            .compactMapValues { sameDay in
                sameDay.max { HealthDataOrigin(source: $0.source).priority < HealthDataOrigin(source: $1.source).priority }
            }
        days = bestPerDay.values
            .sorted { $0.date < $1.date }
            .suffix(7)
            .map { Day(date: $0.date, steps: $0.steps, sleepMinutes: $0.sleepMinutes,
                       restingHeartRate: $0.restingHeartRate, origin: HealthDataOrigin(source: $0.source)) }
    }

    public var latest: Day? { days.last }

    public var averageSleepHours: Double? {
        let nights = days.map(\.sleepMinutes).filter { $0 > 0 }
        guard !nights.isEmpty else { return nil }
        return Double(nights.reduce(0, +)) / Double(nights.count) / 60
    }

    public var restingHeartRateRange: ClosedRange<Int>? {
        let readings = days.map(\.restingHeartRate).filter { $0 > 0 }
        guard let low = readings.min(), let high = readings.max() else { return nil }
        return low...high
    }
}
