import CareCore
import Foundation
import Supabase

enum SupabaseConfig {
    private static let placeholderHost = "your-project-ref.supabase.co"

    static var url: URL? {
        guard let host = infoValue("SupabaseHost"), host != placeholderHost else { return nil }
        return URL(string: "https://\(host)")
    }

    static var anonKey: String? { infoValue("SupabaseAnonKey") }

    static var isConfigured: Bool { url != nil && anonKey != nil }

    /// nil when secrets are absent, so the app stays in demo mode on a fresh clone.
    static let sharedClient: SupabaseClient? = {
        guard let url, let anonKey else { return nil }
        #if os(watchOS)
        let storage: any AuthLocalStorage = WatchUnsharedSessionStorage()
        let autoRefresh = false
        #else
        let storage: any AuthLocalStorage = KeychainLocalStorage()
        let autoRefresh = true
        #endif
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    storage: storage,
                    redirectToURL: SupabaseAuthSessionService.redirectURL,
                    autoRefreshToken: autoRefresh,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

#if os(watchOS)
/// Drops an expired watch session instead of letting the SDK refresh it. Refreshing here would
/// invalidate the same login still stored on the iPhone.
private struct WatchUnsharedSessionStorage: AuthLocalStorage {
    private let backing = KeychainLocalStorage()

    func store(key: String, value: Data) throws {
        try backing.store(key: key, value: value)
    }

    func retrieve(key: String) throws -> Data? {
        guard let data = try backing.retrieve(key: key) else { return nil }
        // Only a stored login is checked. Other keychain values, such as a sign-in code, stay as they are.
        guard let token = storedAccessToken(data) else { return data }
        guard WatchAuthHandoff.accessTokenIsUsable(token) else {
            try? backing.remove(key: key)
            return nil
        }
        return data
    }

    func remove(key: String) throws {
        try backing.remove(key: key)
    }

    /// The SDK writes the session with Swift's default encoder, so the field is `accessToken`.
    private func storedAccessToken(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["accessToken"] as? String) ?? (json["access_token"] as? String)
    }
}
#endif

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
