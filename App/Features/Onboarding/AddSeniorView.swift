import CareCore
import SwiftUI

struct AddSeniorView: View {
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var age = 75
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier

    var body: some View {
        OnboardingScaffold(title: "Who are you caring for?", subtitle: "Add the senior your family looks after.") {
            OnboardingField(label: "Their name", text: $name, identifier: "senior.name")
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            Stepper(value: $age, in: 40...120) {
                Text("Age \(age)").font(.system(size: 19, weight: .bold)).foregroundStyle(CareTheme.ink)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            .accessibilityIdentifier("senior.age")
            OnboardingField(label: "City (optional)", text: $city, identifier: "senior.city")
                .textInputAutocapitalization(.words)
            NavigationLink {
                TimeZonePickerView(selection: $timeZone)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Their time zone").font(.system(size: 15, weight: .bold)).foregroundStyle(CareTheme.mutedText)
                        Text(TimeZonePickerView.label(for: timeZone)).font(.system(size: 19)).foregroundStyle(CareTheme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(CareTheme.secondaryText)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("senior.timeZone")
            OnboardingPrimaryButton(title: "Add senior", enabled: !name.isEmpty, identifier: "senior.add") {
                await session.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZone)
            }
        }
    }
}

struct TimeZonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static func label(for identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { Self.label(for: $0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(zones, id: \.self) { zone in
            Button {
                selection = zone
                dismiss()
            } label: {
                HStack {
                    Text(Self.label(for: zone)).foregroundStyle(CareTheme.ink)
                    Spacer()
                    if zone == selection {
                        Image(systemName: "checkmark").foregroundStyle(CareTheme.sageDark)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search city or region")
        .navigationTitle("Time zone")
    }
}
