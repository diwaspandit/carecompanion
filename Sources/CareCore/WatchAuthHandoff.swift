import Foundation

/// The signed-in account the iPhone sends to its paired watch. Tokens travel only over
/// Watch Connectivity between those two devices.
public struct WatchAuthHandoff: Equatable, Sendable {
    public enum Status: String, Sendable {
        case ready
        case signedOut
        case notSenior
        case needsLink
        /// The iPhone app is open but has not finished loading the account yet.
        case unavailable
    }

    public var status: Status
    public var accessToken: String?
    public var refreshToken: String?

    public init(status: Status, accessToken: String? = nil, refreshToken: String? = nil) {
        self.status = status
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public var dictionary: [String: String] {
        var payload = ["status": status.rawValue]
        if let accessToken { payload["accessToken"] = accessToken }
        if let refreshToken { payload["refreshToken"] = refreshToken }
        return payload
    }

    public init?(dictionary: [String: Any]) {
        guard let raw = dictionary["status"] as? String, let status = Status(rawValue: raw) else { return nil }
        self.status = status
        accessToken = dictionary["accessToken"] as? String
        refreshToken = dictionary["refreshToken"] as? String
    }

    /// True when the access token can be used as-is. An expired token must not be refreshed on the
    /// watch: the iPhone and the watch share one refresh token, and a second refresh signs both out.
    public static func accessTokenIsUsable(_ token: String, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let payload = decodeJWTPart(String(parts[1])) else { return false }
        guard let exp = (payload["exp"] as? NSNumber)?.doubleValue else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSince(now) > 30
    }

    private static func decodeJWTPart(_ value: String) -> [String: Any]? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
