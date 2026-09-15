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
    case codeSent(email: String)
    case signedIn(AuthenticatedUser)
}

@MainActor public protocol AuthSessionService: AnyObject {
    var state: AuthSessionState { get }
    /// Restores a persisted session without prompting the user.
    func restoreSession() async -> AuthSessionState
    /// Emails a one-time sign-in code. Creates the user if the email is new.
    func sendEmailCode(to email: String) async throws
    /// Completes sign-in with the emailed code. Throws `.invalidCode` when it is wrong or expired.
    func verifyEmailCode(_ code: String, email: String) async throws
    /// Test accounts only; the UI offers it in DEBUG builds.
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}

/// Demo-mode bypass: always "signed in" to the local demo, never touches the network.
@MainActor public final class DemoAuthSessionService: AuthSessionService {
    public let state: AuthSessionState = .demo

    public init() {}

    public func restoreSession() async -> AuthSessionState { state }
    public func sendEmailCode(to email: String) async throws {}
    public func verifyEmailCode(_ code: String, email: String) async throws {}
    public func signIn(email: String, password: String) async throws {}
    public func signOut() async throws {}
}

public enum EmailAddress {
    public static func isValid(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/) != nil
    }
}
