import Foundation

public struct CareInsight: Equatable, Codable, Sendable {
    public var title: String
    public var summary: String
    public var observations: [String]
    public var suggestion: String

    public init(title: String, summary: String, observations: [String], suggestion: String) {
        self.title = title
        self.summary = summary
        self.observations = observations
        self.suggestion = suggestion
    }
}

public struct AppointmentPrep: Equatable, Codable, Sendable {
    public var title: String
    public var observations: [String]
    public var questions: [String]
    public var safetyNote: String

    public init(title: String, observations: [String], questions: [String], safetyNote: String) {
        self.title = title
        self.observations = observations
        self.questions = questions
        self.safetyNote = safetyNote
    }
}

public protocol AIService: Sendable {
    func careInsight(for snapshot: CareSnapshot, seniorID: String) async throws -> CareInsight
    func appointmentPrep(for appointment: Appointment, snapshot: CareSnapshot) async throws -> AppointmentPrep
}

public struct MockAIService: AIService {
    public init() {}

    public func careInsight(for snapshot: CareSnapshot, seniorID: String) async throws -> CareInsight {
        guard let care = SeniorCareSummary(snapshot: snapshot, seniorID: seniorID) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        let items = care.attentionItems
        let summary = items.isEmpty
            ? "\(care.firstName)'s routine looks steady based on today's check-in, medications, and recent health data."
            : "Worth a look for \(care.firstName) today: \(SeniorCareSummary.list(items))."
        return CareInsight(
            title: "CareCompanion AI Insight",
            summary: summary,
            observations: care.observations,
            suggestion: Self.suggestion(for: care) + " This is care organization support, not a diagnosis."
        )
    }

    public func appointmentPrep(for appointment: Appointment, snapshot: CareSnapshot) async throws -> AppointmentPrep {
        guard let care = SeniorCareSummary(snapshot: snapshot, seniorID: appointment.seniorID) else {
            throw CareServiceError.invalidState("Senior not found")
        }
        var questions: [String] = []
        if !care.missedMedications.isEmpty {
            questions.append("Is the timing of \(SeniorCareSummary.list(care.missedMedications.map(\.name))) working for \(care.firstName)'s routine?")
        }
        if care.isStepsBelowBaseline {
            questions.append("Has \(care.firstName) noticed any change in energy or daily activity recently?")
        }
        if let sleep = care.averageSleepMinutes {
            questions.append("Has sleep felt restful? Recent nights average \(SeniorCareSummary.duration(minutes: sleep)).")
        }
        questions.append("Are there any changes to \(care.firstName)'s medications or routine we should note?")
        questions.append("What should the family keep an eye on before the next visit?")
        return AppointmentPrep(
            title: "Preparation for \(appointment.title)",
            observations: care.observations,
            questions: questions,
            safetyNote: "CareCompanion helps organize family observations and appointment questions. It does not diagnose, prescribe, or determine whether symptoms are an emergency."
        )
    }

    private static func suggestion(for care: SeniorCareSummary) -> String {
        if care.hasEmergency {
            return "Contact \(care.firstName) about the open SOS alert."
        }
        if !care.missedMedications.isEmpty {
            return "Consider a quick call to ask whether \(care.firstName) has taken \(SeniorCareSummary.list(care.missedMedications.map(\.name)))."
        }
        if !care.isCheckedIn {
            return "Consider reaching out to \(care.firstName), who hasn't confirmed today's check-in yet."
        }
        if care.isStepsBelowBaseline {
            return "Consider asking \(care.firstName) how the day is going; activity is lower than the recent average."
        }
        return "No follow-up needed right now. Keep an eye on the next check-in."
    }
}

public struct LiveAIService: AIService {
    public init() {}

    public func careInsight(for snapshot: CareSnapshot, seniorID: String) async throws -> CareInsight {
        try await MockAIService().careInsight(for: snapshot, seniorID: seniorID)
    }

    public func appointmentPrep(for appointment: Appointment, snapshot: CareSnapshot) async throws -> AppointmentPrep {
        try await MockAIService().appointmentPrep(for: appointment, snapshot: snapshot)
    }
}
