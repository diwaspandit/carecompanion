import CareCore
import Foundation
import Supabase

@MainActor final class SupabaseAuthSessionService: AuthSessionService {
    nonisolated static let redirectURL = URL(string: "carecompanion://login-callback")!

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

    func sendEmailCode(to email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isValid(email) else {
            throw CareServiceError.invalidState("Enter a valid email address")
        }
        do {
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
            state = .codeSent(email: email)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        do {
            let response = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .email)
            guard case .session(let session) = response else { throw CareServiceError.invalidCode }
            state = .signedIn(Self.user(from: session.user))
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Test accounts only; the UI offers it in DEBUG builds.
    func signIn(email: String, password: String) async throws {
        do {
            let session = try await client.auth.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            state = .signedIn(Self.user(from: session.user))
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            // Local session is cleared by the SDK even when the network call fails.
            if SupabaseErrorMapper.map(error) != .offline { throw SupabaseErrorMapper.map(error) }
        }
        state = .signedOut
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
            if case .sessionMissing = authError { return .unauthorized }
            if authError.errorCode == .otpExpired || authError.errorCode == .invalidCredentials { return .invalidCode }
            return .vendorUnavailable
        }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code {
            case "42501", "PGRST301", "28000": return .unauthorized
            case "P0002": return .inviteNotFound
            default: return .vendorUnavailable
            }
        }
        return .vendorUnavailable
    }
}
