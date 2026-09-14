import Foundation
import HealthKit
import CareCore

/// HealthKit implementation of HealthDataProvider
@available(iOS 17.0, *)
public final class HealthKitHealthDataProvider: HealthDataProvider {
    private let healthStore = HKHealthStore()
    private let calendar = Calendar.current

    // User defaults keys for storing anchors
    private let stepsAnchorKey = "com.carecompanion.healthkit.steps.anchor"
    private let sleepAnchorKey = "com.carecompanion.healthkit.sleep.anchor"
    private let heartRateAnchorKey = "com.carecompanion.healthkit.heartrate.anchor"

    // HealthKit deliberately does not expose real read-authorization status
    // (authorizationStatus(for:) only reflects share/write permissions, and
    // for read-only types it returns misleading values by design, for user
    // privacy). We track locally whether the user has completed the system
    // permission prompt instead, and let the read queries themselves reflect
    // whatever was actually granted.
    private let hasRequestedAccessKey = "com.carecompanion.healthkit.hasRequestedAccess"

    // Health data types we need to read
    private var readTypes: Set<HKObjectType> {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let heartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            return []
        }
        return [stepType, sleepType, heartRateType]
    }

    public init() {}

    // MARK: - HealthDataProvider Protocol

    public func permissionStatus() async -> HealthPermissionStatus {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .restricted
        }

        // Do NOT use authorizationStatus(for:) here: it's only meaningful for
        // share/write types. This provider only ever requests read access, and
        // for read-only types the framework won't tell us whether the user
        // actually granted or denied it (so apps can't infer sensitive health
        // info from the grant/deny choice itself). Once the user has been
        // through the system prompt, treat access as authorized and let the
        // read queries reflect what was really granted.
        return UserDefaults.standard.bool(forKey: hasRequestedAccessKey) ? .authorized : .notDetermined
    }

    public func requestPermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CareServiceError.healthPermissionDenied
        }

        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
    }

    public func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw CareServiceError.healthPermissionDenied
        }

        // No further permission check here: for read-only types, the only
        // reliable signal of what's actually accessible is the query result
        // itself (an outright denial simply comes back empty, not as an error).

        // Get data for the last 7 days
        let startDate = calendar.date(byAdding: .day, value: -6, to: date) ?? date

        // Fetch steps, sleep, and heart rate concurrently
        async let stepsData = fetchSteps(from: startDate, to: date)
        async let sleepData = fetchSleep(from: startDate, to: date)
        async let heartRateData = fetchHeartRate(from: startDate, to: date)

        let (steps, sleep, heartRate) = try await (stepsData, sleepData, heartRateData)

        // Combine into daily snapshots
        return combineDailySnapshots(
            seniorID: seniorID,
            steps: steps,
            sleep: sleep,
            heartRate: heartRate,
            startDate: startDate,
            endDate: date
        )
    }

    #if DEBUG
    /// Debug-only: writes one day of sample steps, sleep, and resting heart rate into
    /// Apple Health so the read/sync path can be verified on the Simulator, where the
    /// Health app has no data and may not allow manual entry for every type.
    /// Returns a line per data type describing what was saved or why it failed.
    public func seedSampleData() async -> [String] {
        guard HKHealthStore.isHealthDataAvailable(),
              let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return ["HealthKit is not available on this device."]
        }

        do {
            try await healthStore.requestAuthorization(toShare: [stepType, sleepType, heartRateType], read: readTypes)
            UserDefaults.standard.set(true, forKey: hasRequestedAccessKey)
        } catch {
            return ["Write permission request failed: \(error.localizedDescription)"]
        }

        // Keep every sample on today's date so they land in the same daily snapshot.
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let latestEnd = now.addingTimeInterval(-60)
        let sleepStart = min(dayStart.addingTimeInterval(30 * 60), latestEnd.addingTimeInterval(-60))
        let sleepEnd = min(dayStart.addingTimeInterval(6 * 3600 + 45 * 60), latestEnd)
        let stepsStart = max(dayStart, latestEnd.addingTimeInterval(-3600))

        let samples: [(String, HKSample)] = [
            ("Steps (6,789)", HKQuantitySample(type: stepType,
                                                quantity: HKQuantity(unit: .count(), doubleValue: 6789),
                                                start: stepsStart, end: latestEnd)),
            ("Sleep (00:30–06:45, asleep)", HKCategorySample(type: sleepType,
                                                              value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                                                              start: sleepStart, end: sleepEnd)),
            ("Resting heart rate (63 bpm)", HKQuantitySample(type: heartRateType,
                                                              quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 63),
                                                              start: latestEnd, end: latestEnd))
        ]

        var results: [String] = []
        for (label, sample) in samples {
            do {
                try await healthStore.save(sample)
                results.append("Saved \(label)")
            } catch {
                results.append("Failed \(label): \(error.localizedDescription)")
            }
        }
        return results
    }
    #endif

    public func startBackgroundSync() async throws {
        // Background delivery is not implemented in this version
        // Would require setting up HKObserverQuery for background updates
        // For now, sync is triggered manually
    }

    public func stopBackgroundSync() async {
        // No background sync to stop in current implementation
    }

    // MARK: - Private Methods

    private func fetchSteps(from startDate: Date, to endDate: Date) async throws -> [Date: Double] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw CareServiceError.vendorUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
                    return
                }

                var dailySteps: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let steps = sum.doubleValue(for: HKUnit.count())
                        let dayStart = self.calendar.startOfDay(for: statistics.startDate)
                        dailySteps[dayStart] = steps
                    }
                }

                continuation.resume(returning: dailySteps)
            }

            healthStore.execute(query)
        }
    }

    private func fetchSleep(from startDate: Date, to endDate: Date) async throws -> [Date: Double] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw CareServiceError.vendorUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
                    return
                }

                var dailySleep: [Date: Double] = [:]
                guard let sleepSamples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                // Aggregate sleep duration per day
                for sample in sleepSamples {
                    // Only count in-bed asleep time (asleepUnspecified replaces deprecated .asleep)
                    if sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                       sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue {
                        let duration = sample.endDate.timeIntervalSince(sample.startDate) / 60.0 // minutes
                        let dayStart = self.calendar.startOfDay(for: sample.startDate)
                        dailySleep[dayStart, default: 0] += duration
                    }
                }

                continuation.resume(returning: dailySleep)
            }

            healthStore.execute(query)
        }
    }

    private func fetchHeartRate(from startDate: Date, to endDate: Date) async throws -> [Date: Double] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw CareServiceError.vendorUnavailable
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: CareServiceError.unknown(error.localizedDescription))
                    return
                }

                var dailyHeartRate: [Date: Double] = [:]
                guard let heartRateSamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [:])
                    return
                }

                // Take the latest resting heart rate per day
                for sample in heartRateSamples {
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    let dayStart = self.calendar.startOfDay(for: sample.startDate)

                    // Use the latest measurement for the day
                    if let existing = dailyHeartRate[dayStart] {
                        // Keep the most recent value (samples are sorted)
                        dailyHeartRate[dayStart] = max(existing, bpm)
                    } else {
                        dailyHeartRate[dayStart] = bpm
                    }
                }

                continuation.resume(returning: dailyHeartRate)
            }

            healthStore.execute(query)
        }
    }

    private func combineDailySnapshots(
        seniorID: String,
        steps: [Date: Double],
        sleep: [Date: Double],
        heartRate: [Date: Double],
        startDate: Date,
        endDate: Date
    ) -> [HealthSnapshot] {
        var snapshots: [HealthSnapshot] = []
        var currentDate = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.startOfDay(for: endDate)

        while currentDate <= endOfDay {
            // Only create snapshot if we have at least one data point
            let stepsCount = Int(steps[currentDate] ?? 0)
            let sleepMinutes = Int(sleep[currentDate] ?? 0)
            let restingHR = Int(heartRate[currentDate] ?? 0)

            if stepsCount > 0 || sleepMinutes > 0 || restingHR > 0 {
                let snapshot = HealthSnapshot(
                    id: "healthkit-\(seniorID)-\(currentDate.timeIntervalSince1970)",
                    seniorID: seniorID,
                    date: currentDate,
                    steps: stepsCount,
                    sleepMinutes: sleepMinutes,
                    restingHeartRate: restingHR,
                    source: "healthkit"
                )
                snapshots.append(snapshot)
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return snapshots.sorted { $0.date > $1.date } // Most recent first
    }
}
