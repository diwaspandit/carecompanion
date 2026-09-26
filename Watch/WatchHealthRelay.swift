import CareCore
import Foundation
import HealthKit
import WatchConnectivity
import WatchKit

/// Reads Apple Health on the watch and sends it to the paired iPhone.
/// Wear is sent about once a minute. Step, sleep, heart-rate and blood-pressure totals are sent with it every 15 minutes;
/// the iPhone writes those totals to the family database once an hour.
@MainActor
final class WatchHealthRelay {
    static let shared = WatchHealthRelay()

    private let healthStore = HKHealthStore()
    private var started = false
    private var ready = false
    private var publishing = false
    private var observersInstalled = false
    private var lastHistoryAt: Date?
    private var lastSentAt: Date?
    private var lastWorn: Bool?
    private var loop: Task<Void, Never>?

    /// A heart-rate sample this recent means the watch is on the wrist.
    private let wornWindow: TimeInterval = 15 * 60
    private let historyInterval: TimeInterval = 15 * 60

    private var sampleTypes: [HKSampleType] {
        [
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic)
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        Self.scheduleBackgroundRefresh()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.publish()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let next = Date().addingTimeInterval(15 * 60)
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: next, userInfo: nil) { _ in }
    }

    func publish() async {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }

        if !ready { await prepare() }
        let now = Date()
        let latest = await latestHeartDate()
        let worn = latest.map { now.timeIntervalSince($0) <= wornWindow } ?? false
        let historyDue = lastHistoryAt.map { now.timeIntervalSince($0) >= historyInterval } ?? true
        if !historyDue, let lastSentAt, lastWorn == worn, now.timeIntervalSince(lastSentAt) < 45 { return }

        var readings: [HealthReading]?
        var snapshots: [HealthSnapshot]?
        if historyDue, ready {
            if let collected = await collectHistory(endingAt: now) {
                readings = collected.readings
                snapshots = collected.snapshots
                lastHistoryAt = now
            }
        }
        lastSentAt = now
        lastWorn = worn
        send(WatchHealthReport(worn: worn, reportedAt: now, readings: readings, snapshots: snapshots))
    }

    private func prepare() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: Set(sampleTypes))
            ready = true
            installObservers()
        } catch {
            ready = false
        }
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        for type in sampleTypes {
            let frequency: HKUpdateFrequency = type == HKQuantityType(.heartRate) ? .immediate : .hourly
            healthStore.enableBackgroundDelivery(for: type, frequency: frequency) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                completion()
                guard error == nil else { return }
                Task { @MainActor in await WatchHealthRelay.shared.publish() }
            }
            healthStore.execute(query)
        }
    }

    private func send(_ report: WatchHealthReport) {
        WatchHealthSender.deliver(report.userInfo())
    }

    // MARK: - Health queries

    private func collectHistory(endingAt date: Date) async -> (readings: [HealthReading], snapshots: [HealthSnapshot])? {
        let calendar = Calendar.current
        let start = date.addingTimeInterval(-48 * 3600)
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date)) ?? date
        do {
            async let steps = hourlySteps(from: start, to: date, calendar: calendar)
            async let sleep = hourlySleep(from: start.addingTimeInterval(-12 * 3600), to: date, calendar: calendar)
            async let pulse = heartRateSamples(from: start, to: date)
            async let pressure = hourlyBloodPressure(from: start, to: date, calendar: calendar)
            async let dailySteps = dailySteps(from: firstDay, to: date, calendar: calendar)
            async let dailySleep = sleepMinutes(from: firstDay.addingTimeInterval(-12 * 3600), to: date, calendar: calendar)
            async let resting = restingHeartRate(from: firstDay, to: date, calendar: calendar)
            let samples = try await pulse
            let readings = try await HealthDayAggregator.hourlyReadings(
                seniorID: "watch", steps: steps, sleepMinutes: sleep,
                heartRate: HealthDayAggregator.averageHeartRateByHour(samples, calendar: calendar),
                bloodPressure: pressure,
                worn: HealthDayAggregator.wornByHour(samples.map(\.date), calendar: calendar),
                source: "watch")
            let snapshots = try await HealthDayAggregator.snapshots(
                seniorID: "watch", steps: dailySteps, sleepMinutes: dailySleep, restingHeartRate: resting,
                days: 7, endingAt: date, calendar: calendar, source: "watch")
            return (readings, snapshots)
        } catch {
            return nil
        }
    }

    private func latestHeartDate() async -> Date? {
        guard ready else { return nil }
        let samples = (try? await quantitySamples(HKQuantityType(.heartRate), from: Date().addingTimeInterval(-wornWindow), to: Date(),
                                                  limit: 1, newestFirst: true)) ?? []
        return samples.first?.endDate
    }

    private func hourlySteps(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let anchor = HealthDayAggregator.hourStart(for: start, calendar: calendar)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: anchor,
                                                    intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, results, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                var totals: [Date: Int] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    let count = Int(sum.doubleValue(for: .count()).rounded())
                    if count > 0 { totals[statistics.startDate] = count }
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    private func dailySteps(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                    return
                }
                var totals: [Date: Int] = [:]
                results?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let sum = statistics.sumQuantity() else { return }
                    let key = HealthDayAggregator.dayKey(for: statistics.startDate, calendar: calendar)
                    totals[key] = Int(sum.doubleValue(for: .count()).rounded())
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }

    private func heartRateSamples(from start: Date, to end: Date) async throws -> [HealthDayAggregator.Reading] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = try await quantitySamples(HKQuantityType(.heartRate), from: start, to: end, limit: HKObjectQueryNoLimit, newestFirst: false)
        return samples.map { HealthDayAggregator.Reading(date: $0.endDate, value: $0.quantity.doubleValue(for: unit)) }
    }

    private func restingHeartRate(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = try await quantitySamples(HKQuantityType(.restingHeartRate), from: start, to: end, limit: HKObjectQueryNoLimit, newestFirst: false)
        return HealthDayAggregator.latestValueByDay(
            samples.map { HealthDayAggregator.Reading(date: $0.endDate, value: $0.quantity.doubleValue(for: unit)) },
            calendar: calendar)
    }

    private func hourlyBloodPressure(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: (Int, Int)] {
        let unit = HKUnit.millimeterOfMercury()
        async let systolic = quantitySamples(HKQuantityType(.bloodPressureSystolic), from: start, to: end, limit: HKObjectQueryNoLimit, newestFirst: false)
        async let diastolic = quantitySamples(HKQuantityType(.bloodPressureDiastolic), from: start, to: end, limit: HKObjectQueryNoLimit, newestFirst: false)
        let pair = try await (systolic, diastolic)
        let reading = { (sample: HKQuantitySample) in
            HealthDayAggregator.Reading(date: sample.endDate, value: sample.quantity.doubleValue(for: unit))
        }
        return HealthDayAggregator.bloodPressureByHour(systolic: pair.0.map(reading), diastolic: pair.1.map(reading), calendar: calendar)
    }

    private func hourlySleep(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let split = try await sleepIntervals(from: start, to: end)
        let asleep = HealthDayAggregator.sleepMinutesByHour(split.asleep, calendar: calendar)
        let inBed = HealthDayAggregator.sleepMinutesByHour(split.inBed, calendar: calendar)
        return inBed.merging(asleep) { _, asleep in asleep }
    }

    private func sleepMinutes(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let split = try await sleepIntervals(from: start, to: end)
        return HealthDayAggregator.sleepMinutesByDay(asleep: split.asleep, inBed: split.inBed, calendar: calendar)
    }

    private func sleepIntervals(from start: Date, to end: Date) async throws -> (asleep: [HealthDayAggregator.Interval], inBed: [HealthDayAggregator.Interval]) {
        let samples = try await categorySamples(HKCategoryType(.sleepAnalysis), from: start, to: end)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let interval = { (sample: HKCategorySample) in HealthDayAggregator.Interval(start: sample.startDate, end: sample.endDate) }
        return (samples.filter { asleepValues.contains($0.value) }.map(interval),
                samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }.map(interval))
    }

    private func quantitySamples(_ type: HKQuantityType, from start: Date, to end: Date, limit: Int, newestFirst: Bool) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: !newestFirst)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(_ type: HKCategoryType, from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}

/// Watch Connectivity calls these replies on a background queue. They stay off the main actor so that does not crash the app.
private enum WatchHealthSender {
    static func deliver(_ info: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(info, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(info)
            })
        } else {
            WCSession.default.transferUserInfo(info)
        }
    }
}
