import Foundation
import Observation

@MainActor @Observable public final class AppState {
    public var role: CareRole?
    public var screen: AppScreen = .onboarding
    public var seniorTab: SeniorTab = .home
    public var familyTab: FamilyTab = .dashboard
    public var paywallContext: PaywallContext?
    public var toastMessage: String?
    public var careInsight: CareInsight?
    public var appointmentPrep: AppointmentPrep?
    public private(set) var snapshot: CareSnapshot
    public var subscription = SubscriptionAccess()
    public internal(set) var isPremiumPreview = false
    public internal(set) var isAppointmentPreparedPreview = false
    public private(set) var selectedSeniorID: String
    @ObservationIgnored private let repository: any CareRepository
    @ObservationIgnored private let now: () -> Date

    public init(repository: any CareRepository, now: @escaping () -> Date = { DemoCareRepository.referenceDate }) {
        self.repository = repository
        self.now = now
        snapshot = repository.snapshot
        selectedSeniorID = repository.snapshot.seniors.first?.id ?? ""
    }
    public var selectedSenior: AccountSenior? { snapshot.seniors.first { $0.id == selectedSeniorID } }
    public var isCheckedIn: Bool { snapshot.checkIns.contains { $0.seniorID == selectedSeniorID } }
    public var currentMood: Mood? { snapshot.moods.last { $0.seniorID == selectedSeniorID }?.mood }
    public var hasEmergency: Bool { snapshot.alerts.contains { $0.seniorID == selectedSeniorID && !$0.acknowledged } }
    public var hasPremiumAccess: Bool { subscription.canUsePremiumAI || isPremiumPreview }
    public var medicationsTakenCount: Int { snapshot.medications.filter { $0.seniorID == selectedSeniorID && $0.taken }.count }
    public var latestHealth: HealthSnapshot? { snapshot.health.first { $0.seniorID == selectedSeniorID } }
    public var selectedAppointment: Appointment? { snapshot.appointments.first { $0.seniorID == selectedSeniorID } }
    public var activeDemoAlertCount: Int {
        var count = 1 // Activity below baseline is part of the deterministic demo story.
        if medicationsTakenCount < snapshot.medications.filter({ $0.seniorID == selectedSeniorID }).count { count += 1 }
        if !isCheckedIn { count += 1 }
        if hasEmergency { count += 1 }
        return count
    }

    public func selectSenior(id: String) {
        guard snapshot.seniors.contains(where: { $0.id == id }) else { return }
        selectedSeniorID = id
    }
    public func chooseRole(_ newRole: CareRole) {
        role = newRole
        screen = newRole == .senior ? .seniorHome : .familyDashboard
        seniorTab = .home
        familyTab = hasEmergency ? .emergency : .dashboard
    }
    public func switchToSenior(tab: SeniorTab = .home) {
        role = .senior
        screen = .seniorHome
        seniorTab = tab
    }
    public func switchToFamily(tab: FamilyTab = .dashboard) {
        role = .family
        screen = .familyDashboard
        familyTab = hasEmergency ? .emergency : tab
    }
    public func refresh() async {
        do {
            try await repository.refresh()
            snapshot = repository.snapshot
            if !snapshot.seniors.contains(where: { $0.id == selectedSeniorID }) {
                selectedSeniorID = snapshot.seniors.first?.id ?? ""
            }
        } catch {
            showDemoToast("Couldn't refresh care data: \(error.localizedDescription)")
        }
    }

    public func checkIn() async {
        do {
            try await repository.checkIn(seniorID: selectedSeniorID, at: now())
            snapshot = repository.snapshot
            seniorTab = .mood
            showDemoToast("Maya's check-in is now visible to Diwas.")
        } catch {
            showDemoToast("Check-in failed: \(error.localizedDescription)")
        }
    }

    public func recordMood(_ mood: Mood) async {
        do {
            try await repository.recordMood(mood, seniorID: selectedSeniorID, at: now())
            snapshot = repository.snapshot
            showDemoToast("Mood recorded for today's care context.")
        } catch {
            showDemoToast("Failed to record mood: \(error.localizedDescription)")
        }
    }

    public func toggleMedication(id: String) async {
        do {
            try await repository.toggleMedication(id: id)
            snapshot = repository.snapshot
        } catch {
            showDemoToast("Failed to update medication: \(error.localizedDescription)")
        }
    }

    public func triggerSOS() async {
        do {
            try await repository.triggerSOS(seniorID: selectedSeniorID, at: now())
            snapshot = repository.snapshot
            familyTab = .emergency
            showDemoToast("SOS alert is active for the family dashboard.")
        } catch {
            showDemoToast("Failed to trigger SOS: \(error.localizedDescription)")
        }
    }

    public func acknowledgeEmergency() async {
        do {
            try await repository.acknowledgeAlerts(seniorID: selectedSeniorID)
            snapshot = repository.snapshot
            familyTab = .dashboard
        } catch {
            showDemoToast("Failed to acknowledge emergency: \(error.localizedDescription)")
        }
    }
    public func showPaywall(for context: PaywallContext) {
        paywallContext = context
    }
    public func unlockPremiumPreview() {
        isPremiumPreview = true
        subscription = SubscriptionAccess(activeEntitlements: ["premium_insights"])
        paywallContext = nil
        showDemoToast("Premium AI unlocked for the demo.")
    }
    public func loadCareInsight(using service: any AIService = MockAIService()) async {
        guard hasPremiumAccess else {
            showPaywall(for: .careInsight)
            return
        }
        careInsight = try? await service.careInsight(for: snapshot, seniorID: selectedSeniorID)
    }
    public func prepareAppointment(using service: any AIService = MockAIService()) async {
        guard hasPremiumAccess else {
            showPaywall(for: .appointmentPrep)
            return
        }
        guard let appointment = selectedAppointment else { return }
        appointmentPrep = try? await service.appointmentPrep(for: appointment, snapshot: snapshot)
        isAppointmentPreparedPreview = appointmentPrep != nil
        showDemoToast("Appointment preparation is ready.")
    }
    public func showDemoToast(_ message: String) {
        toastMessage = message
    }
    public func clearToast() {
        toastMessage = nil
    }
    public func resetDemo() async {
        await repository.reset()
        snapshot = repository.snapshot
        selectedSeniorID = snapshot.seniors.first?.id ?? ""
        role = nil
        screen = .onboarding
        seniorTab = .home
        familyTab = .dashboard
        paywallContext = nil
        toastMessage = nil
        careInsight = nil
        appointmentPrep = nil
        isPremiumPreview = false
        isAppointmentPreparedPreview = false
    }
}
