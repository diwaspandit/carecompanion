import Foundation

public enum SeniorTab: String, Codable, Sendable {
    case home
    case mood
    case medicines
    case visits
    case messages
}

public enum PhoneOpen {
    /// Handoff activity the watch starts so the paired iPhone can open Messages.
    public static let messagesActivity = "com.carecompanion.txst.messages"
    public static let messagesKind = "openPhone"
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
