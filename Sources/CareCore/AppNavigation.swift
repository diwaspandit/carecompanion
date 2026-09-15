import Foundation

public enum SeniorTab: String, Codable, Sendable {
    case home
    case mood
    case medicines
    case visits
    case messages
}

public enum FamilyTab: String, Codable, Sendable {
    case dashboard
    case health
    case appointments
    case alerts
    case messages
    case profile
}

public enum PaywallContext: String, Identifiable, Codable, Sendable {
    case careInsight
    case appointmentPrep

    public var id: String { rawValue }
}
