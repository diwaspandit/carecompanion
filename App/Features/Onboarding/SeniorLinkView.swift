import CareCore
import SwiftUI

struct SeniorLinkView: View {
    @Environment(AppSession.self) private var session
    let seniors: [AccountSenior]

    var body: some View {
        OnboardingScaffold(title: seniors.count == 1 ? "Is this you?" : "Which one is you?",
                           subtitle: "Linking this phone shares your check-ins with your family, and Apple Health data if you allow it.") {
            if seniors.isEmpty {
                Text("Your family hasn't added you yet. Ask them to add you, then tap Refresh.")
                    .font(.system(size: 17))
                    .foregroundStyle(CareTheme.secondaryText)
                OnboardingPrimaryButton(title: "Refresh", identifier: "seniorLink.refresh") { await session.retry() }
            } else {
                ForEach(seniors) { senior in
                    Button {
                        Task { await session.claimSenior(id: senior.id) }
                    } label: {
                        HStack(spacing: 14) {
                            AvatarCircle(text: initials(senior.name), color: CareTheme.gold, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("This is me: \(senior.name)").font(.system(size: 19, weight: .black)).foregroundStyle(CareTheme.ink)
                                Text(["\(senior.age) years", senior.city].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(CareTheme.secondaryText)
                        }
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CareTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("seniorLink.claim")
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        let parts = Array(name.split(separator: " "))
        var result = ""
        for index in 0..<min(2, parts.count) {
            if let first = parts[index].first {
                result.append(first)
            }
        }
        return result
    }
}
