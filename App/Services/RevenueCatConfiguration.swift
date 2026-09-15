import Foundation
import RevenueCat

/// Reads the RevenueCat public iOS SDK key from git-ignored Config/Secrets.xcconfig, mirroring
/// how SupabaseConfig handles Supabase secrets. A missing key means a fresh clone stays in demo
/// mode: AppState.subscription is then only ever touched by DemoScenarioController /
/// unlockPremiumPreview(), never by this file.
enum RevenueCatConfiguration {
    private static let placeholderKey = "your-revenuecat-public-sdk-key"

    /// UI tests drive the deterministic offline Test Store paywall even when a real key is present.
    static var apiKey: String? {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return nil }
        return infoValue("RevenueCatAPIKey")
    }
    static var isConfigured: Bool { apiKey != nil }

    static func configureIfNeeded() {
        guard let apiKey, !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$("), value != placeholderKey else { return nil }
        return value
    }
}
