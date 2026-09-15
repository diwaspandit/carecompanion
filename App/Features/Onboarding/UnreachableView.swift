import CareCore
import SwiftUI

struct UnreachableView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        OnboardingScaffold(title: "Can't reach CareCompanion",
                           subtitle: "Check your connection and try again. Your family's information is safe.") {
            OnboardingPrimaryButton(title: "Try again", identifier: "unreachable.retry") { await session.retry() }
            OnboardingLinkButton(title: "Try the demo", identifier: "unreachable.tryDemo") { session.tryDemo() }
        }
    }
}
