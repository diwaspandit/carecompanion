import CareCore
import Foundation
import RevenueCat

/// Vendor-backed SubscriptionService. Nothing outside App/Services and PaywallHostView touches
/// RevenueCat types directly — CareCore and the rest of the app only ever see SubscriptionAccess,
/// per AGENTS.md's "Views must not call ... RevenueCat ... directly."
@MainActor final class RevenueCatSubscriptionService: NSObject, SubscriptionService {
    private(set) var currentAccess = SubscriptionAccess()
    /// Fires on any CustomerInfo push from RevenueCat (renewals, cancellations, cross-device
    /// purchases) — not just the calls this service makes itself. SubscriptionController wires
    /// this into AppState so entitlement changes reach the UI without a manual refresh.
    var onCustomerInfoChanged: ((SubscriptionAccess) -> Void)?

    override init() {
        super.init()
        Purchases.shared.delegate = self
    }

    func refreshAccess() async throws -> SubscriptionAccess {
        let info = try await Purchases.shared.customerInfo()
        let access = Self.access(from: info)
        currentAccess = access
        return access
    }

    func restorePurchases() async throws -> SubscriptionAccess {
        let info = try await Purchases.shared.restorePurchases()
        let access = Self.access(from: info)
        currentAccess = access
        return access
    }

    func presentPaywall(for context: PaywallContext) async throws {
        // Presentation itself is RevenueCatUI.PaywallView, driven by PaywallHostView. This method
        // exists only to satisfy the SubscriptionService protocol AppState depends on.
    }

    nonisolated static func access(from info: CustomerInfo) -> SubscriptionAccess {
        SubscriptionAccess(activeEntitlements: Set(info.entitlements.active.keys))
    }
}

extension RevenueCatSubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let access = Self.access(from: customerInfo)
        Task { @MainActor in
            self.currentAccess = access
            self.onCustomerInfoChanged?(access)
        }
    }
}
