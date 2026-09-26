import Foundation
import Supabase
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Registers this device with Apple, then stores the token for the signed-in senior.
enum PushRegistration {
    #if os(iOS)
    static let platform = "ios"
    #else
    static let platform = "watch"
    #endif

    private static let storageKey = "carecompanion.pushToken"
    /// Set by the phone or watch session so a token that arrives early is still saved.
    nonisolated(unsafe) static var readyToUpload: (@MainActor () async -> Void)?

    static var storedToken: String? {
        UserDefaults.standard.string(forKey: storageKey)
    }

    static func registerWithSystem() {
        DispatchQueue.main.async {
            #if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
            #elseif os(watchOS)
            WKApplication.shared().registerForRemoteNotifications()
            #endif
        }
    }

    static func store(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: storageKey)
        let callback = readyToUpload
        Task { @MainActor in
            await callback?()
        }
    }

    static func upload(using client: SupabaseClient) async {
        guard let token = storedToken else { return }
        try? await client.rpc(
            "register_device_token",
            params: ["device_token": token, "device_platform": platform]
        ).execute()
    }
}
