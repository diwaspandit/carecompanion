import CareCore
import Foundation
import Supabase

/// The signed-in user's own profile, available before they belong to a care account.
struct UserProfileDetails: Equatable, Sendable, Decodable {
    var displayName: String
    var city: String
    var phone: String

    enum CodingKeys: String, CodingKey {
        case city, phone
        case displayName = "display_name"
    }
}

/// Production CareRepository: account-scoped reads/writes through PostgREST (RLS enforced
/// server-side) plus realtime refresh. Views never see this type, only `CareRepository`.
///
/// Every write is safe to send twice: new rows carry an id generated on the device and are inserted
/// with "ignore duplicates", and updates/deletes target explicit ids. That lets transient connection
/// drops be retried without creating duplicate check-ins, medicines or messages.
@MainActor final class SupabaseCareRepository: CareRepository {
    private(set) var snapshot: CareSnapshot
    let accountID: String
    let currentProfileID: String?

    private let client: SupabaseClient
    private let now: () -> Date
    private var channel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    private static let realtimeTables = [
        "account_members", "account_seniors", "check_ins", "mood_entries", "medications", "medication_events",
        "health_snapshots", "appointments", "alerts", "emergency_contacts", "messages"
    ]

    private init(client: SupabaseClient, accountID: String, profileID: String, records: CareRecords,
                 now: @escaping () -> Date) throws {
        self.client = client
        self.accountID = accountID
        self.currentProfileID = profileID
        self.now = now
        self.snapshot = try records.snapshot(now: now())
    }

    /// Loads the signed-in user's care account. Throws `.unauthorized` without a session and
    /// `.invalidState` when the user has not created or joined an account yet.
    static func load(client: SupabaseClient, now: @escaping () -> Date = Date.init) async throws -> SupabaseCareRepository {
        do {
            let profileID = try await client.auth.session.user.id.uuidString.lowercased()
            let memberships: [MembershipRow] = try await TransientRetry.run {
                try await client.from("account_members")
                    .select("account_id")
                    .eq("profile_id", value: profileID)
                    .order("created_at")
                    .limit(1)
                    .execute().value
            }
            guard let accountID = memberships.first?.accountID else {
                throw CareServiceError.invalidState("No care account yet")
            }
            let records = try await TransientRetry.run { try await fetchRecords(client: client, accountID: accountID, now: now()) }
            return try SupabaseCareRepository(client: client, accountID: accountID, profileID: profileID,
                                              records: records, now: now)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    // MARK: - Account bootstrap (before a repository exists)

    static func loadProfile(client: SupabaseClient) async throws -> UserProfileDetails {
        do {
            let profileID = try await client.auth.session.user.id.uuidString.lowercased()
            return try await TransientRetry.run {
                try await client.from("profiles")
                    .select("display_name, city, phone")
                    .eq("id", value: profileID)
                    .single()
                    .execute().value
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    static func saveProfile(client: SupabaseClient, _ profile: UserProfileDetails) async throws {
        do {
            let profileID = try await client.auth.session.user.id.uuidString.lowercased()
            try await TransientRetry.run {
                try await client.from("profiles")
                    .update(ProfileUpdate(displayName: profile.displayName, city: profile.city, phone: profile.phone),
                            returning: .minimal)
                    .eq("id", value: profileID)
                    .execute()
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    /// Not retried: a second call would create a second family.
    static func createAccount(client: SupabaseClient, name: String, role: CareRole) async throws {
        do {
            try await client.rpc("create_care_account", params: ["account_name": name, "member_role": role.rawValue]).execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    static func joinAccount(client: SupabaseClient, inviteCode: String, role: CareRole) async throws {
        do {
            try await TransientRetry.run {
                try await client.rpc("join_care_account", params: ["code": inviteCode, "member_role": role.rawValue]).execute()
            }
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    static func deleteMyAccount(client: SupabaseClient) async throws {
        do {
            try await client.rpc("delete_my_account").execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    // MARK: - Reads

    func refresh() async throws {
        do {
            let records = try await TransientRetry.run {
                try await Self.fetchRecords(client: client, accountID: accountID, now: now())
            }
            snapshot = try records.snapshot(now: now())
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    private static func fetchRecords(client: SupabaseClient, accountID: String, now: Date) async throws -> CareRecords {
        // Two days covers "today" in every time zone; eight covers a week of history in every time zone.
        let recentEvents = iso(now.addingTimeInterval(-2 * 86_400))
        let weekOfHistory = now.addingTimeInterval(-8 * 86_400)

        async let account: CareAccountRow = client.from("care_accounts")
            .select("id, kind, name, invite_code").eq("id", value: accountID).single().execute().value
        async let members: [AccountMemberRow] = client.from("account_members")
            .select("id, account_id, profile_id, role, profiles(display_name, city, phone)")
            .eq("account_id", value: accountID).order("created_at").execute().value
        async let seniors: [AccountSeniorRow] = client.from("account_seniors")
            .select("id, account_id, name, age, city, time_zone_identifier, profile_id")
            .eq("account_id", value: accountID).is("deleted_at", value: nil).order("created_at").execute().value
        async let checkIns: [CheckInRow] = client.from("check_ins")
            .select("id, senior_id, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: recentEvents).execute().value
        async let moods: [MoodEntryRow] = client.from("mood_entries")
            .select("id, senior_id, mood, note, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: iso(weekOfHistory)).execute().value
        async let medications: [MedicationRow] = client.from("medications")
            .select("id, senior_id, name, dosage, scheduled_time")
            .eq("account_id", value: accountID).is("deleted_at", value: nil).order("scheduled_time").execute().value
        async let events: [MedicationEventRow] = client.from("medication_events")
            .select("id, medication_id, status, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: iso(weekOfHistory)).execute().value
        async let health: [HealthSnapshotRow] = client.from("health_snapshots")
            .select("id, senior_id, snapshot_date, steps, sleep_minutes, resting_heart_rate, source")
            .eq("account_id", value: accountID)
            .gte("snapshot_date", value: CareRecords.dateOnly.string(from: weekOfHistory)).execute().value
        async let appointments: [AppointmentRow] = client.from("appointments")
            .select("id, senior_id, title, clinician, scheduled_at, location, notes")
            .eq("account_id", value: accountID).is("deleted_at", value: nil)
            .gte("scheduled_at", value: iso(now.addingTimeInterval(-30 * 86_400))).execute().value
        async let alerts: [AlertRow] = client.from("alerts")
            .select("id, senior_id, occurred_at, acknowledged")
            .eq("account_id", value: accountID)
            .or("acknowledged.eq.false,occurred_at.gte.\(iso(weekOfHistory))").execute().value
        async let contacts: [EmergencyContactRow] = client.from("emergency_contacts")
            .select("id, senior_id, name, relation, phone")
            .eq("account_id", value: accountID).execute().value
        async let messages: [MessageRow] = client.from("messages")
            .select("id, sender_profile_id, body, created_at")
            .eq("account_id", value: accountID)
            .order("created_at", ascending: false).limit(300).execute().value

        return try await CareRecords(
            account: account, members: members, seniors: seniors, checkIns: checkIns, moods: moods,
            medications: medications, medicationEvents: events, health: health,
            appointments: appointments, alerts: alerts, contacts: contacts, messages: messages
        )
    }

    // MARK: - Realtime

    /// Refreshes the snapshot whenever another member changes account data, then calls `onChange`.
    func startRealtime(onChange: @escaping @MainActor () async -> Void) async throws {
        guard channel == nil else { return }
        let channel = client.channel("care-account-\(accountID)")
        let streams = Self.realtimeTables.map {
            channel.postgresChange(AnyAction.self, schema: "public", table: $0, filter: .eq("account_id", value: accountID))
        }
        self.channel = channel
        // One listener per table. Tasks created here inherit the repository's main-actor isolation,
        // so capturing `self` isn't a cross-isolation send (Swift 6 rejects the task-group version).
        for stream in streams {
            realtimeTasks.append(Task { [weak self] in
                for await _ in stream {
                    await self?.handleRealtimeChange(onChange: onChange)
                }
            })
        }
        do {
            try await channel.subscribeWithError()
        } catch {
            await stopRealtime()
            throw SupabaseErrorMapper.map(error)
        }
    }

    func stopRealtime() async {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
        if let channel {
            await client.removeChannel(channel)
        }
        channel = nil
    }

    private func handleRealtimeChange(onChange: @MainActor () async -> Void) async {
        do {
            try await refresh()
            await onChange()
        } catch {
            // Keep the last known snapshot; the next change or manual refresh retries.
        }
    }

    // MARK: - Writes

    func checkIn(seniorID: String, at date: Date) async throws {
        try await insert("check_ins", CheckInInsert(id: Self.newID(), accountID: try account(for: seniorID),
                                                    seniorID: seniorID, occurredAt: date))
    }

    func recordMood(_ mood: Mood, seniorID: String, at date: Date, note: String?) async throws {
        try await insert("mood_entries", MoodInsert(id: Self.newID(), accountID: try account(for: seniorID), seniorID: seniorID,
                                                    mood: mood.rawValue, note: note, occurredAt: date))
    }

    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {
        guard let medication = snapshot.medications.first(where: { $0.id == medicationID }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        try await insert("medication_events", MedicationEventInsert(
            id: Self.newID(), accountID: try account(for: medication.seniorID), seniorID: medication.seniorID,
            medicationID: medicationID, status: taken ? "taken" : "skipped", occurredAt: date))
    }

    func addMedication(seniorID: String, name: String, dosage: String, scheduledTime: String) async throws {
        try await insert("medications", MedicationInsert(id: Self.newID(), accountID: try account(for: seniorID),
                                                        seniorID: seniorID, name: name, dosage: dosage,
                                                        scheduledTime: scheduledTime))
    }

    func updateMedication(id: String, name: String, dosage: String, scheduledTime: String) async throws {
        try await perform {
            try await client.from("medications")
                .update(MedicationUpdate(name: name, dosage: dosage, scheduledTime: scheduledTime), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    func deleteMedication(id: String) async throws {
        try await perform {
            try await client.from("medications").update(SoftDelete(deletedAt: now()), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws {
        let rows = snapshots.compactMap { item -> HealthSnapshotUpsert? in
            guard let accountID = try? account(for: item.seniorID) else { return nil }
            return HealthSnapshotUpsert(accountID: accountID, seniorID: item.seniorID,
                                        snapshotDate: CareRecords.dateOnly.string(from: item.date),
                                        steps: item.steps, sleepMinutes: item.sleepMinutes,
                                        restingHeartRate: item.restingHeartRate, source: item.source)
        }
        guard !rows.isEmpty else { return }
        try await perform {
            try await client.from("health_snapshots")
                .upsert(rows, onConflict: "senior_id,snapshot_date,source", returning: .minimal).execute()
        }
    }

    func saveAppointment(_ appointment: Appointment) async throws {
        let accountID = try account(for: appointment.seniorID)
        if appointment.id.isEmpty {
            try await insert("appointments", AppointmentInsert(
                id: Self.newID(), accountID: accountID, seniorID: appointment.seniorID, title: appointment.title,
                clinician: appointment.clinician, scheduledAt: appointment.date, location: appointment.location,
                notes: appointment.notes))
        } else {
            let row = AppointmentUpdate(title: appointment.title, clinician: appointment.clinician,
                                        scheduledAt: appointment.date, location: appointment.location, notes: appointment.notes)
            try await perform {
                try await client.from("appointments").update(row, returning: .minimal).eq("id", value: appointment.id).execute()
            }
        }
    }

    func deleteAppointment(id: String) async throws {
        try await perform {
            try await client.from("appointments").update(SoftDelete(deletedAt: now()), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    func triggerSOS(seniorID: String, at date: Date) async throws {
        let row = AlertInsert(id: Self.newID(), accountID: try account(for: seniorID), seniorID: seniorID,
                              kind: "sos", occurredAt: date)
        do {
            try await TransientRetry.run {
                try await client.from("alerts").upsert(row, onConflict: "id", returning: .minimal, ignoreDuplicates: true).execute()
            }
        } catch let error as PostgrestError where error.code == "23505" {
            // An open SOS already exists for this senior: SOS is idempotent.
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
        try await refresh()
    }

    func acknowledgeAlerts(seniorID: String) async throws {
        try await perform {
            try await client.from("alerts")
                .update(AlertAcknowledgement(acknowledgedAt: now(), acknowledgedBy: currentProfileID), returning: .minimal)
                .eq("senior_id", value: seniorID).eq("acknowledged", value: false).execute()
        }
    }

    func addSenior(_ senior: AccountSenior) async throws {
        try await insert("account_seniors", SeniorInsert(
            id: Self.newID(), accountID: accountID, name: senior.name, age: senior.age, city: senior.city,
            timeZoneIdentifier: senior.timeZoneIdentifier, profileID: senior.profileID))
    }

    func updateSenior(_ senior: AccountSenior) async throws {
        try await perform {
            try await client.from("account_seniors")
                .update(SeniorUpdate(name: senior.name, age: senior.age, city: senior.city,
                                     timeZoneIdentifier: senior.timeZoneIdentifier), returning: .minimal)
                .eq("id", value: senior.id).execute()
        }
    }

    func removeSenior(id: String) async throws {
        try await perform {
            try await client.from("account_seniors").update(SoftDelete(deletedAt: now()), returning: .minimal)
                .eq("id", value: id).execute()
        }
    }

    func claimSenior(id: String) async throws {
        try await perform {
            try await client.rpc("claim_senior", params: ["target_senior_id": id]).execute()
        }
    }

    func saveEmergencyContact(_ contact: EmergencyContact) async throws {
        let accountID = try account(for: contact.seniorID)
        if contact.id.isEmpty {
            try await insert("emergency_contacts", EmergencyContactInsert(
                id: Self.newID(), accountID: accountID, seniorID: contact.seniorID, name: contact.name,
                relation: contact.relation, phone: contact.phone))
        } else {
            try await perform {
                try await client.from("emergency_contacts")
                    .update(EmergencyContactUpdate(name: contact.name, relation: contact.relation, phone: contact.phone),
                            returning: .minimal)
                    .eq("id", value: contact.id).execute()
            }
        }
    }

    func deleteEmergencyContact(id: String) async throws {
        try await perform {
            try await client.from("emergency_contacts").delete(returning: .minimal).eq("id", value: id).execute()
        }
    }

    func sendMessage(_ body: String) async throws {
        try await insert("messages", MessageInsert(id: Self.newID(), accountID: accountID, body: body))
    }

    func updateProfile(displayName: String, city: String, phone: String) async throws {
        guard let currentProfileID else { throw CareServiceError.unauthorized }
        try await perform {
            try await client.from("profiles")
                .update(ProfileUpdate(displayName: displayName, city: city, phone: phone), returning: .minimal)
                .eq("id", value: currentProfileID).execute()
        }
    }

    // MARK: - Helpers

    private func account(for seniorID: String) throws -> String {
        guard let senior = snapshot.seniors.first(where: { $0.id == seniorID }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        return senior.accountID
    }

    /// Inserts a row whose id was generated on the device; a retried duplicate is ignored.
    private func insert(_ table: String, _ row: some Encodable & Sendable) async throws {
        try await perform {
            try await client.from(table).upsert(row, onConflict: "id", returning: .minimal, ignoreDuplicates: true).execute()
        }
    }

    /// Runs an idempotent write (retrying a dropped connection once), then re-reads so `snapshot`
    /// reflects server-side defaults and triggers.
    private func perform(_ write: () async throws -> Void) async throws {
        do {
            try await TransientRetry.run(write)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
        try await refresh()
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}

// MARK: - Write payloads

private struct MembershipRow: Decodable {
    let accountID: String
    enum CodingKeys: String, CodingKey { case accountID = "account_id" }
}

private struct ProfileUpdate: Encodable, Sendable {
    let displayName: String, city: String, phone: String
    enum CodingKeys: String, CodingKey { case city, phone, displayName = "display_name" }
}

private struct SoftDelete: Encodable, Sendable {
    let deletedAt: Date
    enum CodingKeys: String, CodingKey { case deletedAt = "deleted_at" }
}

private struct CheckInInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case id, accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
    }
}

private struct MoodInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, mood: String, note: String?, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case id, mood, note, accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
    }
}

private struct MedicationInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, name: String, dosage: String, scheduledTime: String
    enum CodingKeys: String, CodingKey {
        case id, name, dosage, accountID = "account_id", seniorID = "senior_id", scheduledTime = "scheduled_time"
    }
}

private struct MedicationUpdate: Encodable, Sendable {
    let name: String, dosage: String, scheduledTime: String
    enum CodingKeys: String, CodingKey { case name, dosage, scheduledTime = "scheduled_time" }
}

private struct MedicationEventInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, medicationID: String, status: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case id, status, accountID = "account_id", seniorID = "senior_id",
             medicationID = "medication_id", occurredAt = "occurred_at"
    }
}

private struct HealthSnapshotUpsert: Encodable, Sendable {
    let accountID: String, seniorID: String, snapshotDate: String
    let steps: Int, sleepMinutes: Int, restingHeartRate: Int, source: String
    enum CodingKeys: String, CodingKey {
        case steps, source, accountID = "account_id", seniorID = "senior_id",
             snapshotDate = "snapshot_date", sleepMinutes = "sleep_minutes",
             restingHeartRate = "resting_heart_rate"
    }
}

private struct AppointmentInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, title: String, clinician: String
    let scheduledAt: Date, location: String, notes: String
    enum CodingKeys: String, CodingKey {
        case id, title, clinician, location, notes, accountID = "account_id",
             seniorID = "senior_id", scheduledAt = "scheduled_at"
    }
}

private struct AppointmentUpdate: Encodable, Sendable {
    let title: String, clinician: String, scheduledAt: Date, location: String, notes: String
    enum CodingKeys: String, CodingKey {
        case title, clinician, location, notes, scheduledAt = "scheduled_at"
    }
}

private struct AlertInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, kind: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case id, kind, accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
    }
}

private struct AlertAcknowledgement: Encodable, Sendable {
    let acknowledged = true
    let acknowledgedAt: Date
    let acknowledgedBy: String?
    enum CodingKeys: String, CodingKey {
        case acknowledged, acknowledgedAt = "acknowledged_at", acknowledgedBy = "acknowledged_by"
    }
}

private struct SeniorInsert: Encodable, Sendable {
    let id: String, accountID: String, name: String, age: Int, city: String, timeZoneIdentifier: String, profileID: String?
    enum CodingKeys: String, CodingKey {
        case id, name, age, city, accountID = "account_id", timeZoneIdentifier = "time_zone_identifier",
             profileID = "profile_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(name, forKey: .name)
        try container.encode(age, forKey: .age)
        try container.encode(city, forKey: .city)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
        try container.encodeIfPresent(profileID, forKey: .profileID)
    }
}

private struct SeniorUpdate: Encodable, Sendable {
    let name: String, age: Int, city: String, timeZoneIdentifier: String
    enum CodingKeys: String, CodingKey {
        case name, age, city, timeZoneIdentifier = "time_zone_identifier"
    }
}

private struct EmergencyContactInsert: Encodable, Sendable {
    let id: String, accountID: String, seniorID: String, name: String, relation: String, phone: String
    enum CodingKeys: String, CodingKey {
        case id, name, relation, phone, accountID = "account_id", seniorID = "senior_id"
    }
}

private struct EmergencyContactUpdate: Encodable, Sendable {
    let name: String, relation: String, phone: String
}

private struct MessageInsert: Encodable, Sendable {
    let id: String, accountID: String, body: String
    enum CodingKeys: String, CodingKey { case id, body, accountID = "account_id" }
}
