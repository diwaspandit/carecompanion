import Foundation

/// Typed errors for care service operations
public enum CareServiceError: Error, Equatable, Sendable {
    /// Service is offline or network unavailable
    case offline

    /// User is not authorized to perform this operation
    case unauthorized

    /// Premium subscription required for this feature
    case premiumRequired

    /// HealthKit permission denied or revoked
    case healthPermissionDenied

    /// Vendor service (Supabase, RevenueCat, etc.) is unavailable
    case vendorUnavailable

    /// Invalid state for the requested operation
    case invalidState(String)

    /// Email sign-in code was wrong or expired
    case invalidCode

    /// No care account matches the invite code
    case inviteNotFound

    /// The senior record is already linked to another login
    case seniorAlreadyLinked

    /// Unknown or unexpected error
    case unknown(String)
}

extension CareServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline:
            return "Service is offline. Please check your connection."
        case .unauthorized:
            return "You are not authorized to perform this action."
        case .premiumRequired:
            return "This feature requires a premium subscription."
        case .healthPermissionDenied:
            return "Health data access was denied. You can enable it in Settings."
        case .vendorUnavailable:
            return "Service temporarily unavailable. Please try again."
        case .invalidState(let message):
            return "Invalid state: \(message)"
        case .invalidCode:
            return "That code didn't work. Check the email or send a new one."
        case .inviteNotFound:
            return "No family found for that code."
        case .seniorAlreadyLinked:
            return "This senior is already linked to another phone."
        case .unknown(let message):
            return "An error occurred: \(message)"
        }
    }
}
