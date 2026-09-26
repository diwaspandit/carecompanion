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
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRate),
            HKQuantityType(.bloodPressureSystolic),
            HKQuantityType(.bloodPressureDiastolic)
        ]
    }

    func permissionStatus() async -> HealthPermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else { return .restricted }
        return UserDefaults.standard.bool(forKey: hasRequestedAccessKey) ? .authorized : .notDetermined
    }

    func requestPermission() async throws {
        try await ensureAuthorization()
    }

    /// Asks for every type we read. Safe to call again: Health only prompts for types not decided yet.
    private func ensureAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw CareServiceError.healthPermissionDenied }
        try await healthStore.requestAuthorization(toShare: [], read: Set(sampleTypes))
        UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
    }

    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        try await ensureAuthorization()
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

    func readings(seniorID: String, endingAt date: Date) async throws -> [HealthReading] {
        try await ensureAuthorization()
        let calendar = Calendar.current
        let start = date.addingTimeInterval(-48 * 3600)
        async let steps = hourlySteps(from: start, to: date, calendar: calendar)
        async let sleep = hourlySleep(from: start.addingTimeInterval(-12 * 3600), to: date, calendar: calendar)
        async let pulse = heartRateSamples(from: start, to: date)
        async let pressure = hourlyBloodPressure(from: start, to: date, calendar: calendar)
        let samples = try await pulse
        return try await HealthDayAggregator.hourlyReadings(
            seniorID: seniorID, steps: steps, sleepMinutes: sleep,
            heartRate: HealthDayAggregator.averageHeartRateByHour(samples, calendar: calendar),
            bloodPressure: pressure,
            worn: HealthDayAggregator.wornByHour(samples.map(\.date), calendar: calendar))
    }

    func startBackgroundSync() async throws {
        try await ensureAuthorization()
        await stopObserverQueries()
        for type in sampleTypes {
            let frequency: HKUpdateFrequency = type == HKQuantityType(.heartRate) ? .immediate : .hourly
            try await healthStore.enableBackgroundDelivery(for: type, frequency: frequency)
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

    private func hourlySteps(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let anchor = HealthDayAggregator.hourStart(for: start, calendar: calendar)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: anchor,
                                                    intervalComponents: DateComponents(hour: 1))
            query.initialResultsHandler = { _, results, error in
                if let error, (error as? HKError)?.code != .errorNoData {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
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

    private func hourlySleep(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: Int] {
        let samples = try await categorySamples(HKCategoryType(.sleepAnalysis), from: start, to: end)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let interval = { (sample: HKCategorySample) in HealthDayAggregator.Interval(start: sample.startDate, end: sample.endDate) }
        let asleep = HealthDayAggregator.sleepMinutesByHour(samples.filter { asleepValues.contains($0.value) }.map(interval), calendar: calendar)
        let inBed = HealthDayAggregator.sleepMinutesByHour(
            samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }.map(interval), calendar: calendar)
        return inBed.merging(asleep) { _, asleep in asleep }
    }

    private func heartRateSamples(from start: Date, to end: Date) async throws -> [HealthDayAggregator.Reading] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = try await quantitySamples(HKQuantityType(.heartRate), from: start, to: end)
        return samples.map {
            HealthDayAggregator.Reading(date: $0.endDate, value: $0.quantity.doubleValue(for: unit))
        }
    }

    private func hourlyBloodPressure(from start: Date, to end: Date, calendar: Calendar) async throws -> [Date: (Int, Int)] {
        let unit = HKUnit.millimeterOfMercury()
        async let systolic = quantitySamples(HKQuantityType(.bloodPressureSystolic), from: start, to: end)
        async let diastolic = quantitySamples(HKQuantityType(.bloodPressureDiastolic), from: start, to: end)
        let pair = try await (systolic, diastolic)
        let reading = { (sample: HKQuantitySample) in
            HealthDayAggregator.Reading(date: sample.endDate, value: sample.quantity.doubleValue(for: unit))
        }
        return HealthDayAggregator.bloodPressureByHour(
            systolic: pair.0.map(reading), diastolic: pair.1.map(reading), calendar: calendar)
    }

    private func quantitySamples(_ type: HKQuantityType, from start: Date, to end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
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
        let pulseType = HKQuantityType(.heartRate)
        let systolicType = HKQuantityType(.bloodPressureSystolic)
        let diastolicType = HKQuantityType(.bloodPressureDiastolic)
        do {
            try await healthStore.requestAuthorization(
                toShare: [stepType, sleepType, heartType, pulseType, systolicType, diastolicType], read: Set(sampleTypes))
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
                let beats = HKUnit.count().unitDivided(by: .minute())
                samples.append(HKQuantitySample(type: heartType, quantity: HKQuantity(unit: beats, doubleValue: bpm),
                                                start: walkEnd, end: walkEnd))
                samples.append(HKQuantitySample(type: pulseType, quantity: HKQuantity(unit: beats, doubleValue: bpm + 8),
                                                start: walkEnd.addingTimeInterval(-3600), end: walkEnd.addingTimeInterval(-3600)))
                let pressure = HKUnit.millimeterOfMercury()
                samples.append(HKQuantitySample(type: systolicType, quantity: HKQuantity(unit: pressure, doubleValue: 122),
                                                start: walkEnd, end: walkEnd))
                samples.append(HKQuantitySample(type: diastolicType, quantity: HKQuantity(unit: pressure, doubleValue: 78),
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
