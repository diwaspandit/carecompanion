import CareCore
import Foundation
import Observation

/// Owns the app's RevenueCat lifecycle: configure once at launch, apply a cached last-known
/// entitlement set immediately for a graceful cold start, then refresh from the network — and
/// again on every app foreground and every CustomerInfo push. Demo mode (no SDK key configured)
/// leaves this entirely inert: AppState.subscription is then only ever touched by
/// DemoScenarioController / unlockPremiumPreview().
@MainActor @Observable final class SubscriptionController {
    private(set) var isRestoring = false
    private(set) var lastError: String?

    @ObservationIgnored private let service: RevenueCatSubscriptionService?
    @ObservationIgnored private let cache = SubscriptionAccessCache()

    var isConfigured: Bool { service != nil }

    /// Must configure the RevenueCat SDK before constructing RevenueCatSubscriptionService —
    /// its init touches `Purchases.shared`, which fatal-errors if `Purchases.configure()` hasn't
    /// run yet. This runs synchronously in `init()` (not the App's `.task`) because `@State`
    /// initial values are constructed before any `.task` on the view fires.
    init() {
        RevenueCatConfiguration.configureIfNeeded()
        service = RevenueCatConfiguration.isConfigured ? RevenueCatSubscriptionService() : nil
    }

    func start(applyingTo state: AppState) async {
        guard let service else { return }
        if let cached = cache.load() {
            apply(cached, to: state)
        }
        service.onCustomerInfoChanged = { [weak self, weak state] access in
            guard let self, let state else { return }
            self.apply(access, to: state)
        }
        await refresh(applyingTo: state)
    }

    func refresh(applyingTo state: AppState) async {
        guard let service else { return }
        do {
            apply(try await service.refreshAccess(), to: state)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore(applyingTo state: AppState) async {
        guard let service else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            apply(try await service.restorePurchases(), to: state)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func apply(_ access: SubscriptionAccess, to state: AppState) {
        state.applySubscriptionAccess(access)
        cache.save(access)
    }
}

/// Tiny UserDefaults cache so a cold launch can show last-known entitlements before the network
/// call returns. Never authoritative on its own — refresh() always re-verifies with RevenueCat.
private struct SubscriptionAccessCache {
    private let key = "com.carecompanion.txst.cachedEntitlements"

    func load() -> SubscriptionAccess? {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String], !raw.isEmpty else { return nil }
        return SubscriptionAccess(activeEntitlements: Set(raw))
    }

    func save(_ access: SubscriptionAccess) {
        UserDefaults.standard.set(Array(access.activeEntitlements), forKey: key)
    }
}
