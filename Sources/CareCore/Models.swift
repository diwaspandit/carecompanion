import Foundation

public enum CareRole: String, Codable, Sendable { case senior, family }
public enum AccountKind: String, Codable, Sendable { case family, organization }
public enum Mood: String, CaseIterable, Codable, Sendable { case great = "Great", okay = "Okay", low = "Low" }

public struct CareAccount: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var kind: AccountKind
    public var name: String
    public var inviteCode: String

    public init(id: String, kind: AccountKind, name: String, inviteCode: String = "") {
        self.id = id
        self.kind = kind
        self.name = name
        self.inviteCode = inviteCode
    }
}

public struct AccountMember: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let accountID: String
    public let profileID: String
    public var name: String
    public var city: String
    public var phone: String
    public var role: CareRole

    public init(id: String, accountID: String, profileID: String = "", name: String, city: String = "",
                phone: String = "", role: CareRole) {
        self.id = id
        self.accountID = accountID
        self.profileID = profileID
        self.name = name
        self.city = city
        self.phone = phone
        self.role = role
    }
}

public struct AccountSenior: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let accountID: String
    public var name: String
    public var age: Int
    public var city: String
    public var timeZoneIdentifier: String
    /// The login that belongs to the senior themself, if they use the app on their own phone.
    public var profileID: String?
    /// Local clock time for the morning mood check, such as "9:00 AM".
    public var moodMorning: String
    /// Local clock time for the evening mood check, such as "6:00 PM".
    public var moodEvening: String
    /// Set when the family asks for a mood right now. Cleared once the senior answers.
    public var moodPromptAt: Date?

    public init(id: String, accountID: String, name: String, age: Int, city: String, timeZoneIdentifier: String,
                profileID: String? = nil, moodMorning: String = MoodPromptSchedule.morningDefault,
                moodEvening: String = MoodPromptSchedule.eveningDefault, moodPromptAt: Date? = nil) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.age = age
        self.city = city
        self.timeZoneIdentifier = timeZoneIdentifier
        self.profileID = profileID
        self.moodMorning = moodMorning
        self.moodEvening = moodEvening
        self.moodPromptAt = moodPromptAt
    }
}

public struct CheckIn: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public let date: Date

    public init(id: String, seniorID: String, date: Date) {
        self.id = id
        self.seniorID = seniorID
        self.date = date
    }
}

public struct MoodEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var mood: Mood
    public var date: Date
    public var note: String?

    public init(id: String, seniorID: String, mood: Mood, date: Date, note: String? = nil) {
        self.id = id
        self.seniorID = seniorID
        self.mood = mood
        self.date = date
        self.note = note
    }
}

public struct Medication: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var name: String
    public var dosage: String
    public var scheduledTime: String
    /// Gregorian weekdays this dose is due, Sunday = 1. Empty means every day.
    public var weekdays: [Int]
    /// Last calendar day the dose is due, stored as midnight UTC. Empty means it does not end.
    public var endsOn: Date?
    /// Whether the latest event on the senior's local day says the dose was taken.
    public var taken: Bool
    /// Set only when the family taps Remind. Adding or editing the dose does not set this.
    public var nudgeAt: Date?
    /// When a Snooze on either device should bring the dose back. Shared so the phone and watch agree.
    public var snoozeUntil: Date?
    /// When the dose was added. A clock time that already passed before then is not alerted until the next one.
    public var createdAt: Date?

    public init(id: String, seniorID: String, name: String, dosage: String = "", scheduledTime: String,
                weekdays: [Int] = [], endsOn: Date? = nil,
                taken: Bool = false, nudgeAt: Date? = nil, snoozeUntil: Date? = nil, createdAt: Date? = nil) {
        self.id = id
        self.seniorID = seniorID
        self.name = name
        self.dosage = dosage
        self.scheduledTime = scheduledTime
        self.weekdays = weekdays
        self.endsOn = endsOn
        self.taken = taken
        self.nudgeAt = nudgeAt
        self.snoozeUntil = snoozeUntil
        self.createdAt = createdAt
    }
}

public enum MedicationEventStatus: String, Codable, Sendable { case taken, skipped, missed }

public struct MedicationEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let medicationID: String
    public let seniorID: String
    public let status: MedicationEventStatus
    public let date: Date

    public init(id: String, medicationID: String, seniorID: String, status: MedicationEventStatus, date: Date) {
        self.id = id
        self.medicationID = medicationID
        self.seniorID = seniorID
        self.status = status
        self.date = date
    }
}

public enum HealthReadingKind: String, Codable, Equatable, Sendable {
    case heartRate = "heart_rate"
    case bloodPressure = "blood_pressure"
    case steps
    case sleep
    /// Minutes the Apple Watch was worn during the hour. `valueSecondary` is the last heart-rate sample, as seconds since 1970.
    case worn
    /// Live on-wrist signal from the watch. `value` is 1 when worn and 0 when not. `valueSecondary` is when the watch reported it.
    case presence
}

/// One hour of Apple Health data for a senior. Rows are kept so each person can be reviewed later.
public struct HealthReading: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    /// Start of the hour these numbers belong to.
    public let recordedAt: Date
    public let kind: HealthReadingKind
    public let value: Double
    public let valueSecondary: Double?
    public let source: String

    public init(id: String, seniorID: String, recordedAt: Date, kind: HealthReadingKind, value: Double,
                valueSecondary: Double? = nil, source: String) {
        self.id = id
        self.seniorID = seniorID
        self.recordedAt = recordedAt
        self.kind = kind
        self.value = value
        self.valueSecondary = valueSecondary
        self.source = source
    }

    public func assigned(to seniorID: String) -> HealthReading {
        HealthReading(id: id, seniorID: seniorID, recordedAt: recordedAt, kind: kind,
                      value: value, valueSecondary: valueSecondary, source: source)
    }
}

public struct HealthSnapshot: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    /// Midnight UTC of the calendar day the values belong to (matches the database `date`).
    public let date: Date
    public let steps: Int
    public let sleepMinutes: Int
    public let restingHeartRate: Int
    public let source: String

    public init(id: String, seniorID: String, date: Date, steps: Int, sleepMinutes: Int, restingHeartRate: Int, source: String) {
        self.id = id
        self.seniorID = seniorID
        self.date = date
        self.steps = steps
        self.sleepMinutes = sleepMinutes
        self.restingHeartRate = restingHeartRate
        self.source = source
    }

    public func assigned(to seniorID: String) -> HealthSnapshot {
        HealthSnapshot(id: id, seniorID: seniorID, date: date, steps: steps, sleepMinutes: sleepMinutes,
                       restingHeartRate: restingHeartRate, source: source)
    }
}

public enum VisitOutcome: String, Codable, Equatable, Sendable {
    case went
    case missed
}

public struct Appointment: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var title: String
    public var clinician: String
    public var date: Date
    public var location: String
    public var notes: String
    public var repeatRule: VisitRepeat
    /// Last calendar day a repeated visit happens, stored as midnight UTC.
    public var endsOn: Date?
    /// Whether the visit happened. For a repeating visit this is the latest logged time.
    public var outcome: VisitOutcome?
    /// The visit time that `outcome` belongs to.
    public var loggedAt: Date?

    public init(id: String, seniorID: String, title: String, clinician: String, date: Date, location: String, notes: String,
                repeatRule: VisitRepeat = .once, endsOn: Date? = nil, outcome: VisitOutcome? = nil, loggedAt: Date? = nil) {
        self.id = id
        self.seniorID = seniorID
        self.title = title
        self.clinician = clinician
        self.date = date
        self.location = location
        self.notes = notes
        self.repeatRule = repeatRule
        self.endsOn = endsOn
        self.outcome = outcome
        self.loggedAt = loggedAt
    }
}

public struct CareAlert: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public let date: Date
    public var acknowledged: Bool

    public init(id: String, seniorID: String, date: Date, acknowledged: Bool) {
        self.id = id
        self.seniorID = seniorID
        self.date = date
        self.acknowledged = acknowledged
    }
}

public struct EmergencyContact: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var name: String
    public var relation: String
    public var phone: String

    public init(id: String, seniorID: String, name: String, relation: String, phone: String) {
        self.id = id
        self.seniorID = seniorID
        self.name = name
        self.relation = relation
        self.phone = phone
    }
}

public struct CareMessage: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let senderProfileID: String?
    public let body: String
    public let date: Date
    /// Storage path for a voice clip. Empty for a typed message.
    public let audioPath: String?
    /// Profiles that have opened this message. The sender is not counted as having seen it.
    public var readerProfileIDs: [String]

    public init(id: String, senderProfileID: String?, body: String, date: Date, audioPath: String? = nil, readerProfileIDs: [String] = []) {
        self.id = id
        self.senderProfileID = senderProfileID
        self.body = body
        self.date = date
        self.audioPath = audioPath
        self.readerProfileIDs = readerProfileIDs
    }
}

public struct CareSnapshot: Equatable, Codable, Sendable {
    public var account: CareAccount
    public var members: [AccountMember]
    public var seniors: [AccountSenior]
    public var checkIns: [CheckIn]
    public var moods: [MoodEntry]
    public var medications: [Medication]
    public var medicationEvents: [MedicationEvent]
    public var health: [HealthSnapshot]
    public var healthReadings: [HealthReading]
    public var appointments: [Appointment]
    public var alerts: [CareAlert]
    public var contacts: [EmergencyContact]
    public var messages: [CareMessage]

    public init(account: CareAccount, members: [AccountMember], seniors: [AccountSenior], checkIns: [CheckIn],
                moods: [MoodEntry], medications: [Medication], medicationEvents: [MedicationEvent] = [],
                health: [HealthSnapshot], healthReadings: [HealthReading] = [],
                appointments: [Appointment], alerts: [CareAlert],
                contacts: [EmergencyContact] = [], messages: [CareMessage] = []) {
        self.account = account
        self.members = members
        self.seniors = seniors
        self.checkIns = checkIns
        self.moods = moods
        self.medications = medications
        self.medicationEvents = medicationEvents
        self.health = health
        self.healthReadings = healthReadings
        self.appointments = appointments
        self.alerts = alerts
        self.contacts = contacts
        self.messages = messages
    }
}
