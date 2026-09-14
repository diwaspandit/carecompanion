import Foundation

/// Service for evaluating plan-based access policies
public protocol PlanService: Sendable {
    /// Check if user can add another senior to their account
    func canAddSenior(currentCount: Int, subscription: SubscriptionAccess) -> Bool

    /// Check if user can use premium AI features
    func canUsePremiumAI(subscription: SubscriptionAccess) -> Bool

    /// Check if user can access core care features (always true for safety)
    func canUseCoreCare() -> Bool

    /// Get maximum number of seniors allowed for subscription
    func seniorLimit(for subscription: SubscriptionAccess) -> Int
}

/// Default implementation of plan service
public struct DefaultPlanService: PlanService {
    public init() {}

    public func canAddSenior(currentCount: Int, subscription: SubscriptionAccess) -> Bool {
        currentCount >= 0 && currentCount < seniorLimit(for: subscription)
    }

    public func canUsePremiumAI(subscription: SubscriptionAccess) -> Bool {
        subscription.canUsePremiumAI
    }

    public func canUseCoreCare() -> Bool {
        // Core care features (check-in, SOS, basic dashboard) are always free
        true
    }

    public func seniorLimit(for subscription: SubscriptionAccess) -> Int {
        subscription.seniorLimit
    }
}
