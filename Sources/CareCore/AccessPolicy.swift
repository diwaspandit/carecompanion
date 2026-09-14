import Foundation

/// The four plan tiers. Free/Plus/Pro are real, RevenueCat-backed tiers (see docs/REVENUECAT.md).
/// Enterprise is architecture-only for this build: AGENTS.md's "Organization — Future" section
/// excludes production enterprise billing and organization UI from the hackathon build, so
/// `enterprise_plan` has no StoreKit product yet. It exists so PlanCatalog can show it as a
/// "contact us" tier and so a future sales-configured seat count has somewhere to live.
public enum PlanTier: String, CaseIterable, Identifiable, Sendable {
    case free, plus, pro, enterprise
    public var id: String { rawValue }
}

/// Supply only active entitlements from the subscription provider.
public struct SubscriptionAccess: Equatable, Sendable {
    public var activeEntitlements: Set<String>
    /// Only meaningful when `enterprise_plan` is active. There is no self-serve StoreKit product
    /// for Enterprise in this build (seat count can't be typed in at checkout — see
    /// docs/REVENUECAT.md), so this stays nil until a future sales-configured value (e.g. cached
    /// from Supabase `subscription_statuses.seat_limit`) is wired up.
    public var enterpriseSeatLimit: Int?

    public init(activeEntitlements: Set<String> = [], enterpriseSeatLimit: Int? = nil) {
        self.activeEntitlements = activeEntitlements
        self.enterpriseSeatLimit = enterpriseSeatLimit
    }

    public var tier: PlanTier {
        if activeEntitlements.contains("enterprise_plan") { return .enterprise }
        if activeEntitlements.contains("pro_plan") { return .pro }
        if activeEntitlements.contains("plus_plan") { return .plus }
        return .free
    }

    /// Senior limit based on subscription tier
    public var seniorLimit: Int {
        switch tier {
        case .enterprise: return enterpriseSeatLimit ?? Int.max
        case .pro: return 25
        case .plus: return 5
        case .free: return 1
        }
    }

    /// Whether premium AI features are accessible
    public var canUsePremiumAI: Bool {
        !activeEntitlements.isDisjoint(with: ["plus_plan", "pro_plan", "enterprise_plan", "premium_insights"])
    }
}

/// Access policy evaluator
public struct AccessPolicy: Sendable {
    public let subscription: SubscriptionAccess
    private let planService: any PlanService

    public init(subscription: SubscriptionAccess, planService: any PlanService = DefaultPlanService()) {
        self.subscription = subscription
        self.planService = planService
    }

    /// Check if a senior can be added to the account
    public func canAddSenior(currentCount: Int) -> Bool {
        planService.canAddSenior(currentCount: currentCount, subscription: subscription)
    }

    /// Check if premium AI features can be used
    public var canUsePremiumAI: Bool {
        planService.canUsePremiumAI(subscription: subscription)
    }

    /// Check if core care features can be used (always true)
    public var canUseCoreCare: Bool {
        planService.canUseCoreCare()
    }
}
