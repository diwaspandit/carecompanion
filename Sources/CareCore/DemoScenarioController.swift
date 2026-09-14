public enum DemoScenario: String, CaseIterable, Sendable {
    case initial, checkedIn, moodRecorded, premiumUnlocked, appointmentPrepared, sosTriggered
}

@MainActor public final class DemoScenarioController {
    private let state: AppState
    public init(state: AppState) { self.state = state }
    public func reset() { state.resetDemo() }
    public func apply(_ scenario: DemoScenario) {
        reset()
        guard scenario != .initial else { return }
        state.switchToSenior()
        state.checkIn()
        guard scenario != .checkedIn else { return }
        state.recordMood(.okay)
        guard scenario != .moodRecorded else { return }
        state.switchToFamily()
        if scenario == .sosTriggered {
            state.triggerSOS()
            return
        }
        // Preview markers are deliberately separate from paid access.
        state.isPremiumPreview = true
        state.isAppointmentPreparedPreview = scenario == .appointmentPrepared
    }
}
