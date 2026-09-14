import Foundation

/// Supply only active entitlements from the subscription provider.
public struct SubscriptionAccess: Equatable, Sendable {
    public var activeEntitlements: Set<String>
    public init(activeEntitlements: Set<String> = []) { self.activeEntitlements = activeEntitlements }
    public var seniorLimit: Int {
        if activeEntitlements.contains("pro_plan") { return 25 }
        if activeEntitlements.contains("plus_plan") { return 5 }
        return 1
    }
    public var canUsePremiumAI: Bool {
        !activeEntitlements.isDisjoint(with: ["plus_plan", "pro_plan", "premium_insights"])
    }
}
@MainActor public protocol SubscriptionService {
    func refreshAccess() async throws -> SubscriptionAccess
    func restorePurchases() async throws -> SubscriptionAccess
}
public struct AccessPolicy: Sendable {
    public let subscription: SubscriptionAccess
    public init(subscription: SubscriptionAccess) { self.subscription = subscription }
    public func canAddSenior(currentCount: Int) -> Bool { currentCount >= 0 && currentCount < subscription.seniorLimit }
    public var canUsePremiumAI: Bool { subscription.canUsePremiumAI }
    public var canUseCoreCare: Bool { true }
}
