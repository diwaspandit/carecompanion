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

    func sendMagicLink(to email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isValid(email) else {
            throw CareServiceError.invalidState("Enter a valid email address")
        }
        do {
            try await client.auth.signInWithOTP(email: email, redirectTo: Self.redirectURL)
            state = .magicLinkSent(email: email)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func handleOpenURL(_ url: URL) async throws {
        guard url.scheme == Self.redirectURL.scheme else { return }
        do {
            let session = try await client.auth.session(from: url)
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
        if let authError = error as? AuthError, case .sessionMissing = authError { return .unauthorized }
        if let postgrest = error as? PostgrestError {
            switch postgrest.code {
            case "42501", "PGRST301", "28000": return .unauthorized
            case "P0002": return .invalidState(postgrest.message)
            default: return .vendorUnavailable
            }
        }
        return .vendorUnavailable
    }
}
