import CareCore
import Foundation
import Supabase

@MainActor final class SupabaseAuthSessionService: AuthSessionService {
    nonisolated static let redirectURL = URL(string: "carecompanion://login-callback")!
    /// Set when this device asked for a reset email, so the returning link opens "choose a new password".
    private static let pendingRecoveryKey = "com.carecompanion.auth.pendingPasswordRecovery"

    private(set) var state: AuthSessionState = .signedOut
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func restoreSession() async -> AuthSessionState {
        do {
            let session = try await client.auth.session
            state = .signedIn(Self.user(from: session.user))
        } catch {
            state = .signedOut
        }
        return state
    }

    func signIn(email: String, password: String) async throws {
        let email = try Self.validatedEmail(email)
        do {
            let session = try await client.auth.signIn(email: email, password: password)
            state = .signedIn(Self.user(from: session.user))
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func signUp(email: String, password: String, displayName: String) async throws {
        let email = try Self.validatedEmail(email)
        if let problem = PasswordPolicy.problem(with: password) {
            throw CareServiceError.invalidState(problem)
        }
        do {
            let metadata: [String: AnyJSON]? = displayName.isEmpty ? nil : ["display_name": .string(displayName)]
            switch try await client.auth.signUp(email: email, password: password, data: metadata, redirectTo: Self.redirectURL) {
            case .session(let session):
                state = .signedIn(Self.user(from: session.user))
            case .user:
                state = .awaitingEmailConfirmation(email: email)
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func sendPasswordReset(to email: String) async throws {
        let email = try Self.validatedEmail(email)
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: Self.redirectURL)
            UserDefaults.standard.set(true, forKey: Self.pendingRecoveryKey)
            state = .passwordResetSent(email: email)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func updatePassword(_ password: String) async throws {
        if let problem = PasswordPolicy.problem(with: password) {
            throw CareServiceError.invalidState(problem)
        }
        do {
            let user = try await client.auth.update(user: UserAttributes(password: password))
            state = .signedIn(Self.user(from: user))
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func handleOpenURL(_ url: URL) async throws {
        guard url.scheme == Self.redirectURL.scheme else { return }
        do {
            let session = try await client.auth.session(from: url)
            let user = Self.user(from: session.user)
            if UserDefaults.standard.bool(forKey: Self.pendingRecoveryKey) {
                UserDefaults.standard.removeObject(forKey: Self.pendingRecoveryKey)
                state = .recoveringPassword(user)
            } else {
                state = .signedIn(user)
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            // The SDK clears the local session even when the network call fails.
            if SupabaseErrorMapper.map(error) != .offline { throw SupabaseErrorMapper.map(error) }
        }
        state = .signedOut
    }

    /// Leaves "check your email" screens without touching the server.
    func returnToSignIn() {
        state = .signedOut
    }

    private static func validatedEmail(_ raw: String) throws -> String {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard EmailAddress.isValid(email) else {
            throw CareServiceError.invalidState("Enter a valid email address.")
        }
        return email
    }

    private static func user(from user: User) -> AuthenticatedUser {
        AuthenticatedUser(id: user.id.uuidString.lowercased(), email: user.email)
    }
}

enum SupabaseErrorMapper {
    static func map(_ error: Error) -> CareServiceError {
        if let careError = error as? CareServiceError { return careError }
        if error is URLError { return .offline }
        if let authError = error as? AuthError {
            switch authError.errorCode {
            case .sessionNotFound:
                return .unauthorized
            case .invalidCredentials:
                return .invalidState("That email and password don't match.")
            case .emailNotConfirmed:
                return .invalidState("Confirm your email with the link we sent, then sign in.")
            case .userAlreadyExists, .emailExists:
                return .invalidState("An account with this email already exists. Sign in instead.")
            case .overEmailSendRateLimit:
                return .invalidState("Too many emails were sent. Wait a few minutes and try again.")
            default:
                return .invalidState(authError.message)
            }
        }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code {
            case "42501", "PGRST301", "28000": return .unauthorized
            case "P0001", "P0002", "22023", "23514": return .invalidState(postgrest.message)
            default: return .vendorUnavailable
            }
        }
        return .vendorUnavailable
    }
}
