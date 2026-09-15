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
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await MainActor.run { state.role = .senior }
        await state.checkIn()
        await state.checkIn()
        await MainActor.run {
            state.role = .family
            XCTAssertEqual(state.snapshot.checkIns.count, 1)
            XCTAssertTrue(state.isCheckedIn)
        }
    }
    func testCheckInAdvancesSeniorDemoToMoodPrompt() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await MainActor.run { state.switchToSenior() }
        await state.checkIn()
        await MainActor.run {
            XCTAssertEqual(state.seniorTab, .mood)
        }
    }
    func testMoodRecordsLatestChoice() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await state.recordMood(.great)
        await state.recordMood(.low)
        await MainActor.run {
            XCTAssertEqual(state.currentMood, .low)
            XCTAssertEqual(state.snapshot.moods.count, 1)
        }
    }
    func testUnknownSeniorCannotMutateRepository() async {
        let repository = await MainActor.run { DemoCareRepository() }
        let seed = await MainActor.run { repository.snapshot }
        do {
            try await repository.checkIn(seniorID: "unknown", at: DemoCareRepository.referenceDate)
            XCTFail("Should have thrown error")
        } catch {}
        do {
            try await repository.recordMood(.low, seniorID: "unknown", at: DemoCareRepository.referenceDate)
            XCTFail("Should have thrown error")
        } catch {}
        do {
            try await repository.triggerSOS(seniorID: "unknown", at: DemoCareRepository.referenceDate)
            XCTFail("Should have thrown error")
        } catch {}
        await MainActor.run {
            XCTAssertEqual(repository.snapshot, seed)
        }
    }
    func testSOSIsIdempotentAndCanBeAcknowledged() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await state.triggerSOS()
        await state.triggerSOS()
        await MainActor.run {
            XCTAssertEqual(state.snapshot.alerts.count, 1)
            XCTAssertTrue(state.hasEmergency)
        }
        await state.acknowledgeEmergency()
        await MainActor.run {
            XCTAssertFalse(state.hasEmergency)
        }
    }
    func testEmergencyAcknowledgeClearsAlertBadge() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await MainActor.run {
            XCTAssertEqual(state.activeDemoAlertCount, 3)
        }
        await state.triggerSOS()
        await MainActor.run {
            XCTAssertEqual(state.activeDemoAlertCount, 4)
        }
        await state.acknowledgeEmergency()
        await MainActor.run {
            XCTAssertEqual(state.activeDemoAlertCount, 3)
        }
    }
    func testMedicationToggleUpdatesSnapshot() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await MainActor.run {
            XCTAssertEqual(state.medicationsTakenCount, 3)
        }
        await state.toggleMedication(id: "med-3")
        await MainActor.run {
            XCTAssertEqual(state.medicationsTakenCount, 4)
        }
        await state.toggleMedication(id: "missing")
        await MainActor.run {
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
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        let seed = await MainActor.run { state.snapshot }
        await MainActor.run {
            state.subscription = SubscriptionAccess(activeEntitlements: ["plus_plan", "premium_insights"])
        }
        await state.checkIn()
        await state.recordMood(.great)
        await state.triggerSOS()
        await MainActor.run { state.role = .family }
        await DemoScenarioController(state: state).reset()
        await MainActor.run {
            XCTAssertEqual(state.snapshot, seed)
            XCTAssertNil(state.role)
            XCTAssertEqual(state.screen, .onboarding)
            XCTAssertTrue(state.subscription.canUsePremiumAI)
        }
    }
    func testPremiumScenarioDoesNotForgePurchase() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        await DemoScenarioController(state: state).apply(.premiumUnlocked)
        await MainActor.run {
            XCTAssertTrue(state.isPremiumPreview)
            XCTAssertFalse(state.subscription.canUsePremiumAI)
        }
    }
    func testScenariosRepeatExactly() async {
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        let controller = await MainActor.run { DemoScenarioController(state: state) }
        for scenario in DemoScenario.allCases {
            await controller.apply(scenario)
            let first = await MainActor.run { state.snapshot }
            await controller.apply(scenario)
            await MainActor.run {
                XCTAssertEqual(first, state.snapshot)
            }
        }
    }
    func testHealthHistoryIsSevenDaysAndExplicitlyDemo() {
        let date = Date(timeIntervalSince1970: 0)
        let history = DemoHealthDataProvider().snapshotsSync(seniorID: "maya", endingAt: date)
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
        let state = await MainActor.run { AppState(repository: DemoCareRepository()) }
        let controller = await MainActor.run { DemoScenarioController(state: state) }
        await controller.apply(.appointmentPrepared)
        await MainActor.run {
            XCTAssertTrue(state.isAppointmentPreparedPreview)
        }
        await controller.reset()
        await MainActor.run {
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

    // MARK: - Phase 1 Service Boundary Tests

    func testServiceErrorTypes() {
        let offline = CareServiceError.offline
        let unauthorized = CareServiceError.unauthorized
        let premiumRequired = CareServiceError.premiumRequired
        let healthPermissionDenied = CareServiceError.healthPermissionDenied
        let vendorUnavailable = CareServiceError.vendorUnavailable
        let invalidState = CareServiceError.invalidState("test")

        XCTAssertNotNil(offline.errorDescription)
        XCTAssertNotNil(unauthorized.errorDescription)
        XCTAssertNotNil(premiumRequired.errorDescription)
        XCTAssertNotNil(healthPermissionDenied.errorDescription)
        XCTAssertNotNil(vendorUnavailable.errorDescription)
        XCTAssertNotNil(invalidState.errorDescription)
    }

    func testDemoSubscriptionServiceReturnsCurrentAccess() async {
        let service = await MainActor.run {
            DemoSubscriptionService(access: SubscriptionAccess(activeEntitlements: ["plus_plan"]))
        }
        let access = try? await service.refreshAccess()
        await MainActor.run {
            XCTAssertEqual(access?.activeEntitlements, ["plus_plan"])
            XCTAssertEqual(service.currentAccess.seniorLimit, 5)
        }
    }

    func testDemoSubscriptionServiceRestorePurchases() async {
        let service = await MainActor.run { DemoSubscriptionService() }
        let access = try? await service.restorePurchases()
        await MainActor.run {
            XCTAssertNotNil(access)
            XCTAssertEqual(access?.seniorLimit, 1)
        }
    }

    func testPlanServiceEnforcesSeniorLimits() {
        let planService = DefaultPlanService()
        let freeAccess = SubscriptionAccess()
        let plusAccess = SubscriptionAccess(activeEntitlements: ["plus_plan"])
        let proAccess = SubscriptionAccess(activeEntitlements: ["pro_plan"])

        XCTAssertTrue(planService.canAddSenior(currentCount: 0, subscription: freeAccess))
        XCTAssertFalse(planService.canAddSenior(currentCount: 1, subscription: freeAccess))

        XCTAssertTrue(planService.canAddSenior(currentCount: 4, subscription: plusAccess))
        XCTAssertFalse(planService.canAddSenior(currentCount: 5, subscription: plusAccess))

        XCTAssertTrue(planService.canAddSenior(currentCount: 24, subscription: proAccess))
        XCTAssertFalse(planService.canAddSenior(currentCount: 25, subscription: proAccess))
    }

    func testPlanServicePremiumAIAccess() {
        let planService = DefaultPlanService()
        let freeAccess = SubscriptionAccess()
        let plusAccess = SubscriptionAccess(activeEntitlements: ["plus_plan"])
        let insightsOnly = SubscriptionAccess(activeEntitlements: ["premium_insights"])

        XCTAssertFalse(planService.canUsePremiumAI(subscription: freeAccess))
        XCTAssertTrue(planService.canUsePremiumAI(subscription: plusAccess))
        XCTAssertTrue(planService.canUsePremiumAI(subscription: insightsOnly))
    }

    func testPlanServiceCoreCareAlwaysFree() {
        let planService = DefaultPlanService()
        XCTAssertTrue(planService.canUseCoreCare())
    }

    func testSyncStatusTracking() {
        var status = SyncStatus()
        XCTAssertFalse(status.isAnySyncing)
        XCTAssertFalse(status.hasAnyFailed)
        XCTAssertTrue(status.allSynced)

        status.careData = .syncing
        XCTAssertTrue(status.isAnySyncing)
        XCTAssertFalse(status.allSynced)

        status.careData = .failed
        status.lastError = "Test error"
        XCTAssertTrue(status.hasAnyFailed)
        XCTAssertEqual(status.lastError, "Test error")
    }

    func testHealthDataProviderPermissionStatus() async {
        let provider = DemoHealthDataProvider()
        let status = await provider.permissionStatus()
        XCTAssertEqual(status, .authorized)
    }

    func testHealthDataProviderSnapshots() async throws {
        let provider = DemoHealthDataProvider()
        let date = Date()
        let snapshots = try await provider.snapshots(seniorID: "test-senior", endingAt: date)

        XCTAssertEqual(snapshots.count, 7)
        XCTAssertTrue(snapshots.allSatisfy { $0.source == "Demo data" })
        XCTAssertTrue(snapshots.allSatisfy { $0.seniorID == "test-senior" })
    }

    func testRepositoryErrorsOnInvalidSenior() async {
        let repository = await MainActor.run { DemoCareRepository() }

        do {
            try await repository.checkIn(seniorID: "invalid", at: Date())
            XCTFail("Should have thrown error")
        } catch let error as CareServiceError {
            if case .invalidState(let message) = error {
                XCTAssertTrue(message.contains("Senior not found"))
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRepositoryHealthSnapshotUpsert() async throws {
        let repository = await MainActor.run { DemoCareRepository() }
        let seniorID = DemoCareRepository.mayaID

        let newSnapshot = HealthSnapshot(
            id: "test-health",
            seniorID: seniorID,
            date: Date(),
            steps: 5000,
            sleepMinutes: 450,
            restingHeartRate: 68,
            source: "test"
        )

        try await repository.upsertHealthSnapshots([newSnapshot])

        await MainActor.run {
            XCTAssertTrue(repository.snapshot.health.contains { $0.id == "test-health" })
        }
    }

    // MARK: - Phase 3 Plan Tier Tests

    func testPlanTierResolvesFromEntitlements() {
        XCTAssertEqual(SubscriptionAccess().tier, .free)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan"]).tier, .plus)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["pro_plan"]).tier, .pro)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan", "pro_plan"]).tier, .pro)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["enterprise_plan"]).tier, .enterprise)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["premium_insights"]).tier, .free)
    }

    func testEnterpriseSeniorLimitFallsBackToUnboundedWithoutASeatCount() {
        let noSeatCount = SubscriptionAccess(activeEntitlements: ["enterprise_plan"])
        XCTAssertEqual(noSeatCount.seniorLimit, Int.max)
        let withSeatCount = SubscriptionAccess(activeEntitlements: ["enterprise_plan"], enterpriseSeatLimit: 400)
        XCTAssertEqual(withSeatCount.seniorLimit, 400)
        XCTAssertTrue(withSeatCount.canUsePremiumAI)
    }

    func testPlanCatalogHasFourTiersWithOnlyPlusAndProPurchasable() {
        XCTAssertEqual(PlanCatalog.all.map(\.tier), [.free, .plus, .pro, .enterprise])
        XCTAssertEqual(PlanCatalog.all.filter(\.isPurchasable).map(\.tier), [.plus, .pro])
        XCTAssertFalse(PlanCatalog.all.first { $0.tier == .free }!.isPurchasable)
        XCTAssertFalse(PlanCatalog.all.first { $0.tier == .enterprise }!.isPurchasable)
    }

    func testPlanServiceEnforcesEnterpriseSeatLimit() {
        let planService = DefaultPlanService()
        let enterprise = SubscriptionAccess(activeEntitlements: ["enterprise_plan"], enterpriseSeatLimit: 60)
        XCTAssertTrue(planService.canAddSenior(currentCount: 59, subscription: enterprise))
        XCTAssertFalse(planService.canAddSenior(currentCount: 60, subscription: enterprise))
        XCTAssertTrue(planService.canUsePremiumAI(subscription: enterprise))
    }

    func testApplySubscriptionAccessUpdatesStateFromAVendorBridge() async {
        await MainActor.run {
            let state = AppState(repository: DemoCareRepository())
            XCTAssertFalse(state.hasPremiumAccess)
            state.applySubscriptionAccess(SubscriptionAccess(activeEntitlements: ["pro_plan"]))
            XCTAssertTrue(state.hasPremiumAccess)
            XCTAssertEqual(state.subscription.seniorLimit, 25)
        }
    }

    func testRepositoryAppointmentOperations() async throws {
        let repository = await MainActor.run { DemoCareRepository() }
        let seniorID = DemoCareRepository.mayaID

        let appointment = Appointment(
            id: "test-appt",
            seniorID: seniorID,
            title: "Test Visit",
            clinician: "Dr. Test",
            date: Date(),
            location: "Test Clinic",
            notes: "Test notes"
        )

        try await repository.saveAppointment(appointment)
        await MainActor.run {
            XCTAssertTrue(repository.snapshot.appointments.contains { $0.id == "test-appt" })
        }

        try await repository.deleteAppointment(id: "test-appt")
        await MainActor.run {
            XCTAssertFalse(repository.snapshot.appointments.contains { $0.id == "test-appt" })
        }
    }

    // MARK: - Phase 4 Health Sync Tests

    /// Sync is only allowed on the senior's own linked login.
    @MainActor private static func linkedSeniorState() async -> AppState {
        let repository = DemoCareRepository()
        var maya = repository.snapshot.seniors[0]
        maya.profileID = "profile-maya"
        try? await repository.updateSenior(maya)
        return AppState(repository: repository, healthProvider: DemoHealthDataProvider(), currentProfileID: "profile-maya")
    }

    func testHealthSyncWithNoProvider() async {
        let state = await MainActor.run {
            AppState(repository: DemoCareRepository(), healthProvider: nil)
        }

        await state.syncHealthData()

        await MainActor.run {
            // Should not fail, just no-op
            XCTAssertEqual(state.healthSyncStatus.healthData, .idle)
        }
    }

    func testHealthSyncWithDemoProvider() async {
        let state = await Self.linkedSeniorState()

        await state.syncHealthData()

        await MainActor.run {
            XCTAssertEqual(state.healthSyncStatus.healthData, .synced)
            XCTAssertNotNil(state.healthSyncStatus.lastSyncDate)
            // Should have health snapshots from demo provider
            XCTAssertFalse(state.snapshot.health.isEmpty)
        }
    }

    func testHealthPermissionStatusCheck() async {
        let state = await MainActor.run {
            AppState(repository: DemoCareRepository(), healthProvider: DemoHealthDataProvider())
        }

        let status = await state.checkHealthPermissionStatus()

        XCTAssertEqual(status, .authorized)
    }

    func testHealthSyncUpdatesSnapshot() async {
        let state = await Self.linkedSeniorState()

        await state.syncHealthData()

        await MainActor.run {
            // Should have health snapshots from sync
            XCTAssertFalse(state.snapshot.health.isEmpty)
            // All snapshots should be from demo provider
            let demoSnapshots = state.snapshot.health.filter { $0.source == "Demo data" }
            XCTAssertEqual(demoSnapshots.count, state.snapshot.health.count)
            // Should have 7 days of data
            XCTAssertEqual(state.snapshot.health.count, 7)
        }
    }

    func testHealthSnapshotsHaveCorrectSource() async throws {
        let provider = DemoHealthDataProvider()
        let date = Date()
        let snapshots = try await provider.snapshots(seniorID: "test-senior", endingAt: date)

        XCTAssertTrue(snapshots.allSatisfy { $0.source == "Demo data" })
    }

    func testHealthSyncStatusTracking() async {
        let state = await Self.linkedSeniorState()

        await MainActor.run {
            XCTAssertEqual(state.healthSyncStatus.healthData, .idle)
        }

        await state.syncHealthData()

        await MainActor.run {
            XCTAssertEqual(state.healthSyncStatus.healthData, .synced)
            XCTAssertNil(state.healthSyncStatus.lastError)
        }
    }

    func testRequestHealthPermissionsWithNoProvider() async {
        let state = await MainActor.run {
            AppState(repository: DemoCareRepository(), healthProvider: nil)
        }

        do {
            try await state.requestHealthPermissions()
            XCTFail("Should have thrown error")
        } catch let error as CareServiceError {
            if case .vendorUnavailable = error {
                // Expected
            } else {
                XCTFail("Wrong error type")
            }
        } catch {
            XCTFail("Wrong error type")
        }
    }
}
