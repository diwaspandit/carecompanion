import Foundation

/// Service for managing subscription status and entitlements
@MainActor public protocol SubscriptionService: AnyObject {
    /// Current subscription access level
    var currentAccess: SubscriptionAccess { get }

    /// Refresh entitlement information from the provider
    func refreshAccess() async throws -> SubscriptionAccess

    /// Restore previous purchases
    func restorePurchases() async throws -> SubscriptionAccess

    /// Present paywall for the given context
    func presentPaywall(for context: PaywallContext) async throws
}

/// Demo implementation that simulates subscription behavior
@MainActor public final class DemoSubscriptionService: SubscriptionService {
    public private(set) var currentAccess: SubscriptionAccess

    public init(access: SubscriptionAccess = SubscriptionAccess()) {
        self.currentAccess = access
    }

    public func refreshAccess() async throws -> SubscriptionAccess {
        // In demo mode, return current access without network call
        return currentAccess
    }

    public func restorePurchases() async throws -> SubscriptionAccess {
        // In demo mode, simulate restore with no changes
        return currentAccess
    }

    public func presentPaywall(for context: PaywallContext) async throws {
        // In demo mode, paywall presentation is handled by the UI layer
        // This is a no-op in the demo service
    }

    /// Update access for demo purposes
    public func updateAccess(_ access: SubscriptionAccess) {
        currentAccess = access
    }
}
