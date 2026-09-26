import CareCore
import Foundation
import WidgetKit

/// Writes the signed-in person's widget lines and asks iOS to refresh the home screen.
enum CareWidgetPublisher {
    static let kind = "CareHomeWidget"

    @MainActor
    static func publish(_ state: AppState) {
        let senior = state.selectedSenior
        let zone = TimeZone(identifier: senior?.timeZoneIdentifier ?? "") ?? .current
        let message = state.unseenMessages.last.map { item -> String in
            let body = item.audioPath == nil ? item.body : "Voice message"
            return "\(state.senderName(for: item)): \(body)"
        }
        let medicine = state.medications.filter { medication in
            !medication.taken && CareSchedule.medicationIsDue(medication, on: Date(), timeZone: zone)
        }.min { doseMinutes($0) < doseMinutes($1) }
        let visit = state.appointments.compactMap { item -> (Appointment, Date)? in
            guard let next = CareSchedule.nextOccurrence(of: item, after: Date(), timeZone: zone) else { return nil }
            return (item, next)
        }.min { $0.1 < $1.1 }
        let title = state.role == .senior ? "Today" : (senior?.name.split(separator: " ").first.map(String.init) ?? "Family")
        CareWidgetSnapshot.write(CareWidgetSnapshot(
            title: title,
            message: clipped(message ?? "No new message"),
            medicine: clipped(medicine.map { med in
                med.scheduledTime.isEmpty ? med.name : "\(med.name) · \(med.scheduledTime)"
            } ?? "No medicine"),
            visit: clipped(visit.map { item, when in
                let label = when.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated).hour().minute())
                return "\(item.title) · \(label)"
            } ?? "No visit")
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func syncAppearance(_ raw: String) {
        CareWidgetSnapshot.writeAppearance(raw)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func clear() {
        CareWidgetSnapshot.clear()
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func clipped(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 80 ? String(flat.prefix(79)) + "…" : flat
    }

    private static func doseMinutes(_ medication: Medication) -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "h:mm a"
        guard let date = formatter.date(from: medication.scheduledTime.uppercased()) else { return 24 * 60 }
        let parts = formatter.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 24) * 60 + (parts.minute ?? 0)
    }
}

/// A tap on the widget. The signed-in person decides the screen: home for a senior, alerts for family.
enum CareWidgetLink {
    private static let pendingKey = "carecompanion.widget.open"

    static func isWidgetOpen(_ url: URL) -> Bool {
        url.scheme == "carecompanion" && url.host == "open"
    }

    static func remember() {
        UserDefaults.standard.set(true, forKey: pendingKey)
    }

    @MainActor
    static func apply(to state: AppState) {
        guard UserDefaults.standard.bool(forKey: pendingKey) else { return }
        UserDefaults.standard.set(false, forKey: pendingKey)
        open(state)
    }

    @MainActor
    static func open(_ state: AppState) {
        if state.role == .senior {
            state.seniorTab = .home
        } else {
            state.familyTab = .alerts
        }
    }
}
