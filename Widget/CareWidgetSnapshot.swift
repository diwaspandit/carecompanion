import Foundation

/// The three lines shown on the home screen widget. The app writes this; the widget only reads it.
struct CareWidgetSnapshot: Codable, Equatable, Sendable {
    var title: String
    var message: String
    var medicine: String
    var visit: String

    static let empty = CareWidgetSnapshot(
        title: "CareCompanion",
        message: "No new message",
        medicine: "No medicine",
        visit: "No visit"
    )

    private static let suiteName = "group.com.carecompanion.txst"
    private static let key = "care.widget.snapshot"
    static let appearanceKey = "care.appearance"

    static func read() -> CareWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CareWidgetSnapshot.self, from: data)
    }

    static func write(_ snapshot: CareWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: suiteName)?.set(data, forKey: key)
    }

    static func writeAppearance(_ raw: String) {
        UserDefaults(suiteName: suiteName)?.set(raw, forKey: appearanceKey)
    }

    static func readAppearance() -> String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: appearanceKey)
    }

    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
    }
}
