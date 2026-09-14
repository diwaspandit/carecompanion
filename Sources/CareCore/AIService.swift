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
        let medicationCount = snapshot.medications.filter { $0.seniorID == seniorID && $0.taken }.count
        let mood = snapshot.moods.last { $0.seniorID == seniorID }?.mood.rawValue ?? "Not recorded"
        let health = snapshot.health.first { $0.seniorID == seniorID }
        return CareInsight(
            title: "CareCompanion AI Insight",
            summary: "Maya checked in and her routine looks mostly steady today. There are a few small changes worth discussing at the next appointment.",
            observations: [
                "\(medicationCount) of 4 medications are marked taken today.",
                "Mood is recorded as \(mood).",
                "Today's demo health snapshot shows \(health?.steps ?? 0) steps, \(Self.sleepText(minutes: health?.sleepMinutes ?? 0)) sleep, and \(health?.restingHeartRate ?? 0) bpm resting heart rate."
            ],
            suggestion: "Consider checking in about the missed evening medication and whether sleep felt restful. This is care organization support, not a diagnosis."
        )
    }

    public func appointmentPrep(for appointment: Appointment, snapshot: CareSnapshot) async throws -> AppointmentPrep {
        AppointmentPrep(
            title: "Preparation for \(appointment.title)",
            observations: [
                "Maya has checked in today and reported feeling Okay.",
                "Medication adherence is 3 of 4 for the current demo day.",
                "Recent sleep is 6h 20min in the seeded demo snapshot.",
                "Steps are lower than an active day in the seven-day demo history."
            ],
            questions: [
                "Has Maya noticed any recent change in energy, balance, or appetite?",
                "Should the evening medication routine be simplified?",
                "Are sleep changes worth tracking before the next visit?"
            ],
            safetyNote: "CareCompanion helps organize family observations and appointment questions. It does not diagnose, prescribe, or determine whether symptoms are an emergency."
        )
    }

    private static func sleepText(minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)min"
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
