import XCTest
@testable import CareCore

@MainActor
final class CareCoreTests: XCTestCase {
    private typealias Repo = InMemoryCareRepository

    private func makeState(profile: String? = Repo.diwasProfileID, mayaLinked: Bool = false,
                           health: (any HealthDataProvider)? = nil) -> (AppState, Repo) {
        let repository = Repo(currentProfileID: profile, mayaLinked: mayaLinked)
        return (AppState(repository: repository, healthProvider: health, now: { Repo.referenceDate }), repository)
    }

    // MARK: - Roles

    func testFamilyMemberSeesFamilyRole() {
        let (state, _) = makeState()
        XCTAssertEqual(state.role, .family)
        XCTAssertNil(state.linkedSenior)
        XCTAssertFalse(state.needsSeniorLink)
        XCTAssertEqual(state.selectedSeniorID, Repo.mayaID)
    }

    func testSeniorMustLinkBeforeUsingSeniorHome() async {
        let (state, _) = makeState(profile: Repo.mayaProfileID)
        XCTAssertEqual(state.role, .senior)
        XCTAssertTrue(state.needsSeniorLink)

        let linked = await state.claimSenior(id: Repo.mayaID)

        XCTAssertTrue(linked)
        XCTAssertEqual(state.linkedSenior?.id, Repo.mayaID)
        XCTAssertFalse(state.needsSeniorLink)
    }

    func testFamilyMemberCannotClaimSenior() async {
        let (state, _) = makeState()
        let linked = await state.claimSenior(id: Repo.mayaID)
        XCTAssertFalse(linked)
        XCTAssertNil(state.linkedSenior)
        XCTAssertNotNil(state.toastMessage)
    }

    func testLinkedSeniorIsSelectedByDefault() async {
        let repository = Repo(currentProfileID: Repo.mayaProfileID, mayaLinked: true)
        try? await repository.addSenior(AccountSenior(id: "senior-first", accountID: "account-sharma", name: "Ramesh",
                                                      age: 80, city: "", timeZoneIdentifier: "UTC"))
        let state = AppState(repository: repository)
        XCTAssertEqual(state.selectedSeniorID, Repo.mayaID)
    }

    // MARK: - Care actions

    func testCheckInIsIdempotentAndAdvancesToMood() async {
        let (state, _) = makeState(profile: Repo.mayaProfileID, mayaLinked: true)
        await state.checkIn()
        await state.checkIn()
        XCTAssertEqual(state.snapshot.checkIns.count, 1)
        XCTAssertTrue(state.isCheckedIn)
        XCTAssertEqual(state.seniorTab, .mood)
        XCTAssertEqual(state.toastMessage, "Check-in shared with your family.")
    }

    func testMoodRecordsLatestChoiceWithTrimmedNote() async {
        let (state, _) = makeState(profile: Repo.mayaProfileID, mayaLinked: true)
        await state.recordMood(.great)
        await state.recordMood(.low, note: "  Knee hurts a little  ")
        XCTAssertEqual(state.currentMood, .low)
        XCTAssertEqual(state.snapshot.moods.last?.note, "Knee hurts a little")
        XCTAssertEqual(state.seniorTab, .home)

        await state.recordMood(.okay, note: "   ")
        XCTAssertNil(state.snapshot.moods.last?.note)
    }

    func testUnknownSeniorCannotMutateRepository() async {
        let repository = Repo()
        let seed = repository.snapshot
        for write in [
            { try await repository.checkIn(seniorID: "unknown", at: Repo.referenceDate) },
            { try await repository.recordMood(.low, seniorID: "unknown", at: Repo.referenceDate, note: nil) },
            { try await repository.triggerSOS(seniorID: "unknown", at: Repo.referenceDate) }
        ] as [() async throws -> Void] {
            do {
                try await write()
                XCTFail("Should have thrown")
            } catch {}
        }
        XCTAssertEqual(repository.snapshot, seed)
    }

    func testSOSIsIdempotentAndCanBeAcknowledged() async {
        let (state, _) = makeState()
        await state.triggerSOS()
        await state.triggerSOS()
        XCTAssertEqual(state.snapshot.alerts.count, 1)
        XCTAssertTrue(state.hasEmergency)
        await state.acknowledgeEmergency()
        XCTAssertFalse(state.hasEmergency)
    }

    func testEmergencyAcknowledgeClearsAlertBadge() async {
        let (state, _) = makeState()
        XCTAssertEqual(state.activeAlertCount, 2, "not checked in + one medication not taken")
        await state.triggerSOS()
        XCTAssertEqual(state.activeAlertCount, 3)
        await state.acknowledgeEmergency()
        XCTAssertEqual(state.activeAlertCount, 2)
    }

    func testMedicationToggleRecordsEvent() async {
        let (state, _) = makeState()
        XCTAssertEqual(state.medicationsTakenCount, 3)
        await state.toggleMedication(id: "med-3")
        XCTAssertEqual(state.medicationsTakenCount, 4)
        XCTAssertEqual(state.snapshot.medicationEvents.last?.status, .taken)
        await state.toggleMedication(id: "missing")
        XCTAssertEqual(state.medicationsTakenCount, 4)
    }

    func testMedicationCrudKeepsDosage() async throws {
        let (state, _) = makeState()
        let added = await state.addMedication(name: " Vitamin D ", dosage: " 1000 IU ", scheduledTime: "9:00 AM")
        XCTAssertTrue(added)
        let vitamin = try XCTUnwrap(state.medications.first { $0.name == "Vitamin D" })
        XCTAssertEqual(vitamin.dosage, "1000 IU")

        await state.updateMedication(id: vitamin.id, name: "Vitamin D3", dosage: "2000 IU", scheduledTime: "9:30 AM")
        XCTAssertEqual(state.medications.first { $0.id == vitamin.id }?.dosage, "2000 IU")

        await state.deleteMedication(id: vitamin.id)
        XCTAssertFalse(state.medications.contains { $0.id == vitamin.id })

        let rejected = await state.addMedication(name: "   ", dosage: "", scheduledTime: "9:00 AM")
        XCTAssertFalse(rejected)
    }

    func testAppointmentCrud() async throws {
        let (state, _) = makeState()
        let visit = Appointment(id: "", seniorID: state.selectedSeniorID, title: "Eye check", clinician: "Dr. Rana",
                                date: Repo.referenceDate.addingTimeInterval(86_400), location: "Tilganga", notes: "")
        let saved = await state.saveAppointment(visit)
        XCTAssertTrue(saved)
        let stored = try XCTUnwrap(state.appointments.first { $0.title == "Eye check" })
        XCTAssertFalse(stored.id.isEmpty)
        XCTAssertEqual(state.nextAppointment?.id, stored.id)

        await state.deleteAppointment(id: stored.id)
        XCTAssertFalse(state.appointments.contains { $0.id == stored.id })
    }

    func testEmergencyContactCrud() async throws {
        let (state, _) = makeState()
        let saved = await state.saveEmergencyContact(name: "Sunita", relation: "Daughter", phone: "+977 98 4100 2233")
        XCTAssertTrue(saved)
        let contact = try XCTUnwrap(state.selectedSummary?.contacts.first)
        XCTAssertEqual(contact.relation, "Daughter")

        await state.saveEmergencyContact(name: "Sunita Sharma", relation: "Daughter", phone: "+977 98 4100 2233", id: contact.id)
        XCTAssertEqual(state.selectedSummary?.contacts.first?.name, "Sunita Sharma")

        await state.deleteEmergencyContact(id: contact.id)
        XCTAssertEqual(state.selectedSummary?.contacts.count, 0)

        let missingPhone = await state.saveEmergencyContact(name: "No phone", relation: "", phone: " ")
        XCTAssertFalse(missingPhone)
    }

    func testMessagesAreSentAsCurrentUserAndNamed() async {
        let (state, _) = makeState()
        let empty = await state.sendMessage("   ")
        XCTAssertFalse(empty)

        let sent = await state.sendMessage("  How was your walk?  ")
        XCTAssertTrue(sent)
        let message = state.messages.last!
        XCTAssertEqual(message.body, "How was your walk?")
        XCTAssertTrue(state.isFromCurrentUser(message))
        XCTAssertEqual(state.senderName(for: message), "You")

        let fromMaya = CareMessage(id: "m", senderProfileID: Repo.mayaProfileID, body: "Good", date: Repo.referenceDate)
        XCTAssertEqual(state.senderName(for: fromMaya), "Maya")
        let fromGone = CareMessage(id: "g", senderProfileID: nil, body: "Old", date: Repo.referenceDate)
        XCTAssertEqual(state.senderName(for: fromGone), "Former member")
    }

    func testUpdateProfileChangesCurrentMember() async {
        let (state, _) = makeState()
        let saved = await state.updateProfile(displayName: " Diwas Sharma ", city: "Austin", phone: "+1 512 555 0199")
        XCTAssertTrue(saved)
        XCTAssertEqual(state.currentMember?.name, "Diwas Sharma")
        XCTAssertEqual(state.currentMember?.phone, "+1 512 555 0199")
    }

    func testAddAndRemoveSeniorKeepsValidSelection() async {
        let (state, _) = makeState()
        let added = await state.addSenior(name: "Ramesh Sharma", age: 78, city: "Pokhara", timeZoneIdentifier: "Asia/Kathmandu")
        XCTAssertTrue(added)
        XCTAssertEqual(state.selectedSenior?.name, "Ramesh Sharma")
        XCTAssertEqual(state.seniorSummaries.count, 2)

        await state.removeSenior(id: state.selectedSeniorID)
        XCTAssertEqual(state.selectedSeniorID, Repo.mayaID)
    }

    func testSeniorCreatingOwnRecordIsLinked() async {
        let repository = Repo(currentProfileID: Repo.mayaProfileID)
        try? await repository.removeSenior(id: Repo.mayaID)
        let state = AppState(repository: repository)
        XCTAssertTrue(state.needsSeniorLink)

        await state.addSenior(name: "Maya Sharma", age: 74, city: "Kathmandu", timeZoneIdentifier: "Asia/Kathmandu", isMe: true)

        XCTAssertEqual(state.linkedSenior?.name, "Maya Sharma")
        XCTAssertFalse(state.needsSeniorLink)
    }

    // MARK: - Insights

    func testInsightAndAppointmentPrepNeedNoPurchase() async {
        let (state, _) = makeState()
        await state.loadCareInsight()
        XCTAssertNotNil(state.careInsight)
        await state.prepareAppointment()
        XCTAssertEqual(state.appointmentPrep?.title, "Preparation for Cardiology follow-up")
    }

    func testPrepareWithoutUpcomingAppointmentExplains() async {
        let repository = Repo()
        try? await repository.deleteAppointment(id: "appointment-maya")
        let state = AppState(repository: repository, now: { Repo.referenceDate })
        await state.prepareAppointment()
        XCTAssertNil(state.appointmentPrep)
        XCTAssertEqual(state.toastMessage, "Add an upcoming appointment first.")
    }

    func testMockAIAvoidsDiagnosisLanguage() async throws {
        let snapshot = Repo().snapshot
        let insight = try await MockAIService().careInsight(for: snapshot, seniorID: Repo.mayaID)
        let prep = try await MockAIService().appointmentPrep(for: snapshot.appointments[0], snapshot: snapshot)
        let combined = ([insight.summary, insight.suggestion, prep.safetyNote] + insight.observations + prep.observations + prep.questions)
            .joined(separator: " ").lowercased()
        XCTAssertFalse(combined.contains("diagnos") && !combined.contains("does not diagnose") && !combined.contains("not a diagnosis"))
        XCTAssertFalse(combined.contains("prescribe treatment"))
        XCTAssertFalse(combined.contains("disease probability"))
        XCTAssertTrue(combined.contains("does not diagnose, prescribe"))
    }

    // MARK: - Health sync

    func testHealthSyncOnlyRunsOnTheSeniorsOwnPhone() async {
        let (state, repository) = makeState(health: StubHealthDataProvider())
        let before = repository.snapshot.health
        XCTAssertFalse(state.canSyncHealth)

        await state.syncHealthData()

        XCTAssertEqual(state.healthSyncStatus.healthData, .idle)
        XCTAssertEqual(repository.snapshot.health, before)
    }

    func testHealthSyncWritesToLinkedSenior() async {
        let (state, repository) = makeState(profile: Repo.mayaProfileID, mayaLinked: true, health: StubHealthDataProvider())
        XCTAssertTrue(state.canSyncHealth)

        await state.syncHealthData()

        XCTAssertEqual(state.healthSyncStatus.healthData, .synced)
        XCTAssertNil(state.healthSyncStatus.lastError)
        let synced = repository.snapshot.health.filter { $0.source == "healthkit" }
        XCTAssertEqual(synced.count, 2)
        XCTAssertTrue(synced.allSatisfy { $0.seniorID == Repo.mayaID })
        XCTAssertEqual(state.latestHealth?.source, "healthkit")
    }

    func testHealthSyncWaitsForPermission() async {
        let (state, repository) = makeState(profile: Repo.mayaProfileID, mayaLinked: true,
                                            health: StubHealthDataProvider(status: .notDetermined))
        let before = repository.snapshot.health
        await state.syncHealthData()
        XCTAssertEqual(state.healthSyncStatus.healthData, .idle)
        XCTAssertEqual(repository.snapshot.health, before)
    }

    func testHealthSyncIsIdempotentPerDay() async {
        let (state, repository) = makeState(profile: Repo.mayaProfileID, mayaLinked: true, health: StubHealthDataProvider())
        await state.syncHealthData()
        await state.syncHealthData()
        XCTAssertEqual(repository.snapshot.health.filter { $0.source == "healthkit" }.count, 2)
    }

    func testRequestHealthPermissionsWithNoProvider() async {
        let (state, _) = makeState()
        do {
            try await state.requestHealthPermissions()
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(error as? CareServiceError, .vendorUnavailable)
        }
    }

    // MARK: - Plans and service boundaries

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

    func testAccessLimitsAndEntitlements() {
        XCTAssertEqual(SubscriptionAccess().seniorLimit, 1)
        XCTAssertFalse(SubscriptionAccess().canUsePremiumAI)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan"]).seniorLimit, 5)
        XCTAssertTrue(SubscriptionAccess(activeEntitlements: ["plus_plan"]).canUsePremiumAI)
        XCTAssertEqual(SubscriptionAccess(activeEntitlements: ["plus_plan", "pro_plan"]).seniorLimit, 25)
        XCTAssertTrue(SubscriptionAccess(activeEntitlements: ["premium_insights"]).canUsePremiumAI)
    }

    func testPlanServiceEnforcesSeniorLimits() {
        let planService = DefaultPlanService()
        XCTAssertTrue(planService.canAddSenior(currentCount: 0, subscription: SubscriptionAccess()))
        XCTAssertFalse(planService.canAddSenior(currentCount: 1, subscription: SubscriptionAccess()))
        XCTAssertTrue(planService.canAddSenior(currentCount: 24, subscription: SubscriptionAccess(activeEntitlements: ["pro_plan"])))
        XCTAssertFalse(planService.canAddSenior(currentCount: 25, subscription: SubscriptionAccess(activeEntitlements: ["pro_plan"])))
        XCTAssertTrue(planService.canUseCoreCare())
    }

    func testServiceErrorsHaveDescriptions() {
        for error in [CareServiceError.offline, .unauthorized, .premiumRequired, .healthPermissionDenied,
                      .vendorUnavailable, .invalidState("x"), .unknown("y")] {
            XCTAssertNotNil(error.errorDescription)
        }
    }

    func testSyncStatusTracking() {
        var status = SyncStatus()
        XCTAssertTrue(status.allSynced)
        status.careData = .syncing
        XCTAssertTrue(status.isAnySyncing)
        status.careData = .failed
        XCTAssertTrue(status.hasAnyFailed)
    }
}
