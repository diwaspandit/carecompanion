import XCTest
@testable import CareCore

final class CareCoreTests: XCTestCase {
    func testSeedIsDeterministic() async {
        await MainActor.run {
            let a = DemoCareRepository()
            let b = DemoCareRepository()
            XCTAssertEqual(a.snapshot, b.snapshot)
            XCTAssertEqual(a.snapshot.seniors.first?.name, "Maya Sharma")
            XCTAssertEqual(a.snapshot.health.first?.steps, 2840)
            XCTAssertEqual(a.snapshot.health.first?.sleepMinutes, 380)
            XCTAssertEqual(a.snapshot.health.first?.restingHeartRate, 72)
        }
    }
    func testCheckInIsIdempotentAndSharedAcrossRoles() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            state.role = .senior
            state.checkIn()
            state.checkIn()
            state.role = .family
            XCTAssertEqual(state.snapshot.checkIns.count, 1)
            XCTAssertTrue(state.isCheckedIn)
        }
    }
    func testCheckInAdvancesSeniorDemoToMoodPrompt() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            state.switchToSenior()
            state.checkIn()
            XCTAssertEqual(state.seniorTab, .mood)
        }
    }
    func testMoodRecordsLatestChoice() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            state.recordMood(.great)
            state.recordMood(.low)
            XCTAssertEqual(state.currentMood, .low)
            XCTAssertEqual(state.snapshot.moods.count, 1)
        }
    }
    func testUnknownSeniorCannotMutateRepository() async {
        await MainActor.run {
            let repository = DemoCareRepository()
            let seed = repository.snapshot
            repository.checkIn(seniorID: "unknown", at: DemoCareRepository.referenceDate)
            repository.recordMood(.low, seniorID: "unknown", at: DemoCareRepository.referenceDate)
            repository.triggerSOS(seniorID: "unknown", at: DemoCareRepository.referenceDate)
            XCTAssertEqual(repository.snapshot, seed)
        }
    }
    func testSOSIsIdempotentAndCanBeAcknowledged() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            state.triggerSOS()
            state.triggerSOS()
            XCTAssertEqual(state.snapshot.alerts.count, 1)
            XCTAssertTrue(state.hasEmergency)
            state.acknowledgeEmergency()
            XCTAssertFalse(state.hasEmergency)
        }
    }
    func testEmergencyAcknowledgeClearsAlertBadge() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            XCTAssertEqual(state.activeDemoAlertCount, 3)
            state.triggerSOS()
            XCTAssertEqual(state.activeDemoAlertCount, 4)
            state.acknowledgeEmergency()
            XCTAssertEqual(state.activeDemoAlertCount, 3)
        }
    }
    func testMedicationToggleUpdatesSnapshot() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            XCTAssertEqual(state.medicationsTakenCount, 3)
            state.toggleMedication(id: "med-3")
            XCTAssertEqual(state.medicationsTakenCount, 4)
            state.toggleMedication(id: "missing")
            XCTAssertEqual(state.medicationsTakenCount, 4)
        }
    }
    func testRoleNavigationSetsScreens() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            XCTAssertEqual(state.screen, .onboarding)
            state.chooseRole(.senior)
            XCTAssertEqual(state.screen, .seniorHome)
            state.switchToFamily(tab: .appointments)
            XCTAssertEqual(state.screen, .familyDashboard)
            XCTAssertEqual(state.familyTab, .appointments)
        }
    }
    func testResetClearsCareStateButPreservesSubscription() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            let seed = state.snapshot
            state.subscription = SubscriptionAccess(activeEntitlements: ["plus_plan", "premium_insights"])
            state.checkIn()
            state.recordMood(.great)
            state.triggerSOS()
            state.role = .family
            DemoScenarioController(state: state).reset()
            XCTAssertEqual(state.snapshot, seed)
            XCTAssertNil(state.role)
            XCTAssertEqual(state.screen, .onboarding)
            XCTAssertTrue(state.subscription.canUsePremiumAI)
        }
    }
    func testPremiumScenarioDoesNotForgePurchase() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            DemoScenarioController(state: state).apply(.premiumUnlocked)
            XCTAssertTrue(state.isPremiumPreview)
            XCTAssertFalse(state.subscription.canUsePremiumAI)
        }
    }
    func testScenariosRepeatExactly() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            let controller = DemoScenarioController(state: state)
            for scenario in DemoScenario.allCases {
                controller.apply(scenario)
                let first = state.snapshot
                controller.apply(scenario)
                XCTAssertEqual(first, state.snapshot)
            }
        }
    }
    func testHealthHistoryIsSevenDaysAndExplicitlyDemo() {
        let date = Date(timeIntervalSince1970: 0)
        let history = DemoHealthDataProvider().snapshots(seniorID: "maya", endingAt: date)
        XCTAssertEqual(history.count, 7)
        XCTAssertEqual(Set(history.map(\.id)).count, 7)
        XCTAssertTrue(history.allSatisfy { $0.source == "Demo data" && $0.seniorID == "maya" })
        XCTAssertEqual(history.last?.date, date.addingTimeInterval(-6 * 86400))
    }
    func testCareAlwaysFreeAndSeniorLimitEnforced() {
        let free = AccessPolicy(subscription: SubscriptionAccess())
        XCTAssertTrue(free.canUseCoreCare)
        XCTAssertTrue(free.canAddSenior(currentCount: 0))
        XCTAssertFalse(free.canAddSenior(currentCount: 1))
        XCTAssertFalse(free.canAddSenior(currentCount: -1))
        let plus = AccessPolicy(subscription: SubscriptionAccess(activeEntitlements: ["plus_plan"]))
        XCTAssertTrue(plus.canAddSenior(currentCount: 4))
        XCTAssertFalse(plus.canAddSenior(currentCount: 5))
    }
    func testResetClearsPreviewFlags() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            let controller = DemoScenarioController(state: state)
            controller.apply(.appointmentPrepared)
            XCTAssertTrue(state.isAppointmentPreparedPreview)
            controller.reset()
            XCTAssertFalse(state.isAppointmentPreparedPreview)
            XCTAssertFalse(state.isPremiumPreview)
        }
    }
    func testAccessLimitsAndEntitlements() {
        XCTAssertEqual(SubscriptionAccess().seniorLimit, 1)
        XCTAssertFalse(SubscriptionAccess().canUsePremiumAI)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan"]).seniorLimit, 5)
        XCTAssertTrue(SubscriptionAccess(activeEntitlements: ["plus_plan"]).canUsePremiumAI)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan", "pro_plan"]).seniorLimit, 25)
        XCTAssertTrue(SubscriptionAccess(activeEntitlements: ["premium_insights"]).canUsePremiumAI)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["premium_insights"]).seniorLimit, 1)
    }
    func testPremiumPreviewUnlockUsesExpectedEntitlement() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            XCTAssertFalse(state.hasPremiumAccess)
            state.unlockPremiumPreview()
            XCTAssertTrue(state.hasPremiumAccess)
            XCTAssertEqual(state.subscription.activeEntitlements, ["premium_insights"])
        }
    }
    func testAppointmentPrepPromptsPaywallThenGeneratesAfterUnlock() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await state.prepareAppointment()
        await MainActor.run {
            XCTAssertEqual(state.paywallContext, .appointmentPrep)
            XCTAssertNil(state.appointmentPrep)
            state.unlockPremiumPreview()
        }
        await state.prepareAppointment()
        await MainActor.run {
            XCTAssertNil(state.paywallContext)
            XCTAssertNotNil(state.appointmentPrep)
            XCTAssertTrue(state.isAppointmentPreparedPreview)
        }
    }
    func testMockAIAvoidsDiagnosisLanguage() async throws {
        let snapshot = await MainActor.run { DemoCareRepository().snapshot }
        let insight = try await MockAIService().careInsight(for: snapshot, seniorID: DemoCareRepository.mayaID)
        let appointment = snapshot.appointments[0]
        let prep = try await MockAIService().appointmentPrep(for: appointment, snapshot: snapshot)
        let combined = ([insight.summary, insight.suggestion, prep.safetyNote] + insight.observations + prep.observations + prep.questions).joined(separator: " ").lowercased()
        XCTAssertFalse(combined.contains("diagnose maya"))
        XCTAssertFalse(combined.contains("prescribe treatment"))
        XCTAssertFalse(combined.contains("disease probability"))
        XCTAssertTrue(combined.contains("does not diagnose"))
        XCTAssertTrue(combined.contains("does not diagnose, prescribe"))
    }
}
