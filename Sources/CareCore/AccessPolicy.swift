import Foundation

/// Supply only active entitlements from the subscription provider.
public struct SubscriptionAccess: Equatable, Sendable {
    public var activeEntitlements: Set<String>

    public init(activeEntitlements: Set<String> = []) {
        self.activeEntitlements = activeEntitlements
    }

    /// Senior limit based on subscription tier
    public var seniorLimit: Int {
        if activeEntitlements.contains("pro_plan") { return 25 }
        if activeEntitlements.contains("plus_plan") { return 5 }
        return 1
    }

    /// Whether premium AI features are accessible
    public var canUsePremiumAI: Bool {
        !activeEntitlements.isDisjoint(with: ["plus_plan", "pro_plan", "premium_insights"])
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
