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

    public init(id: String, accountID: String, name: String, age: Int, city: String, timeZoneIdentifier: String,
                profileID: String? = nil) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.age = age
        self.city = city
        self.timeZoneIdentifier = timeZoneIdentifier
        self.profileID = profileID
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
    /// Whether the latest event on the senior's local day says the dose was taken.
    public var taken: Bool

    public init(id: String, seniorID: String, name: String, dosage: String = "", scheduledTime: String, taken: Bool = false) {
        self.id = id
        self.seniorID = seniorID
        self.name = name
        self.dosage = dosage
        self.scheduledTime = scheduledTime
        self.taken = taken
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
}

public struct Appointment: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var title: String
    public var clinician: String
    public var date: Date
    public var location: String
    public var notes: String

    public init(id: String, seniorID: String, title: String, clinician: String, date: Date, location: String, notes: String) {
        self.id = id
        self.seniorID = seniorID
        self.title = title
        self.clinician = clinician
        self.date = date
        self.location = location
        self.notes = notes
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

    public init(id: String, senderProfileID: String?, body: String, date: Date) {
        self.id = id
        self.senderProfileID = senderProfileID
        self.body = body
        self.date = date
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
    public var appointments: [Appointment]
    public var alerts: [CareAlert]
    public var contacts: [EmergencyContact]
    public var messages: [CareMessage]

    public init(account: CareAccount, members: [AccountMember], seniors: [AccountSenior], checkIns: [CheckIn],
                moods: [MoodEntry], medications: [Medication], medicationEvents: [MedicationEvent] = [],
                health: [HealthSnapshot], appointments: [Appointment], alerts: [CareAlert],
                contacts: [EmergencyContact] = [], messages: [CareMessage] = []) {
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
}
