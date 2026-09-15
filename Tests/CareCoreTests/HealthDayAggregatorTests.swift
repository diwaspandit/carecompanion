import XCTest
@testable import CareCore

final class HealthDayAggregatorTests: XCTestCase {
    private let kathmandu = TimeZone(identifier: "Asia/Kathmandu")!
    private let chicago = TimeZone(identifier: "America/Chicago")!

    private func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func key(_ day: String) -> Date {
        CareRecords.dateOnly.date(from: day)!
    }

    func testDayKeyUsesLocalDayNotUTC() {
        // 00:30 on the 15th in Kathmandu is still the 14th in UTC.
        XCTAssertEqual(HealthDayAggregator.dayKey(for: date("2026-09-14T18:45:00Z"), calendar: calendar(kathmandu)), key("2026-09-15"))
        // 21:00 on the 14th in Chicago is already the 15th in UTC.
        XCTAssertEqual(HealthDayAggregator.dayKey(for: date("2026-09-15T02:00:00Z"), calendar: calendar(chicago)), key("2026-09-14"))
    }

    func testOvernightSleepCountsTowardTheDayYouWakeUp() {
        let night = HealthDayAggregator.Interval(start: date("2026-09-14T04:00:00Z"), end: date("2026-09-14T11:30:00Z"))
        // Chicago: 23:00 on the 13th until 06:30 on the 14th.
        let totals = HealthDayAggregator.sleepMinutesByDay(asleep: [night], inBed: [], calendar: calendar(chicago))
        XCTAssertEqual(totals, [key("2026-09-14"): 450])
    }

    func testOverlappingSourcesAreNotDoubleCounted() {
        let phone = HealthDayAggregator.Interval(start: date("2026-09-14T04:00:00Z"), end: date("2026-09-14T10:00:00Z"))
        let watch = HealthDayAggregator.Interval(start: date("2026-09-14T05:00:00Z"), end: date("2026-09-14T11:00:00Z"))
        let totals = HealthDayAggregator.sleepMinutesByDay(asleep: [phone, watch], inBed: [], calendar: calendar(chicago))
        XCTAssertEqual(totals[key("2026-09-14")], 420)
    }

    func testInBedIsOnlyAFallbackWhenNoAsleepSamples() {
        let calendar = calendar(chicago)
        let asleep = [HealthDayAggregator.Interval(start: date("2026-09-14T05:00:00Z"), end: date("2026-09-14T11:00:00Z"))]
        let inBed = [
            HealthDayAggregator.Interval(start: date("2026-09-14T04:00:00Z"), end: date("2026-09-14T12:00:00Z")),
            HealthDayAggregator.Interval(start: date("2026-09-13T04:00:00Z"), end: date("2026-09-13T10:00:00Z"))
        ]
        let totals = HealthDayAggregator.sleepMinutesByDay(asleep: asleep, inBed: inBed, calendar: calendar)
        XCTAssertEqual(totals[key("2026-09-14")], 360, "asleep time wins when present")
        XCTAssertEqual(totals[key("2026-09-13")], 360, "in-bed time fills days without asleep samples")
    }

    func testLatestReadingWinsPerDay() {
        let readings = [
            HealthDayAggregator.Reading(date: date("2026-09-14T13:00:00Z"), value: 70),
            HealthDayAggregator.Reading(date: date("2026-09-14T20:00:00Z"), value: 64),
            HealthDayAggregator.Reading(date: date("2026-09-13T20:00:00Z"), value: 66.6)
        ]
        let values = HealthDayAggregator.latestValueByDay(readings, calendar: calendar(chicago))
        XCTAssertEqual(values, [key("2026-09-14"): 64, key("2026-09-13"): 67])
    }

    func testSnapshotsSkipEmptyDaysAndAreNewestFirst() {
        let calendar = calendar(chicago)
        let end = date("2026-09-14T20:00:00Z")
        let snapshots = HealthDayAggregator.snapshots(
            seniorID: "maya",
            steps: [key("2026-09-14"): 3000, key("2026-09-12"): 5000],
            sleepMinutes: [key("2026-09-14"): 420],
            restingHeartRate: [:],
            endingAt: end, calendar: calendar)
        XCTAssertEqual(snapshots.map(\.date), [key("2026-09-14"), key("2026-09-12")])
        XCTAssertEqual(snapshots.first?.sleepMinutes, 420)
        XCTAssertEqual(snapshots.first?.id, "healthkit-maya-2026-09-14")
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "healthkit" })
    }

    func testPasswordPolicy() {
        XCTAssertEqual(PasswordPolicy.problem(with: "short"), "Use at least 8 characters.")
        XCTAssertNil(PasswordPolicy.problem(with: "long enough"))
    }
}
