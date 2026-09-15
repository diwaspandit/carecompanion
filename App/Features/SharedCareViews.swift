import CareCore
import SwiftUI

/// "8:00 AM" style medication times: parsing, formatting and ordering.
enum MedicationTime {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }

    static func date(from text: String) -> Date {
        formatter.date(from: text.uppercased()) ?? Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static func minutesSinceMidnight(_ text: String) -> Int {
        guard let date = formatter.date(from: text.uppercased()) else { return Int.max }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func sorted(_ medications: [Medication]) -> [Medication] {
        medications.sorted { minutesSinceMidnight($0.scheduledTime) < minutesSinceMidnight($1.scheduledTime) }
    }
}

extension AppState {
    var selectedTimeZone: TimeZone {
        selectedSenior.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
    }
}

func timeText(_ date: Date, in zone: TimeZone) -> String {
    date.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
}

struct MedicineListView: View {
    @Environment(AppState.self) private var state
    var title = "Today's medicines"
    var large = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: large ? 25 : 19, weight: .black))
                .foregroundStyle(CareTheme.ink)
                .accessibilityAddTraits(.isHeader)
            let medications = MedicationTime.sorted(state.medications)
            if medications.isEmpty {
                Text("No medicines added yet.")
                    .font(.system(size: large ? 18 : 15))
                    .foregroundStyle(CareTheme.secondaryText)
            }
            ForEach(medications) { medication in
                MedicineRow(medication: medication, large: large)
            }
        }
    }
}

struct MedicineRow: View {
    @Environment(AppState.self) private var state
    let medication: Medication
    var large = true

    private var detail: String {
        [medication.dosage, medication.scheduledTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        Button {
            Task { await state.toggleMedication(id: medication.id) }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(medication.taken ? CareTheme.sage : .white)
                        .overlay(Circle().stroke(medication.taken ? CareTheme.sage : Color.black.opacity(0.18), lineWidth: 2))
                    if medication.taken {
                        Image(systemName: "checkmark")
                            .font(.system(size: large ? 22 : 16, weight: .black))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: large ? 48 : 36, height: large ? 48 : 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(medication.name)
                        .font(.system(size: large ? 22 : 17, weight: .black))
                        .foregroundStyle(CareTheme.ink)
                    Text(detail)
                        .font(.system(size: large ? 18 : 14))
                        .foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
            }
            .padding(large ? 20 : 14)
            .background(medication.taken ? CareTheme.sagePale : .white, in: RoundedRectangle(cornerRadius: large ? 32 : 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: large ? 32 : 22, style: .continuous)
                .stroke(medication.taken ? CareTheme.sage.opacity(0.38) : CareTheme.cardStroke, lineWidth: large ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(medication.name), \(detail)")
        .accessibilityValue(medication.taken ? "Taken" : "Not taken")
        .accessibilityHint(medication.taken ? "Double tap to mark as not taken" : "Double tap to mark as taken")
    }
}

struct AppointmentRowView: View {
    let appointment: Appointment
    let timeZone: TimeZone

    private var dayText: String {
        appointment.date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated)).uppercased()
            + "\n" + appointment.date.formatted(Date.FormatStyle(timeZone: timeZone).day())
    }

    private var detail: String {
        [appointment.date.formatted(Date.FormatStyle(timeZone: timeZone).month(.abbreviated).day().hour().minute()),
         appointment.location].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 16) {
                Text(dayText)
                    .font(.system(size: 13, weight: .black))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(CareTheme.ink)
                    .frame(width: 56, height: 56)
                    .background(CareTheme.grayPill, in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(appointment.title).font(.system(size: 18, weight: .black)).foregroundStyle(CareTheme.ink)
                    if !appointment.clinician.isEmpty {
                        Text(appointment.clinician).font(.system(size: 15, weight: .semibold)).foregroundStyle(CareTheme.mutedText)
                    }
                    Text(detail).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
                    if !appointment.notes.isEmpty {
                        Text(appointment.notes).font(.system(size: 14)).foregroundStyle(CareTheme.mutedText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ContactRow: View {
    @Environment(\.openURL) private var openURL
    let name: String
    let detail: String
    let phone: String

    var body: some View {
        HStack(spacing: 12) {
            CircleIcon(systemName: "person.fill", color: CareTheme.sage, size: 40, iconSize: 16, fillOpacity: 0.16)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16, weight: .black)).foregroundStyle(CareTheme.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(CareTheme.secondaryText)
            }
            Spacer()
            if let call = PhoneLinks.call(phone) {
                Button { openURL(call) } label: {
                    CircleIcon(systemName: "phone.fill", color: CareTheme.sageDark, size: 40, iconSize: 16, fillOpacity: 0.18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Call \(name)")
            }
            if let text = PhoneLinks.text(phone) {
                Button { openURL(text) } label: {
                    CircleIcon(systemName: "message.fill", color: CareTheme.blue, size: 40, iconSize: 16, fillOpacity: 0.18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Text \(name)")
            }
        }
        .padding(.vertical, 6)
    }
}

struct SmallMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CareTheme.secondaryText)
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(CareTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityIdentifier(identifier ?? "metric.\(title.replacingOccurrences(of: " ", with: "").lowercased())")
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(CareTheme.grayPill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .tint(color)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        LovableCard {
            HStack(alignment: .top, spacing: 14) {
                CircleIcon(systemName: icon, color: CareTheme.secondaryText, size: 44, iconSize: 18, fillOpacity: 0.12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 17, weight: .black)).foregroundStyle(CareTheme.ink)
                    Text(message).font(.system(size: 15)).foregroundStyle(CareTheme.secondaryText)
                }
            }
        }
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(CareTheme.ink, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

struct ToastOverlay: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let message = state.toastMessage {
            ToastView(message: message)
                .padding(.horizontal, 20)
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(for: .seconds(2.5))
                    if state.toastMessage == message { state.clearToast() }
                }
        }
    }
}

/// Senior details used when adding or editing a monitored senior.
struct SeniorDetailsFields: View {
    @Binding var name: String
    @Binding var age: Int
    @Binding var city: String
    @Binding var timeZone: String

    var body: some View {
        VStack(spacing: 14) {
            TextField("Full name", text: $name)
                .textContentType(.name)
                .careField()
                .accessibilityIdentifier("senior.form.name")
            HStack {
                Text("Age").foregroundStyle(CareTheme.ink)
                Spacer()
                Stepper("\(age) years", value: $age, in: 40...120)
                    .fixedSize()
            }
            .careField()
            TextField("City, country", text: $city)
                .textContentType(.addressCity)
                .careField()
            TimeZoneField(identifier: $timeZone)
                .careField()
        }
    }
}
