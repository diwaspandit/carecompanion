import XCTest
@testable import CareCore

final class SeniorCareSummaryTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let reference = InMemoryCareRepository.referenceDate

    private func demoSnapshot() async -> CareSnapshot {
        await MainActor.run { InMemoryCareRepository().snapshot }
    }

    private func health(_ seniorID: String, daysAgo: Int, steps: Int, sleep: Int, heart: Int, source: String = "healthkit") -> HealthSnapshot {
        HealthSnapshot(id: "h-\(seniorID)-\(daysAgo)-\(source)", seniorID: seniorID,
                       date: reference.addingTimeInterval(-Double(daysAgo) * day),
                       steps: steps, sleepMinutes: sleep, restingHeartRate: heart, source: source)
    }

    private func renamedSnapshot() async -> CareSnapshot {
        var snapshot = await demoSnapshot()
        snapshot.seniors[0].name = "Samar Ranjit"
        snapshot.seniors[0].city = "Austin"
        return snapshot
    }

    func testSummaryUsesRealSeniorAndMedicationCounts() async throws {
        let snapshot = await demoSnapshot()
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: InMemoryCareRepository.mayaID))
        XCTAssertEqual(summary.senior.name, "Maya Sharma")
        XCTAssertEqual(summary.medicationsTaken, 3)
        XCTAssertEqual(summary.medicationsTotal, 4)
        XCTAssertEqual(summary.missedMedications.map(\.name), ["Atorvastatin"])
        XCTAssertNil(summary.checkInDate)
        XCTAssertTrue(summary.needsAttention)
    }

    func testSummaryReturnsNilForUnknownSenior() async {
        let snapshot = await demoSnapshot()
        XCTAssertNil(SeniorCareSummary(snapshot: snapshot, seniorID: "nobody"))
    }

    func testHealthHistoryKeepsOneEntryPerDayPreferringHealthKit() async throws {
        var snapshot = await demoSnapshot()
        let id = InMemoryCareRepository.mayaID
        snapshot.health = [
            health(id, daysAgo: 1, steps: 500, sleep: 300, heart: 70, source: "demo"),
            health(id, daysAgo: 0, steps: 900, sleep: 360, heart: 68, source: "demo"),
            health(id, daysAgo: 0, steps: 4200, sleep: 400, heart: 66, source: "healthkit")
        ]
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: id))
        XCTAssertEqual(summary.healthHistory.count, 2)
        XCTAssertEqual(summary.latestHealth?.source, "healthkit")
        XCTAssertEqual(summary.latestHealth?.steps, 4200)
        XCTAssertEqual(summary.healthHistory.last?.steps, 500)
    }

    func testBaselineIgnoresMissingMetricsAndFlagsLowActivity() async throws {
        var snapshot = await demoSnapshot()
        let id = InMemoryCareRepository.mayaID
        snapshot.health = [
            health(id, daysAgo: 0, steps: 1000, sleep: 0, heart: 0),
            health(id, daysAgo: 1, steps: 4000, sleep: 420, heart: 70),
            health(id, daysAgo: 2, steps: 0, sleep: 0, heart: 0),
            health(id, daysAgo: 3, steps: 4000, sleep: 400, heart: 74)
        ]
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: id))
        XCTAssertEqual(summary.baselineSteps, 4000)
        XCTAssertEqual(summary.averageSleepMinutes, 410)
        XCTAssertEqual(summary.restingHeartRateRange, 70...74)
        XCTAssertTrue(summary.isStepsBelowBaseline)
    }

    func testLiveWatchPresenceReplacesTheHourlyGuess() async throws {
        var snapshot = await demoSnapshot()
        let id = InMemoryCareRepository.mayaID
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        snapshot.healthReadings = [
            HealthReading(id: "worn", seniorID: id, recordedAt: now.addingTimeInterval(-2 * 86_400), kind: .worn, value: 30,
                          valueSecondary: now.timeIntervalSince1970, source: "watch"),
            WatchPresence.reading(seniorID: id, worn: false, reportedAt: now)
        ]
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: id, now: now))
        XCTAssertFalse(summary.watchCollecting)
        XCTAssertEqual(summary.watchLastSample, now)
        XCTAssertEqual(summary.wornMinutesToday, 0)
    }

    func testWatchSnapshotBeatsThePhoneCopyForTheSameDay() async throws {
        var snapshot = await demoSnapshot()
        let id = InMemoryCareRepository.mayaID
        snapshot.health = [
            health(id, daysAgo: 0, steps: 100, sleep: 0, heart: 0, source: "healthkit"),
            health(id, daysAgo: 0, steps: 2400, sleep: 400, heart: 64, source: "watch")
        ]
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: id))
        XCTAssertEqual(summary.latestHealth?.source, "watch")
        XCTAssertEqual(summary.latestHealth?.steps, 2400)
    }

    func testSteadyActivityIsNotFlagged() async throws {
        let snapshot = await demoSnapshot()
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: InMemoryCareRepository.mayaID))
        XCTAssertFalse(summary.isStepsBelowBaseline)
    }

    func testCareInsightDescribesTheRealSenior() async throws {
        var snapshot = await renamedSnapshot()
        let id = InMemoryCareRepository.mayaID
        snapshot.health = [
            health(id, daysAgo: 0, steps: 1000, sleep: 360, heart: 71),
            health(id, daysAgo: 1, steps: 4000, sleep: 420, heart: 70)
        ]
        let insight = try await MockAIService().careInsight(for: snapshot, seniorID: id)
        let text = ([insight.summary, insight.suggestion] + insight.observations).joined(separator: " ")
        XCTAssertFalse(text.contains("Maya"))
        XCTAssertTrue(text.contains("Samar"))
        XCTAssertTrue(text.contains("3 of 4"))
        XCTAssertTrue(text.contains("1,000") || text.contains("1000"))
        XCTAssertTrue(text.contains("Atorvastatin"))
        XCTAssertFalse(text.lowercased().contains("demo"))
    }

    func testAppointmentPrepDescribesTheRealSenior() async throws {
        let snapshot = await renamedSnapshot()
        let prep = try await MockAIService().appointmentPrep(for: snapshot.appointments[0], snapshot: snapshot)
        let text = ([prep.title, prep.safetyNote] + prep.observations + prep.questions).joined(separator: " ")
        XCTAssertFalse(text.contains("Maya"))
        XCTAssertTrue(text.contains("Samar"))
        XCTAssertTrue(text.contains("3 of 4"))
        XCTAssertTrue(prep.safetyNote.contains("does not diagnose, prescribe"))
    }

    func testSelectingAnotherSeniorClearsPerSeniorAIOutput() async throws {
        let repository = await MainActor.run { InMemoryCareRepository() }
        let state = await MainActor.run { AppState(repository: repository) }
        let second = AccountSenior(id: "senior-2", accountID: "account-sharma", name: "Ramesh Sharma",
                                   age: 78, city: "Pokhara", timeZoneIdentifier: "Asia/Kathmandu")
        try await repository.addSenior(second)
        await state.refresh()
        await state.loadCareInsight()
        await MainActor.run {
            XCTAssertNotNil(state.careInsight)
            state.selectSenior(id: "senior-2")
            XCTAssertEqual(state.selectedSenior?.name, "Ramesh Sharma")
            XCTAssertNil(state.careInsight)
            XCTAssertNil(state.appointmentPrep)
            XCTAssertEqual(state.seniorSummaries.map(\.senior.name), ["Maya Sharma", "Ramesh Sharma"])
        }
    }

    func testMoodHistoryKeepsLatestMoodPerSeniorLocalDay() async throws {
        var snapshot = await demoSnapshot()
        let id = InMemoryCareRepository.mayaID
        snapshot.moods = [
            MoodEntry(id: "m1", seniorID: id, mood: .low, date: reference.addingTimeInterval(-day)),
            MoodEntry(id: "m2", seniorID: id, mood: .okay, date: reference),
            MoodEntry(id: "m3", seniorID: id, mood: .great, date: reference.addingTimeInterval(3600))
        ]
        let summary = try XCTUnwrap(SeniorCareSummary(snapshot: snapshot, seniorID: id))
        XCTAssertEqual(summary.moodHistory.map(\.id), ["m1", "m3"])
        XCTAssertEqual(summary.mood, .great)
    }
}
