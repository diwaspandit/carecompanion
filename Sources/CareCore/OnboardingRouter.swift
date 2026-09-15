import Foundation

/// Where the app is between launch and the care screens.
public enum SessionPhase: Equatable, Sendable {
    case restoring
    case welcome
    case enterEmail
    case enterCode(email: String)
    case needsProfile
    case needsFamily
    case needsSenior
    case inviteFamily(code: String)
    /// Senior member choosing which senior record is them; empty until the family adds one.
    case needsSeniorLink([AccountSenior])
    case unreachable
    case ready
    case demo
}

/// Picks the next onboarding step from server state, so relaunching mid-setup resumes correctly.
public enum OnboardingRouter {
    @MainActor
    public static func nextPhase(profile: MemberProfile, membership: CareMembership?,
                                 signedInProfileID: String, justCreatedFamily: Bool) -> SessionPhase {
        guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .needsProfile }
        guard let membership else { return .needsFamily }
        let seniors = membership.repository.snapshot.seniors
        switch membership.role {
        case .family:
            if seniors.isEmpty { return .needsSenior }
            if justCreatedFamily { return .inviteFamily(code: membership.inviteCode) }
            return .ready
        case .senior:
            if seniors.contains(where: { $0.profileID == signedInProfileID }) { return .ready }
            return .needsSeniorLink(seniors.filter { $0.profileID == nil })
        }
    }
}
