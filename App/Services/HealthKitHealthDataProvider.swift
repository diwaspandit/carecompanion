import CareCore
import Foundation
import HealthKit

/// Reads steps, sleep and resting heart rate from Apple Health on the senior's own iPhone.
final class HealthKitHealthDataProvider: HealthDataProvider, @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let lock = NSLock()
    private var observerQueries: [HKObserverQuery] = []

    // HealthKit never reveals whether read access was granted (so apps can't infer health facts
    // from a denial). We remember that the system prompt was shown and let queries return what
    // was actually shared.
    private let hasRequestedAccessKey = "com.carecompanion.healthkit.hasRequestedAccess"

    private var sampleTypes: [HKSampleType] {
        [
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.restingHeartRate)
        ]
    }

    func permissionStatus() async -> HealthPermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        return UserDefaults.standard.bool(forKey: hasRequestedAccessKey) ? .authorized : .notDetermined
    }

    func requestPermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CareServiceError.healthPermissionDenied }
        try await healthStore.requestAuthorization(toShare: [], read: Set(sampleTypes))
        UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
    }

    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        guard HKHealthStore.isHealthDataAvailable() else { throw CareServiceError.healthPermissionDenied }
        let calendar = Calendar.current
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date)) ?? date

        async let steps = dailySteps(from: firstDay, to: date, calendar: calendar)
        // Sleep that ends on the first day started the evening before.
        async let sleep = sleepMinutes(from: firstDay.addingTimeInterval(-12 * 3600), to: date, calendar: calendar)
        async let heartRate = restingHeartRate(from: firstDay, to: date, calendar: calendar)

        return try await HealthDayAggregator.snapshots(
            seniorID: seniorID, steps: steps, sleepMinutes: sleep, restingHeartRate: heartRate,
            days: 7, endingAt: date, calendar: calendar)
    }

    func startBackgroundSync() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CareServiceError.healthPermissionDenied }
        await stopObserverQueries()
        for type in sampleTypes {
            try await healthStore.enableBackgroundDelivery(for: type, frequency: .hourly)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                if error == nil {
                    NotificationCenter.default.post(name: .healthKitDataAvailable, object: nil)
                }
                completionHandler()
            }
            healthStore.execute(query)
            lock.withLock { observerQueries.append(query) }
        }
    }

    func stopBackgroundSync() async {
        await stopObserverQueries()
        try? await healthStore.disableAllBackgroundDelivery()
    }

    // MARK: - Queries

    private func dailySteps(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, results, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
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

    private func sleepMinutes(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let samples = try await categorySamples(HKCategoryType(.sleepAnalysis), from: start, to: end)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let interval = { (sample: HKCategorySample) in HealthDayAggregator.Interval(start: sample.startDate, end: sample.endDate) }
        return HealthDayAggregator.sleepMinutesByDay(
            asleep: samples.filter { asleepValues.contains($0.value) }.map(interval),
            inBed: samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }.map(interval),
            calendar: calendar)
    }

    private func restingHeartRate(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let type = HKQuantityType(.restingHeartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
        return HealthDayAggregator.latestValueByDay(
            samples.map { HealthDayAggregator.Reading(date: $0.endDate, value: $0.quantity.doubleValue(for: beatsPerMinute)) },
            calendar: calendar)
    }

    private func categorySamples(_ type: HKCategoryType, from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, samples, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples as? [HKCategorySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func stopObserverQueries() async {
        let queries = lock.withLock {
            defer { observerQueries.removeAll() }
            return observerQueries
        }
        queries.forEach(healthStore.stop)
    }

    #if DEBUG
    /// Debug builds only: writes a week of plausible samples into the Simulator's Health store so the
    /// read → sync → dashboard path can be exercised where the Health app has no data.
    func writeSimulatorSampleWeek() async -> String {
        guard HKHealthStore.isHealthDataAvailable() else { return "Health data isn't available on this device." }
        let stepType = HKQuantityType(.stepCount)
        let sleepType = HKCategoryType(.sleepAnalysis)
        let heartType = HKQuantityType(.restingHeartRate)
        do {
            try await healthStore.requestAuthorization(toShare: [stepType, sleepType, heartType], read: Set(sampleTypes))
            UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
        } catch {
            return "Write permission failed: \(error.localizedDescription)"
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var samples: [HKSample] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wake = day.addingTimeInterval(Double(6 * 3600 + (offset * 7 % 50) * 60))
            if wake < now {
                let bedtime = wake.addingTimeInterval(-Double(6 * 3600 + (offset * 13 % 90) * 60))
                samples.append(HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                                start: bedtime, end: wake))
            }
            let walkEnd = min(day.addingTimeInterval(18 * 3600), now.addingTimeInterval(-60))
            if walkEnd > day.addingTimeInterval(8 * 3600) {
                let steps = Double(2600 + (offset * 811) % 3400)
                samples.append(HKQuantitySample(type: stepType, quantity: HKQuantity(unit: .count(), doubleValue: steps),
                                                start: day.addingTimeInterval(8 * 3600), end: walkEnd))
                let bpm = Double(62 + (offset * 3) % 9)
                samples.append(HKQuantitySample(type: heartType,
                                                quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: bpm),
                                                start: walkEnd, end: walkEnd))
            }
        }
        do {
            try await healthStore.save(samples)
            return "Wrote \(samples.count) Apple Health samples for the past week."
        } catch {
            return "Couldn't write samples: \(error.localizedDescription)"
        }
    }
    #endif
}
