import Foundation

public enum CareRole: String, Codable, Sendable { case senior, family }
public enum AccountKind: String, Codable, Sendable { case family, organization }
public enum Mood: String, CaseIterable, Codable, Sendable { case great = "Great", okay = "Okay", low = "Low" }
public struct CareAccount: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var kind: AccountKind
    public var name: String
}
public struct AccountMember: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let accountID: String
    public var name: String
    public var city: String
    public var role: CareRole
}
public struct AccountSenior: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let accountID: String
    public var name: String
    public var age: Int
    public var city: String
    public var timeZoneIdentifier: String
}
public struct CheckIn: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public let date: Date
}
public struct MoodEntry: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var mood: Mood
    public var date: Date
}
public struct Medication: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var name: String
    public var scheduledTime: String
    public var taken: Bool
}
public struct HealthSnapshot: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public let date: Date
    public let steps: Int
    public let sleepMinutes: Int
    public let restingHeartRate: Int
    public let source: String
}
public struct Appointment: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public var title: String
    public var clinician: String
    public var date: Date
    public var location: String
    public var notes: String
}
public struct CareAlert: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let seniorID: String
    public let date: Date
    public var acknowledged: Bool
}
public struct CareSnapshot: Equatable, Codable, Sendable {
    public var account: CareAccount
    public var members: [AccountMember]
    public var seniors: [AccountSenior]
    public var checkIns: [CheckIn]
    public var moods: [MoodEntry]
    public var medications: [Medication]
    public var health: [HealthSnapshot]
    public var appointments: [Appointment]
    public var alerts: [CareAlert]
}
