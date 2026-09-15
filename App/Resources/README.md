# Onboarding animation

`care-connection.json` is original vector artwork created for CareCompanion.
It is a Lottie JSON asset, not downloaded from the LottieFiles marketplace.
It contains no external images, fonts, or network resources.

- Canvas: 360 × 206; 30 fps; four seconds; play once.
- Artwork: larger Kathmandu and Austin homes, connecting arc, traveling coral
  heart, and a gentle arrival glow around Austin.
- Palette: sage `#6B9E78`, coral `#E8806A`, warm white `#FAFAF7`.
- Reduce Motion: display the completed illustration without playback.
- Playback: `App/Features/OnboardingConnectionView.swift`.
- Renderer: Airbnb Lottie 4.6.1, installed through its official
  [lottie-spm package](https://github.com/airbnb/lottie-spm).

The asset is copied into the app bundle by the Xcode resources build phase.
To try another LottieFiles design later, replace this file with a compatible
licensed JSON asset, keeping the filename and checking its final frame.
