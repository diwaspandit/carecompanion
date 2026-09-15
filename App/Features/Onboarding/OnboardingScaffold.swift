import CareCore
import SwiftUI

/// Common layout for onboarding steps: title, optional subtitle, content, inline error, busy overlay.
struct OnboardingScaffold<Content: View>: View {
    @Environment(AppSession.self) private var session
    let title: String
    var subtitle: String?
    var showsSignOut = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    if showsSignOut && session.isSignedIn {
                        Button("Sign out") { Task { await session.signOut() } }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CareTheme.secondaryText)
                            .accessibilityIdentifier("onboarding.signOut")
                    }
                }
                .frame(minHeight: 44)

                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CareTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.title")
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(CareTheme.secondaryText)
                }

                content

                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CareTheme.coral)
                        .accessibilityIdentifier("onboarding.error")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background.ignoresSafeArea())
        .overlay { if session.isBusy { ProgressView().controlSize(.large) } }
        .disabled(session.isBusy)
    }
}

struct OnboardingField: View {
    let label: String
    @Binding var text: String
    var isSecure = false
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CareTheme.mutedText)
            Group {
                if isSecure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                }
            }
            .font(.system(size: 19))
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            .accessibilityIdentifier(identifier)
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var enabled = true
    let identifier: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Text(title).font(.system(size: 19, weight: .black))
        }
        .buttonStyle(ReferenceButtonStyle(fill: enabled ? CareTheme.sage : CareTheme.sage.opacity(0.45), height: 58, radius: 29))
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

struct OnboardingLinkButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(CareTheme.sageDark)
            .frame(maxWidth: .infinity, minHeight: 48)
            .accessibilityIdentifier(identifier)
    }
}

struct OnboardingChoiceRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? CareTheme.sageDark : CareTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .black)).foregroundStyle(CareTheme.ink)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? CareTheme.sageDark : CareTheme.cardStroke, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
