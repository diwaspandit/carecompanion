import CareCore
import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppSession.self) private var session
    @State private var displayName = ""
    @State private var city = ""

    var body: some View {
        OnboardingScaffold(title: "What should your family call you?",
                           subtitle: "Your name appears on your family's screens.") {
            OnboardingField(label: "Your name", text: $displayName, identifier: "profile.name")
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            OnboardingField(label: "City (optional)", text: $city, identifier: "profile.city")
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
            OnboardingPrimaryButton(title: "Continue", enabled: !displayName.isEmpty, identifier: "profile.continue") {
                await session.saveProfile(displayName: displayName, city: city)
            }
        }
    }
}
