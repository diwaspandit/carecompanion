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

    func testHourlyHeartRateIsAveragedAndBloodPressureKeepsTheLatestPair() {
        let calendar = calendar(chicago)
        let hour = date("2026-09-14T15:10:00Z")
        let later = date("2026-09-14T15:40:00Z")
        let hearts = HealthDayAggregator.averageHeartRateByHour([
            .init(date: hour, value: 70),
            .init(date: later, value: 80)
        ], calendar: calendar)
        XCTAssertEqual(hearts[HealthDayAggregator.hourStart(for: hour, calendar: calendar)], 75)
        let pressure = HealthDayAggregator.bloodPressureByHour(
            systolic: [.init(date: hour, value: 120), .init(date: later, value: 130)],
            diastolic: [.init(date: hour, value: 80), .init(date: later.addingTimeInterval(30), value: 84)],
            calendar: calendar)
        XCTAssertEqual(pressure[HealthDayAggregator.hourStart(for: hour, calendar: calendar)]?.0, 130)
        XCTAssertEqual(pressure[HealthDayAggregator.hourStart(for: hour, calendar: calendar)]?.1, 84)
    }

    func testWornMinutesCountEachQuarterHourWithAHeartSample() {
        let calendar = calendar(chicago)
        let first = date("2026-09-14T15:10:00Z")
        let second = date("2026-09-14T15:12:00Z")
        let later = date("2026-09-14T15:40:00Z")
        let worn = HealthDayAggregator.wornByHour([first, second, later], calendar: calendar)
        let hour = HealthDayAggregator.hourStart(for: first, calendar: calendar)
        XCTAssertEqual(worn[hour]?.minutes, 30)
        XCTAssertEqual(worn[hour]?.lastSample, later)
    }

    func testSleepIsSplitAcrossHours() {
        let calendar = calendar(chicago)
        let start = date("2026-09-14T10:30:00Z")
        let end = date("2026-09-14T11:30:00Z")
        let totals = HealthDayAggregator.sleepMinutesByHour([.init(start: start, end: end)], calendar: calendar)
        XCTAssertEqual(totals[HealthDayAggregator.hourStart(for: start, calendar: calendar)], 30)
        XCTAssertEqual(totals[HealthDayAggregator.hourStart(for: end, calendar: calendar)], 30)
    }

    func testWatchPresenceIsOnOnlyWhileTheReportIsFresh() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(WatchPresence.isOnWrist(value: 1, reportedAt: now.addingTimeInterval(-60), now: now))
        XCTAssertFalse(WatchPresence.isOnWrist(value: 0, reportedAt: now, now: now))
        XCTAssertFalse(WatchPresence.isOnWrist(value: 1, reportedAt: now.addingTimeInterval(-26 * 60), now: now))
    }

    func testHealthTotalsUploadOnceAnHour() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(HealthUploadSchedule.shouldUpload(lastUpload: nil, now: now))
        XCTAssertFalse(HealthUploadSchedule.shouldUpload(lastUpload: now.addingTimeInterval(-30 * 60), now: now))
        XCTAssertTrue(HealthUploadSchedule.shouldUpload(lastUpload: now.addingTimeInterval(-60 * 60), now: now))
    }

    func testWatchHealthReportRoundTrips() {
        let reading = HealthReading(id: "1", seniorID: "s", recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                    kind: .steps, value: 12, source: "watch")
        let report = WatchHealthReport(worn: true, reportedAt: Date(timeIntervalSince1970: 1_700_000_100), readings: [reading])
        XCTAssertEqual(WatchHealthReport(userInfo: report.userInfo()), report)
    }

    func testPasswordPolicy() {
        XCTAssertEqual(PasswordPolicy.problem(with: "short"), "Use at least 8 characters.")
        XCTAssertNil(PasswordPolicy.problem(with: "long enough"))
    }
}

final class OfflineCatchUpTests: XCTestCase {
    func testPastUntakenDosesAndVisitsAreReadyToLog() {
        let zone = TimeZone(identifier: "America/Chicago")!
        let now = ISO8601DateFormatter().date(from: "2026-09-14T15:00:00Z")!
        let due = Medication(id: "due", seniorID: "s", name: "Morning", scheduledTime: "8:00 AM")
        let soon = Medication(id: "soon", seniorID: "s", name: "Just now", scheduledTime: "9:59 AM")
        let later = Medication(id: "later", seniorID: "s", name: "Later", scheduledTime: "11:00 AM")
        let taken = Medication(id: "taken", seniorID: "s", name: "Done", scheduledTime: "7:00 AM", taken: true)
        let snoozed = Medication(id: "snoozed", seniorID: "s", name: "Wait", scheduledTime: "8:00 AM",
                                 snoozeUntil: now.addingTimeInterval(600))
        let meds = OfflineCatchUp.medications([due, soon, later, taken, snoozed], now: now, timeZone: zone)
        XCTAssertEqual(meds.map(\.id), ["due"])
        let addedAfter = Medication(id: "new", seniorID: "s", name: "Added late", scheduledTime: "8:00 AM",
                                    createdAt: now.addingTimeInterval(-60))
        XCTAssertTrue(OfflineCatchUp.medications([addedAfter], now: now, timeZone: zone).isEmpty)

        let passed = Appointment(id: "passed", seniorID: "s", title: "Clinic", clinician: "",
                                 date: now.addingTimeInterval(-3 * 3600), location: "", notes: "")
        let future = Appointment(id: "future", seniorID: "s", title: "Later", clinician: "",
                                 date: now.addingTimeInterval(3600), location: "", notes: "")
        let old = Appointment(id: "old", seniorID: "s", title: "Old", clinician: "",
                              date: now.addingTimeInterval(-40 * 3600), location: "", notes: "")
        let logged = Appointment(id: "logged", seniorID: "s", title: "Done", clinician: "",
                                 date: now.addingTimeInterval(-3 * 3600), location: "", notes: "", outcome: .went)
        XCTAssertEqual(OfflineCatchUp.visits([passed, future, old, logged], now: now, timeZone: zone).map(\.id), ["passed"])
    }
}

final class CareScheduleTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Chicago")!

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testMedicineWeekdaysAndEndDateDecideWhetherTodayCounts() {
        let monday = date("2026-09-14T15:00:00Z")
        let tuesday = date("2026-09-15T15:00:00Z")
        let mondays = Medication(id: "m", seniorID: "s", name: "Monday pill", scheduledTime: "8:00 AM", weekdays: [2])
        XCTAssertTrue(CareSchedule.medicationIsDue(mondays, on: monday, timeZone: zone))
        XCTAssertFalse(CareSchedule.medicationIsDue(mondays, on: tuesday, timeZone: zone))

        let ended = CareSchedule.storedDay(from: monday, timeZone: zone)!
        let course = Medication(id: "c", seniorID: "s", name: "Course", scheduledTime: "8:00 AM", endsOn: ended)
        XCTAssertTrue(CareSchedule.medicationIsDue(course, on: monday, timeZone: zone))
        XCTAssertFalse(CareSchedule.medicationIsDue(course, on: tuesday, timeZone: zone))
    }

    func testWeeklyVisitSkipsAheadAndStopsOnTheEndDate() {
        let start = date("2026-09-07T15:00:00Z")
        let tuesday = date("2026-09-15T16:00:00Z")
        let visit = Appointment(id: "v", seniorID: "s", title: "Clinic", clinician: "", date: start,
                                location: "", notes: "", repeatRule: .weekly)
        let next = CareSchedule.nextOccurrence(of: visit, after: tuesday, timeZone: zone)
        XCTAssertEqual(next, date("2026-09-21T15:00:00Z"))

        var ended = visit
        ended.endsOn = CareSchedule.storedDay(from: date("2026-09-14T15:00:00Z"), timeZone: zone)
        XCTAssertNil(CareSchedule.nextOccurrence(of: ended, after: tuesday, timeZone: zone))

        let alerts = CareSchedule.notificationOccurrences(of: visit, now: tuesday, timeZone: zone)
        XCTAssertEqual(alerts.first, date("2026-09-21T15:00:00Z"))
        XCTAssertEqual(alerts.count, 2)
    }

    func testALoggedOccurrenceDoesNotBlockTheNextOne() {
        let start = date("2026-09-07T15:00:00Z")
        let afterFirst = date("2026-09-07T18:00:00Z")
        var visit = Appointment(id: "v", seniorID: "s", title: "Clinic", clinician: "", date: start,
                                location: "", notes: "", repeatRule: .weekly)
        XCTAssertEqual(CareSchedule.occurrenceNeedingLog(visit, now: afterFirst, timeZone: zone), start)
        visit.loggedAt = start
        visit.outcome = .went
        XCTAssertNil(CareSchedule.occurrenceNeedingLog(visit, now: afterFirst, timeZone: zone))
        let followingWeek = date("2026-09-14T18:00:00Z")
        XCTAssertEqual(CareSchedule.occurrenceNeedingLog(visit, now: followingWeek, timeZone: zone), date("2026-09-14T15:00:00Z"))
    }
}
