import XCTest
@testable import CareCore

/// Health data must only ever come from the senior's own device, and never in demo mode.
@MainActor final class HealthSyncEligibilityTests: XCTestCase {
    private func state(linkedTo linkedProfile: String?, signedInAs profile: String?,
                       provider: (any HealthDataProvider)? = DemoHealthDataProvider()) async throws -> AppState {
        let repository = DemoCareRepository()
        var maya = repository.snapshot.seniors[0]
        maya.profileID = linkedProfile
        try await repository.updateSenior(maya)
        return AppState(repository: repository, healthProvider: provider, currentProfileID: profile)
    }

    func testDemoModeHasNoHealthSync() async throws {
        let state = try await state(linkedTo: nil, signedInAs: nil, provider: nil)
        XCTAssertEqual(state.healthSyncEligibility, .unavailableInDemo)
    }

    func testFamilyDeviceIsNotAllowedToSyncIntoSenior() async throws {
        let state = try await state(linkedTo: "profile-maya", signedInAs: "profile-diwas")
        XCTAssertEqual(state.healthSyncEligibility, .notLinkedSenior)
    }

    func testUnlinkedSeniorIsNotAllowedToSync() async throws {
        let state = try await state(linkedTo: nil, signedInAs: "profile-maya")
        XCTAssertEqual(state.healthSyncEligibility, .notLinkedSenior)
    }

    func testLinkedSeniorDeviceCanSync() async throws {
        let state = try await state(linkedTo: "profile-maya", signedInAs: "profile-maya")
        XCTAssertEqual(state.healthSyncEligibility, .allowed)
    }

    func testSyncFromFamilyDeviceWritesNothing() async throws {
        let state = try await state(linkedTo: "profile-maya", signedInAs: "profile-diwas",
                                    provider: FixedHealthProvider(source: "healthkit"))
        await state.syncHealthData()
        XCTAssertFalse(state.snapshot.health.contains { $0.source == "healthkit" })
        XCTAssertEqual(state.healthSyncStatus.healthData, .idle)
    }

    func testRequestingPermissionFromFamilyDeviceIsUnauthorized() async throws {
        let state = try await state(linkedTo: "profile-maya", signedInAs: "profile-diwas")
        do {
            try await state.requestHealthPermissions()
            XCTFail("family device must not request HealthKit permission for the senior")
        } catch {
            XCTAssertEqual(error as? CareServiceError, .unauthorized)
        }
    }

    func testSeniorProfileLinkIsMappedFromRecords() throws {
        let row = AccountSeniorRow(id: "s1", accountID: "a1", profileID: "profile-maya", name: "Maya Sharma",
                                   age: 74, city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu")
        let json = #"{"id":"s1","account_id":"a1","profile_id":null,"name":"Maya","age":74,"city":"","time_zone_identifier":"UTC"}"#
        XCTAssertNil(try JSONDecoder().decode(AccountSeniorRow.self, from: Data(json.utf8)).profileID)
        let records = CareRecords(
            account: CareAccountRow(id: "a1", kind: "family", name: "Sharma family", inviteCode: "ABCD1234"),
            members: [], seniors: [row], checkIns: [], moods: [], medications: [], medicationEvents: [],
            health: [], appointments: [], alerts: [])
        XCTAssertEqual(try records.snapshot(now: Date()).seniors.first?.profileID, "profile-maya")
    }
}

final class HealthTrendTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let end = Date(timeIntervalSince1970: 1_788_998_400)

    private func snapshot(_ daysAgo: Int, steps: Int = 3000, sleep: Int = 420, heart: Int = 70,
                          source: String = "healthkit", senior: String = "maya") -> HealthSnapshot {
        HealthSnapshot(id: "\(senior)-\(daysAgo)-\(source)", seniorID: senior,
                       date: end.addingTimeInterval(-Double(daysAgo) * day),
                       steps: steps, sleepMinutes: sleep, restingHeartRate: heart, source: source)
    }

    func testDaysAreOldestFirstAndLimitedToSeven() {
        let trend = HealthTrend(snapshots: (0..<10).map { snapshot($0, steps: $0) }, seniorID: "maya")
        XCTAssertEqual(trend.days.map(\.steps), [6, 5, 4, 3, 2, 1, 0])
    }

    func testIgnoresOtherSeniors() {
        let trend = HealthTrend(snapshots: [snapshot(0), snapshot(1, senior: "ramesh")], seniorID: "maya")
        XCTAssertEqual(trend.days.count, 1)
    }

    func testAverageSleepHoursSkipsDaysWithoutSleep() {
        let trend = HealthTrend(snapshots: [snapshot(0, sleep: 360), snapshot(1, sleep: 420), snapshot(2, sleep: 0)],
                                seniorID: "maya")
        XCTAssertEqual(trend.averageSleepHours!, 6.5, accuracy: 0.001)
    }

    func testHeartRateRangeSkipsMissingReadings() {
        let trend = HealthTrend(snapshots: [snapshot(0, heart: 74), snapshot(1, heart: 0), snapshot(2, heart: 67)],
                                seniorID: "maya")
        XCTAssertEqual(trend.restingHeartRateRange, 67...74)
    }

    func testEmptyTrendHasNoSummaries() {
        let trend = HealthTrend(snapshots: [], seniorID: "maya")
        XCTAssertTrue(trend.days.isEmpty)
        XCTAssertNil(trend.averageSleepHours)
        XCTAssertNil(trend.restingHeartRateRange)
        XCTAssertNil(trend.latest)
    }

    func testSameDayPrefersHealthKitOverManualOverDemo() {
        let trend = HealthTrend(snapshots: [
            snapshot(0, steps: 1, source: "Demo data"),
            snapshot(0, steps: 2, source: "manual"),
            snapshot(0, steps: 3, source: "healthkit"),
            snapshot(1, steps: 4, source: "demo"),
            snapshot(1, steps: 5, source: "manual")
        ], seniorID: "maya")
        XCTAssertEqual(trend.days.map(\.steps), [5, 3])
        XCTAssertEqual(trend.latest?.origin, .healthKit)
    }

    func testOriginsAreClassifiedFromStoredSource() {
        XCTAssertEqual(HealthDataOrigin(source: "healthkit"), .healthKit)
        XCTAssertEqual(HealthDataOrigin(source: "manual"), .manual)
        XCTAssertEqual(HealthDataOrigin(source: "demo"), .demo)
        XCTAssertEqual(HealthDataOrigin(source: "Demo data"), .demo)
        XCTAssertEqual(HealthDataOrigin(source: "device_import"), .deviceImport)
    }
}

private struct FixedHealthProvider: HealthDataProvider {
    let source: String
    func permissionStatus() async -> HealthPermissionStatus { .authorized }
    func requestPermission() async throws {}
    func snapshots(seniorID: String, endingAt date: Date) async throws -> [HealthSnapshot] {
        [HealthSnapshot(id: "fixed", seniorID: seniorID, date: date, steps: 1, sleepMinutes: 1,
                        restingHeartRate: 1, source: source)]
    }
    func startBackgroundSync() async throws {}
    func stopBackgroundSync() async {}
}
