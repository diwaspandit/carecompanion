import SwiftUI
import Lottie

/// The bundled artwork plays once each time onboarding appears, including after demo reset.
struct OnboardingConnectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ConnectionAnimation(reduceMotion: reduceMotion)
                .aspectRatio(360.0 / 206.0, contentMode: .fit)
            HStack {
                Text("Kathmandu")
                Spacer()
                Text("Austin")
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(CareTheme.secondaryText)
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Care connecting Kathmandu and Austin")
    }
}

private struct ConnectionAnimation: UIViewRepresentable {
    let reduceMotion: Bool

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: "care-connection")
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.isUserInteractionEnabled = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        guard context.coordinator.lastReduceMotion != reduceMotion else { return }
        context.coordinator.lastReduceMotion = reduceMotion
        if reduceMotion {
            view.pause()
            view.currentProgress = 1
        } else {
            view.play(fromProgress: 0, toProgress: 1, loopMode: .playOnce)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleUIView(_ view: LottieAnimationView, coordinator: Coordinator) {
        view.stop()
    }

    final class Coordinator {
        var lastReduceMotion: Bool?
    }
}
