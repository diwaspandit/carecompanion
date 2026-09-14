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
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: SupabaseAuthSessionService.redirectURL,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
