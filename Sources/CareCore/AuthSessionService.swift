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
    case signedOut
    /// Sign-up succeeded, but the address must be confirmed from the email before signing in.
    case awaitingEmailConfirmation(email: String)
    case passwordResetSent(email: String)
    /// Opened from a password-reset email: signed in only to choose a new password.
    case recoveringPassword(AuthenticatedUser)
    case signedIn(AuthenticatedUser)
}

@MainActor public protocol AuthSessionService: AnyObject {
    var state: AuthSessionState { get }
    /// Restores a persisted session without prompting the user.
    func restoreSession() async -> AuthSessionState
    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, displayName: String) async throws
    func sendPasswordReset(to email: String) async throws
    func updatePassword(_ password: String) async throws
    /// Completes email confirmation or password recovery from the deep link.
    func handleOpenURL(_ url: URL) async throws
    func signOut() async throws
}

public enum EmailAddress {
    public static func isValid(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[A-Za-z]{2,}/) != nil
    }
}

public enum PasswordPolicy {
    public static let minimumLength = 8

    /// A user-facing reason the password is not acceptable, or nil when it is.
    public static func problem(with password: String) -> String? {
        password.count < minimumLength ? "Use at least \(minimumLength) characters." : nil
    }
}
