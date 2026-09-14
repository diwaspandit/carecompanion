import Foundation

@main
struct CoreSmoke {
    @MainActor static func main() {
        let state = AppState(repository: DemoCareRepository())
        let seed = state.snapshot
        precondition(seed.seniors.first?.name == "Maya Sharma")
        precondition(seed.health.first?.steps == 2840)
        precondition(seed.health.count == 7)
        precondition(seed.medications.filter(\.taken).count == 3)
        state.checkIn()
        state.checkIn()
        state.role = .family
        precondition(state.isCheckedIn && state.snapshot.checkIns.count == 1)
        state.recordMood(.low)
        precondition(state.currentMood == .low)
        state.triggerSOS()
        state.triggerSOS()
        precondition(state.hasEmergency && state.snapshot.alerts.count == 1)
        state.acknowledgeEmergency()
        precondition(!state.hasEmergency)
        let controller = DemoScenarioController(state: state)
        controller.apply(.premiumUnlocked)
        precondition(state.isPremiumPreview && !state.subscription.canUsePremiumAI)
        state.subscription = SubscriptionAccess(activeEntitlements: ["plus_plan"])
        controller.reset()
        precondition(state.snapshot == seed && state.role == nil)
        precondition(state.subscription.canUsePremiumAI && state.subscription.seniorLimit == 5)
        for scenario in DemoScenario.allCases {
            controller.apply(scenario)
            let first = state.snapshot
            controller.apply(scenario)
            precondition(state.snapshot == first)
        }
        print("Core smoke checks passed: seed, check-in, mood, SOS, access, reset, six repeatable scenarios.")
    }
}
