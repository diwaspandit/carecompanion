import Foundation

public struct AuthenticatedUser: Equatable, Sendable {
    public let id: String
    public let email: String?

    public init(id: String, email: String?) {
        self.id = id
        self.email = email
    }
}

public enum AuthSessionState: Equatable, Sendable {
    /// Offline demo: no account, no network.
    case demo
    case signedOut
    case magicLinkSent(email: String)
    case signedIn(AuthenticatedUser)
}

@MainActor public protocol AuthSessionService: AnyObject {
    var state: AuthSessionState { get }
    /// Restores a persisted session without prompting the user.
    func restoreSession() async -> AuthSessionState
    func sendMagicLink(to email: String) async throws
    /// Completes sign-in from the magic-link deep link.
    func handleOpenURL(_ url: URL) async throws
    func signOut() async throws
}

/// Demo-mode bypass: always "signed in" to the local demo, never touches the network.
@MainActor public final class DemoAuthSessionService: AuthSessionService {
    public let state: AuthSessionState = .demo

    public init() {}

    public func restoreSession() async -> AuthSessionState { state }
    public func sendMagicLink(to email: String) async throws {}
    public func handleOpenURL(_ url: URL) async throws {}
    public func signOut() async throws {}
}

public enum EmailAddress {
    public static func isValid(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/) != nil
    }
}
