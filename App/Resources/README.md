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

## Family demo portrait

`App/Assets.xcassets/MayaPortrait.imageset/maya-portrait.png` depicts the fictional demo character Maya Sharma. It was
generated with the built-in imagegen tool and bundled locally for offline use.
It is not a photograph of a real care recipient.

The four-profile demo also bundles fictional Ramesh, Lakshmi, and Hari portraits
in `App/Assets.xcassets/{Ramesh,Lakshmi,Hari}Portrait.imageset/portrait.png`.
They were created with the built-in imagegen tool. Each sample card is labeled
"Demo profile" and opens a local preview without changing the monitored account.
See [DEMO_PORTRAITS.md](DEMO_PORTRAITS.md) for the individual generation prompts.

Generation prompt:

> Create a single square photorealistic profile portrait asset for a fictional character in a warm family care iOS app. Subject Maya Sharma: a 74-year-old Nepali woman from Kathmandu, silver-gray hair softly tied back, gentle warm smile, realistic age lines, wearing a muted sage green cardigan and a simple ivory blouse, small understated gold earrings. Head and upper shoulders centered, entire hair and head visible with generous breathing room for a circular crop. Soft natural window light, clean warm off-white background, approachable everyday family photograph, realistic skin, no beauty retouching, no text, no logos, no borders, no interface, no medical equipment. It should feel personal and dignified. Output a high-quality square portrait.
