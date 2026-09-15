import CareCore
import SwiftUI

struct FamilySetupView: View {
    private enum Mode: Hashable { case start, join }

    @Environment(AppSession.self) private var session
    @State private var mode = Mode.start
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var joinAsSenior = false

    var body: some View {
        OnboardingScaffold(title: "Start or join a family",
                           subtitle: "Everyone caring for the same person shares one family.") {
            Picker("Start or join", selection: $mode) {
                Text("Start a family").tag(Mode.start)
                Text("Join with a code").tag(Mode.join)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("family.mode")

            switch mode {
            case .start:
                OnboardingField(label: "Family name", text: $familyName, identifier: "family.name")
                    .textInputAutocapitalization(.words)
                Text("Next you'll add the person your family cares for.")
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
                OnboardingPrimaryButton(title: "Create family", enabled: !familyName.isEmpty, identifier: "family.create") {
                    await session.createFamily(name: familyName)
                }
            case .join:
                OnboardingField(label: "Invite code", text: $inviteCode, identifier: "family.inviteCode")
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Text("Who are you in this family?")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CareTheme.mutedText)
                OnboardingChoiceRow(title: "I'm a family member", subtitle: "I help look after someone",
                                    selected: !joinAsSenior, identifier: "family.joinAsFamily") { joinAsSenior = false }
                OnboardingChoiceRow(title: "I'm the senior", subtitle: "My family looks after me",
                                    selected: joinAsSenior, identifier: "family.joinAsSenior") { joinAsSenior = true }
                OnboardingPrimaryButton(title: "Join family", enabled: !inviteCode.isEmpty, identifier: "family.join") {
                    await session.joinFamily(inviteCode: inviteCode, role: joinAsSenior ? .senior : .family)
                }
            }
        }
    }
}
