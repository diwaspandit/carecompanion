import Foundation

public enum AppScreen: String, Codable, Sendable {
    case onboarding
    case seniorHome
    case familyDashboard
}

public enum SeniorTab: String, Codable, Sendable {
    case home
    case mood
    case sos
    case medicines
    case visits
    case messages
    case profile
}

public enum FamilyTab: String, Codable, Sendable {
    case dashboard
    case health
    case appointments
    case emergency
    case chats
    case profile
}

public enum PaywallContext: String, Identifiable, Codable, Sendable {
    case careInsight
    case appointmentPrep

    public var id: String { rawValue }
}
