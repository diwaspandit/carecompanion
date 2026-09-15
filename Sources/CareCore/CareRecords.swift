import Foundation

// Row shapes returned by the production database (snake_case columns), plus the
// pure mapping into CareSnapshot. Kept vendor-free so it is covered by `swift test`.

public struct CareAccountRow: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var name: String
    public var inviteCode: String

    enum CodingKeys: String, CodingKey {
        case id, kind, name
        case inviteCode = "invite_code"
    }
}

public struct AccountMemberRow: Codable, Equatable, Sendable {
    public struct Profile: Codable, Equatable, Sendable {
        public var displayName: String
        public var city: String
        public var phone: String

        public init(displayName: String, city: String = "", phone: String = "") {
            self.displayName = displayName
            self.city = city
            self.phone = phone
        }

        enum CodingKeys: String, CodingKey {
            case city, phone
            case displayName = "display_name"
        }
    }

    public var id: String
    public var accountID: String
    public var profileID: String
    public var role: String
    public var profile: Profile?

    enum CodingKeys: String, CodingKey {
        case id, role
        case accountID = "account_id"
        case profileID = "profile_id"
        case profile = "profiles"
    }
}

public struct AccountSeniorRow: Codable, Equatable, Sendable {
    public var id: String
    public var accountID: String
    public var name: String
    public var age: Int
    public var city: String
    public var timeZoneIdentifier: String
    public var profileID: String?

    enum CodingKeys: String, CodingKey {
        case id, name, age, city
        case accountID = "account_id"
        case timeZoneIdentifier = "time_zone_identifier"
        case profileID = "profile_id"
    }
}

public struct CheckInRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case seniorID = "senior_id"
        case occurredAt = "occurred_at"
    }
}

public struct MoodEntryRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var mood: String
    public var note: String?
    public var occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, mood, note
        case seniorID = "senior_id"
        case occurredAt = "occurred_at"
    }
}

public struct MedicationRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var name: String
    public var dosage: String = ""
    public var scheduledTime: String

    enum CodingKeys: String, CodingKey {
        case id, name, dosage
        case seniorID = "senior_id"
        case scheduledTime = "scheduled_time"
    }
}

public struct MedicationEventRow: Codable, Equatable, Sendable {
    public var id: String
    public var medicationID: String
    public var status: String
    public var occurredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case medicationID = "medication_id"
        case occurredAt = "occurred_at"
    }
}

public struct HealthSnapshotRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    /// Postgres `date`, e.g. "2026-09-14".
    public var snapshotDate: String
    public var steps: Int
    public var sleepMinutes: Int
    public var restingHeartRate: Int
    public var source: String

    enum CodingKeys: String, CodingKey {
        case id, steps, source
        case seniorID = "senior_id"
        case snapshotDate = "snapshot_date"
        case sleepMinutes = "sleep_minutes"
        case restingHeartRate = "resting_heart_rate"
    }
}

public struct AppointmentRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var title: String
    public var clinician: String
    public var scheduledAt: Date
    public var location: String
    public var notes: String

    enum CodingKeys: String, CodingKey {
        case id, title, clinician, location, notes
        case seniorID = "senior_id"
        case scheduledAt = "scheduled_at"
    }
}

public struct AlertRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var occurredAt: Date
    public var acknowledged: Bool

    enum CodingKeys: String, CodingKey {
        case id, acknowledged
        case seniorID = "senior_id"
        case occurredAt = "occurred_at"
    }
}

public struct EmergencyContactRow: Codable, Equatable, Sendable {
    public var id: String
    public var seniorID: String
    public var name: String
    public var relation: String
    public var phone: String

    enum CodingKeys: String, CodingKey {
        case id, name, relation, phone
        case seniorID = "senior_id"
    }
}

public struct MessageRow: Codable, Equatable, Sendable {
    public var id: String
    public var senderProfileID: String?
    public var body: String
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body
        case senderProfileID = "sender_profile_id"
        case createdAt = "created_at"
    }
}

public struct CareRecords: Equatable, Sendable {
    public var account: CareAccountRow
    public var members: [AccountMemberRow]
    public var seniors: [AccountSeniorRow]
    public var checkIns: [CheckInRow]
    public var moods: [MoodEntryRow]
    public var medications: [MedicationRow]
    public var medicationEvents: [MedicationEventRow]
    public var health: [HealthSnapshotRow]
    public var appointments: [AppointmentRow]
    public var alerts: [AlertRow]
    public var contacts: [EmergencyContactRow]
    public var messages: [MessageRow]

    public init(account: CareAccountRow, members: [AccountMemberRow], seniors: [AccountSeniorRow],
                checkIns: [CheckInRow], moods: [MoodEntryRow], medications: [MedicationRow],
                medicationEvents: [MedicationEventRow], health: [HealthSnapshotRow],
                appointments: [AppointmentRow], alerts: [AlertRow],
                contacts: [EmergencyContactRow] = [], messages: [MessageRow] = []) {
        self.account = account
        self.members = members
        self.seniors = seniors
        self.checkIns = checkIns
        self.moods = moods
        self.medications = medications
        self.medicationEvents = medicationEvents
        self.health = health
        self.appointments = appointments
        self.alerts = alerts
        self.contacts = contacts
        self.messages = messages
    }

    /// "Today" is evaluated in each senior's own time zone, so a caregiver in Austin sees
    /// a Kathmandu senior's day rather than their own.
    public func snapshot(now: Date) throws -> CareSnapshot {
        guard let kind = AccountKind(rawValue: account.kind) else {
            throw CareServiceError.invalidState("Unknown account kind: \(account.kind)")
        }
        let seniorZones = Dictionary(uniqueKeysWithValues: seniors.map {
            ($0.id, TimeZone(identifier: $0.timeZoneIdentifier) ?? .gmt)
        })
        func isSeniorToday(_ date: Date, _ seniorID: String) -> Bool {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = seniorZones[seniorID] ?? .gmt
            return calendar.isDate(date, inSameDayAs: now)
        }

        let latestEventByMedication = Dictionary(grouping: medicationEvents, by: \.medicationID)
            .compactMapValues { $0.max { $0.occurredAt < $1.occurredAt } }
        let seniorByMedication = Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0.seniorID) })

        return CareSnapshot(
            account: CareAccount(id: account.id, kind: kind, name: account.name, inviteCode: account.inviteCode),
            members: try members.map { row in
                guard let role = CareRole(rawValue: row.role) else {
                    throw CareServiceError.invalidState("Unknown member role: \(row.role)")
                }
                return AccountMember(id: row.id, accountID: row.accountID, profileID: row.profileID,
                                     name: row.profile?.displayName ?? "", city: row.profile?.city ?? "",
                                     phone: row.profile?.phone ?? "", role: role)
            },
            seniors: seniors.map {
                AccountSenior(id: $0.id, accountID: $0.accountID, name: $0.name, age: $0.age,
                              city: $0.city, timeZoneIdentifier: $0.timeZoneIdentifier, profileID: $0.profileID)
            },
            checkIns: checkIns
                .filter { isSeniorToday($0.occurredAt, $0.seniorID) }
                .sorted { $0.occurredAt < $1.occurredAt }
                .map { CheckIn(id: $0.id, seniorID: $0.seniorID, date: $0.occurredAt) },
            moods: try moods
                .sorted { $0.occurredAt < $1.occurredAt }
                .map { row in
                    guard let mood = Mood(rawValue: row.mood) else {
                        throw CareServiceError.invalidState("Unknown mood: \(row.mood)")
                    }
                    return MoodEntry(id: row.id, seniorID: row.seniorID, mood: mood, date: row.occurredAt, note: row.note)
                },
            medications: medications.map { row in
                let latest = latestEventByMedication[row.id]
                let takenToday = latest.map { $0.status == "taken" && isSeniorToday($0.occurredAt, row.seniorID) } ?? false
                return Medication(id: row.id, seniorID: row.seniorID, name: row.name, dosage: row.dosage,
                                  scheduledTime: row.scheduledTime, taken: takenToday)
            },
            medicationEvents: try medicationEvents
                .compactMap { row -> MedicationEvent? in
                    guard let seniorID = seniorByMedication[row.medicationID] else { return nil }
                    guard let status = MedicationEventStatus(rawValue: row.status) else {
                        throw CareServiceError.invalidState("Unknown medication event status: \(row.status)")
                    }
                    return MedicationEvent(id: row.id, medicationID: row.medicationID, seniorID: seniorID,
                                           status: status, date: row.occurredAt)
                }
                .sorted { $0.date < $1.date },
            health: try health
                .map { row in
                    guard let date = Self.dateOnly.date(from: row.snapshotDate) else {
                        throw CareServiceError.invalidState("Bad snapshot date: \(row.snapshotDate)")
                    }
                    return HealthSnapshot(id: row.id, seniorID: row.seniorID, date: date, steps: row.steps,
                                          sleepMinutes: row.sleepMinutes,
                                          restingHeartRate: row.restingHeartRate, source: row.source)
                }
                .sorted { $0.date > $1.date },
            appointments: appointments
                .sorted { $0.scheduledAt < $1.scheduledAt }
                .map { Appointment(id: $0.id, seniorID: $0.seniorID, title: $0.title, clinician: $0.clinician,
                                   date: $0.scheduledAt, location: $0.location, notes: $0.notes) },
            alerts: alerts.map { CareAlert(id: $0.id, seniorID: $0.seniorID, date: $0.occurredAt, acknowledged: $0.acknowledged) },
            contacts: contacts
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { EmergencyContact(id: $0.id, seniorID: $0.seniorID, name: $0.name, relation: $0.relation, phone: $0.phone) },
            messages: messages
                .sorted { $0.createdAt < $1.createdAt }
                .map { CareMessage(id: $0.id, senderProfileID: $0.senderProfileID, body: $0.body, date: $0.createdAt) }
        )
    }

    public static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
