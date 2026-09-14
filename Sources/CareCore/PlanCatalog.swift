import Foundation

/// Marketing-facing description of one plan tier, driving the Compare Plans screen.
/// `isPurchasable` distinguishes real RevenueCat-backed tiers (Plus, Pro) from Free (no purchase
/// needed) and Enterprise (a "contact us" stub — see AGENTS.md's "Organization — Future" section;
/// this build intentionally does not sell Enterprise through StoreKit/RevenueCat).
public struct PlanDescriptor: Identifiable, Sendable {
    public let tier: PlanTier
    public let title: String
    public let seniorLimitDescription: String
    public let features: [String]
    public let isPurchasable: Bool
    public var id: PlanTier { tier }
}

public enum PlanCatalog {
    public static let all: [PlanDescriptor] = [
        PlanDescriptor(
            tier: .free,
            title: "Free",
            seniorLimitDescription: "1 monitored senior",
            features: ["Check-in", "SOS", "Medications", "Mood", "Basic dashboard", "Manual appointments", "Basic health metrics"],
            isPurchasable: false
        ),
        PlanDescriptor(
            tier: .plus,
            title: "Plus",
            seniorLimitDescription: "Up to 5 monitored seniors",
            features: ["Everything in Free", "AI Care Insights", "AI Appointment Prep", "Premium health explanations"],
            isPurchasable: true
        ),
        PlanDescriptor(
            tier: .pro,
            title: "Pro",
            seniorLimitDescription: "Up to 25 monitored seniors",
            features: ["Everything in Plus", "Larger family care networks"],
            isPurchasable: true
        ),
        PlanDescriptor(
            tier: .enterprise,
            title: "Enterprise",
            seniorLimitDescription: "Seat count scaled to your organization",
            features: ["Everything in Pro", "Custom seat count", "Dedicated onboarding"],
            isPurchasable: false
        )
    ]
}
