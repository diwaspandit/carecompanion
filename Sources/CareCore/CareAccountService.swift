import Foundation

/// The signed-in person's own profile (shown as "Diwas · Austin" on the dashboard).
public struct MemberProfile: Equatable, Sendable {
    public var displayName: String
    public var city: String

    public init(displayName: String, city: String) {
        self.displayName = displayName
        self.city = city
    }
}

/// The signed-in person's place in a family account.
@MainActor public struct CareMembership {
    public let accountID: String
    public let inviteCode: String
    public let role: CareRole
    public let repository: any CareRepository

    public init(accountID: String, inviteCode: String, role: CareRole, repository: any CareRepository) {
        self.accountID = accountID
        self.inviteCode = inviteCode
        self.role = role
        self.repository = repository
    }
}

/// Account setup for the signed-in user. Production: Supabase. Tests: in-memory fake.
@MainActor public protocol CareAccountService: AnyObject {
    func loadProfile() async throws -> MemberProfile
    func updateProfile(_ profile: MemberProfile) async throws
    /// nil when the user has not created or joined a family yet.
    func loadMembership() async throws -> CareMembership?
    /// Creates a family account with the signed-in user as a `family` member.
    func createFamily(name: String) async throws
    /// Throws `.inviteNotFound` for an unknown code.
    func joinFamily(inviteCode: String, role: CareRole) async throws
    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws
    /// Links the signed-in senior member to a senior record. Throws `.seniorAlreadyLinked` or `.unauthorized`.
    func claimSenior(id: String) async throws
    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws
    func stopLiveUpdates() async
}
