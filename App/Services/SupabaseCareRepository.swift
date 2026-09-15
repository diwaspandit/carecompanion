import CareCore
import Foundation
import Supabase

/// Production CareRepository: account-scoped reads/writes through PostgREST (RLS enforced
/// server-side) plus realtime refresh. Views never see this type, only `CareRepository`.
@MainActor final class SupabaseCareRepository: CareRepository {
    private(set) var snapshot: CareSnapshot
    let accountID: String
    let inviteCode: String

    private let client: SupabaseClient
    private let now: () -> Date
    private var channel: RealtimeChannelV2?
    private var realtimeTasks: [Task<Void, Never>] = []

    private static let realtimeTables = [
        "check_ins", "mood_entries", "medications", "medication_events",
        "health_snapshots", "appointments", "alerts", "appointment_ai_preps"
    ]

    private init(client: SupabaseClient, accountID: String, records: CareRecords, now: @escaping () -> Date) throws {
        self.client = client
        self.accountID = accountID
        self.inviteCode = records.account.inviteCode
        self.now = now
        self.snapshot = try records.snapshot(now: now())
    }

    /// Loads the signed-in user's care account. Throws `.unauthorized` without a session and
    /// `.invalidState` when the user has not created or joined an account yet.
    static func load(client: SupabaseClient, now: @escaping () -> Date = Date.init) async throws -> SupabaseCareRepository {
        do {
            let session = try await client.auth.session
            let memberships: [MembershipRow] = try await client.from("account_members")
                .select("account_id")
                .eq("profile_id", value: session.user.id)
                .order("created_at")
                .limit(1)
                .execute().value
            guard let accountID = memberships.first?.accountID else {
                throw CareServiceError.invalidState("No care account yet")
            }
            let records = try await fetchRecords(client: client, accountID: accountID, now: now())
            return try SupabaseCareRepository(client: client, accountID: accountID, records: records, now: now)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    static func createAccount(client: SupabaseClient, name: String, role: CareRole) async throws {
        do {
            try await client.rpc("create_care_account", params: ["account_name": name, "member_role": role.rawValue]).execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    static func joinAccount(client: SupabaseClient, inviteCode: String, role: CareRole) async throws {
        do {
            try await client.rpc("join_care_account", params: ["code": inviteCode, "member_role": role.rawValue]).execute()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    // MARK: - Reads

    func refresh() async throws {
        do {
            let records = try await Self.fetchRecords(client: client, accountID: accountID, now: now())
            snapshot = try records.snapshot(now: now())
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    private static func fetchRecords(client: SupabaseClient, accountID: String, now: Date) async throws -> CareRecords {
        // Two days covers "today" in every time zone; a week of health and alert history.
        let recentEvents = iso(now.addingTimeInterval(-2 * 86_400))
        let weekAgo = now.addingTimeInterval(-7 * 86_400)

        async let account: CareAccountRow = client.from("care_accounts")
            .select("id, kind, name, invite_code").eq("id", value: accountID).single().execute().value
        async let members: [AccountMemberRow] = client.from("account_members")
            .select("id, account_id, profile_id, role, profiles(display_name, city)")
            .eq("account_id", value: accountID).order("created_at").execute().value
        async let seniors: [AccountSeniorRow] = client.from("account_seniors")
            .select("id, account_id, profile_id, name, age, city, time_zone_identifier")
            .eq("account_id", value: accountID).is("deleted_at", value: nil).order("created_at").execute().value
        async let checkIns: [CheckInRow] = client.from("check_ins")
            .select("id, senior_id, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: recentEvents).execute().value
        async let moods: [MoodEntryRow] = client.from("mood_entries")
            .select("id, senior_id, mood, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: iso(weekAgo)).execute().value
        async let medications: [MedicationRow] = client.from("medications")
            .select("id, senior_id, name, scheduled_time")
            .eq("account_id", value: accountID).is("deleted_at", value: nil).order("scheduled_time").execute().value
        async let events: [MedicationEventRow] = client.from("medication_events")
            .select("id, medication_id, status, occurred_at")
            .eq("account_id", value: accountID).gte("occurred_at", value: recentEvents).execute().value
        async let health: [HealthSnapshotRow] = client.from("health_snapshots")
            .select("id, senior_id, snapshot_date, steps, sleep_minutes, resting_heart_rate, source")
            .eq("account_id", value: accountID)
            .gte("snapshot_date", value: CareRecords.dateOnly.string(from: weekAgo)).execute().value
        async let appointments: [AppointmentRow] = client.from("appointments")
            .select("id, senior_id, title, clinician, scheduled_at, location, notes")
            .eq("account_id", value: accountID).is("deleted_at", value: nil)
            .gte("scheduled_at", value: recentEvents).execute().value
        async let alerts: [AlertRow] = client.from("alerts")
            .select("id, senior_id, occurred_at, acknowledged")
            .eq("account_id", value: accountID)
            .or("acknowledged.eq.false,occurred_at.gte.\(iso(weekAgo))").execute().value

        return try await CareRecords(
            account: account, members: members, seniors: seniors, checkIns: checkIns, moods: moods,
            medications: medications, medicationEvents: events, health: health,
            appointments: appointments, alerts: alerts
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
        // Awaiting each stream suspends, so the main thread isn't blocked.
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
        try await insert("check_ins", CheckInInsert(accountID: try account(for: seniorID), seniorID: seniorID, occurredAt: date))
    }

    func recordMood(_ mood: Mood, seniorID: String, at date: Date) async throws {
        try await insert("mood_entries", MoodInsert(accountID: try account(for: seniorID), seniorID: seniorID,
                                                    mood: mood.rawValue, occurredAt: date))
    }

    func toggleMedication(id: String) async throws {
        guard let medication = snapshot.medications.first(where: { $0.id == id }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        try await recordMedicationEvent(medicationID: id, taken: !medication.taken, at: now())
    }

    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {
        guard let medication = snapshot.medications.first(where: { $0.id == medicationID }) else {
            throw CareServiceError.invalidState("Medication not found")
        }
        try await insert("medication_events", MedicationEventInsert(
            accountID: try account(for: medication.seniorID), seniorID: medication.seniorID,
            medicationID: medicationID, status: taken ? "taken" : "skipped", occurredAt: date))
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
                .upsert(rows, onConflict: "senior_id,snapshot_date,source").execute()
        }
    }

    func saveAppointment(_ appointment: Appointment) async throws {
        let row = AppointmentUpsert(
            id: UUID(uuidString: appointment.id)?.uuidString.lowercased(),
            accountID: try account(for: appointment.seniorID), seniorID: appointment.seniorID,
            title: appointment.title, clinician: appointment.clinician, scheduledAt: appointment.date,
            location: appointment.location, notes: appointment.notes)
        try await perform {
            if row.id == nil {
                try await client.from("appointments").insert(row).execute()
            } else {
                try await client.from("appointments").upsert(row).execute()
            }
        }
    }

    func deleteAppointment(id: String) async throws {
        try await perform {
            try await client.from("appointments")
                .update(["deleted_at": Self.iso(now())]).eq("id", value: id).execute()
        }
    }

    func triggerSOS(seniorID: String, at date: Date) async throws {
        let row = AlertInsert(accountID: try account(for: seniorID), seniorID: seniorID, kind: "sos", occurredAt: date)
        do {
            try await perform { try await client.from("alerts").insert(row).execute() }
        } catch let error as PostgrestError where error.code == "23505" {
            // An open SOS already exists for this senior: SOS is idempotent.
            try await refresh()
        }
    }

    func acknowledgeAlerts(seniorID: String) async throws {
        let userID = try? await client.auth.session.user.id.uuidString.lowercased()
        try await perform {
            try await client.from("alerts")
                .update(AlertAcknowledgement(acknowledgedAt: now(), acknowledgedBy: userID))
                .eq("senior_id", value: seniorID).eq("acknowledged", value: false).execute()
        }
    }

    func saveCareInsight(_ insight: CareInsight, seniorID: String) async throws {
        try await insert("care_insights", CareInsightInsert(
            accountID: try account(for: seniorID), seniorID: seniorID, title: insight.title,
            summary: insight.summary, observations: insight.observations, suggestion: insight.suggestion))
    }

    func saveAppointmentPrep(_ prep: AppointmentPrep, appointmentID: String) async throws {
        guard let appointment = snapshot.appointments.first(where: { $0.id == appointmentID }) else {
            throw CareServiceError.invalidState("Appointment not found")
        }
        try await insert("appointment_ai_preps", AppointmentPrepInsert(
            accountID: try account(for: appointment.seniorID), seniorID: appointment.seniorID,
            appointmentID: appointmentID, title: prep.title, observations: prep.observations,
            questions: prep.questions, safetyNote: prep.safetyNote))
    }

    func addSenior(_ senior: AccountSenior) async throws {
        try await insert("account_seniors", SeniorUpsert(
            accountID: accountID, name: senior.name, age: senior.age, city: senior.city,
            timeZoneIdentifier: senior.timeZoneIdentifier))
    }

    func addMedication(seniorID: String, name: String, scheduledTime: String) async throws {
        try await insert("medications", MedicationInsert(accountID: try account(for: seniorID), seniorID: seniorID,
                                                        name: name, scheduledTime: scheduledTime))
    }

    /// Links the signed-in senior member's login to this senior record (server checks the role).
    func claimSeniorProfile(seniorID: String) async throws {
        try await perform {
            try await client.rpc("claim_senior_profile", params: ["target_senior_id": seniorID]).execute()
        }
    }

    func updateSenior(_ senior: AccountSenior) async throws {
        try await perform {
            try await client.from("account_seniors")
                .update(SeniorUpsert(accountID: accountID, name: senior.name, age: senior.age,
                                     city: senior.city, timeZoneIdentifier: senior.timeZoneIdentifier))
                .eq("id", value: senior.id).execute()
        }
    }

    /// Production data is never wiped from the app; reset only re-syncs from the server.
    func reset() async {
        try? await refresh()
    }

    // MARK: - Helpers

    private func account(for seniorID: String) throws -> String {
        guard let senior = snapshot.seniors.first(where: { $0.id == seniorID }) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        return senior.accountID
    }

    private func insert(_ table: String, _ row: some Encodable & Sendable) async throws {
        try await perform { try await client.from(table).insert(row).execute() }
    }

    /// Runs a write, then re-reads so `snapshot` reflects server-side defaults and triggers.
    private func perform(_ write: () async throws -> Void) async throws {
        do {
            try await write()
        } catch let error as PostgrestError where error.code == "23505" {
            throw error
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
        try await refresh()
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

private struct CheckInInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
    }
}

private struct MoodInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, mood: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case mood, accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
    }
}

private struct MedicationInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, name: String, scheduledTime: String
    enum CodingKeys: String, CodingKey {
        case name, accountID = "account_id", seniorID = "senior_id", scheduledTime = "scheduled_time"
    }
}

private struct MedicationEventInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, medicationID: String, status: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case status, accountID = "account_id", seniorID = "senior_id",
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

private struct AppointmentUpsert: Encodable, Sendable {
    let id: String?
    let accountID: String, seniorID: String, title: String, clinician: String
    let scheduledAt: Date, location: String, notes: String
    enum CodingKeys: String, CodingKey {
        case id, title, clinician, location, notes, accountID = "account_id",
             seniorID = "senior_id", scheduledAt = "scheduled_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(seniorID, forKey: .seniorID)
        try container.encode(title, forKey: .title)
        try container.encode(clinician, forKey: .clinician)
        try container.encode(scheduledAt, forKey: .scheduledAt)
        try container.encode(location, forKey: .location)
        try container.encode(notes, forKey: .notes)
    }
}

private struct AlertInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, kind: String, occurredAt: Date
    enum CodingKeys: String, CodingKey {
        case kind, accountID = "account_id", seniorID = "senior_id", occurredAt = "occurred_at"
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

private struct CareInsightInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, title: String, summary: String
    let observations: [String], suggestion: String
    enum CodingKeys: String, CodingKey {
        case title, summary, observations, suggestion, accountID = "account_id", seniorID = "senior_id"
    }
}

private struct AppointmentPrepInsert: Encodable, Sendable {
    let accountID: String, seniorID: String, appointmentID: String, title: String
    let observations: [String], questions: [String], safetyNote: String
    enum CodingKeys: String, CodingKey {
        case title, observations, questions, accountID = "account_id", seniorID = "senior_id",
             appointmentID = "appointment_id", safetyNote = "safety_note"
    }
}

private struct SeniorUpsert: Encodable, Sendable {
    let accountID: String, name: String, age: Int, city: String, timeZoneIdentifier: String
    enum CodingKeys: String, CodingKey {
        case name, age, city, accountID = "account_id", timeZoneIdentifier = "time_zone_identifier"
    }
}
