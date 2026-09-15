import CareCore
import Foundation
import Supabase

/// Production CareAccountService: profile, membership and family setup through Supabase (RLS and
/// security-definer RPCs enforce the rules). Keeps the loaded repository for realtime.
@MainActor final class SupabaseCareAccountService: CareAccountService {
    private let client: SupabaseClient
    private var repository: SupabaseCareRepository?

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadProfile() async throws -> MemberProfile {
        try await mapped {
            let row: ProfileRow = try await client.from("profiles")
                .select("display_name, city").eq("id", value: try await profileID()).single().execute().value
            return MemberProfile(displayName: row.displayName, city: row.city)
        }
    }

    func updateProfile(_ profile: MemberProfile) async throws {
        try await mapped {
            try await client.from("profiles")
                .update(ProfileRow(displayName: profile.displayName, city: profile.city))
                .eq("id", value: try await profileID()).execute()
        }
    }

    func loadMembership() async throws -> CareMembership? {
        try await mapped {
            let rows: [MembershipRoleRow] = try await client.from("account_members")
                .select("account_id, role").eq("profile_id", value: try await profileID())
                .order("created_at").limit(1).execute().value
            guard let row = rows.first else {
                await stopLiveUpdates()
                repository = nil
                return nil
            }
            guard let role = CareRole(rawValue: row.role) else {
                throw CareServiceError.invalidState("Unknown member role: \(row.role)")
            }
            if let repository, repository.accountID == row.accountID {
                try await repository.refresh()
            } else {
                await stopLiveUpdates()
                repository = try await SupabaseCareRepository.load(client: client, accountID: row.accountID)
            }
            guard let repository else { return nil }
            return CareMembership(accountID: row.accountID, inviteCode: repository.inviteCode, role: role,
                                  repository: repository)
        }
    }

    func createFamily(name: String) async throws {
        try await mapped {
            try await client.rpc("create_care_account", params: ["account_name": name, "member_role": "family"]).execute()
        }
    }

    func joinFamily(inviteCode: String, role: CareRole) async throws {
        try await mapped {
            try await client.rpc("join_care_account", params: ["code": inviteCode, "member_role": role.rawValue]).execute()
        }
    }

    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws {
        guard let repository else { throw CareServiceError.invalidState("No care account loaded") }
        try await repository.addSenior(AccountSenior(id: UUID().uuidString, accountID: repository.accountID, name: name,
                                                     age: age, city: city, timeZoneIdentifier: timeZoneIdentifier))
    }

    func claimSenior(id: String) async throws {
        guard let repository else { throw CareServiceError.invalidState("No care account loaded") }
        do {
            try await repository.claimSeniorProfile(seniorID: id)
        } catch let error as PostgrestError where error.code == "23505" {
            throw CareServiceError.seniorAlreadyLinked
        }
    }

    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws {
        try await repository?.startRealtime(onChange: onChange)
    }

    func stopLiveUpdates() async {
        await repository?.stopRealtime()
    }

    private func profileID() async throws -> String {
        try await client.auth.session.user.id.uuidString.lowercased()
    }

    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}

private struct ProfileRow: Codable, Sendable {
    let displayName: String
    let city: String
    enum CodingKeys: String, CodingKey { case city, displayName = "display_name" }
}

private struct MembershipRoleRow: Decodable {
    let accountID: String
    let role: String
    enum CodingKeys: String, CodingKey { case role, accountID = "account_id" }
}
