# Design

CareCompanion aims to feel calm, warm and personal. Seniors get large, simple controls. Families get a gentle overview that surfaces what needs attention first.

## Palette

Defined in `CareTheme` (`App/DesignSystem.swift`).

| Token | Use |
| --- | --- |
| `background` (warm off white `#FAFAF7`) | Screen background |
| `heading` (deep slate) | Family home headings and names |
| `ink`, `mutedText`, `secondaryText` | Body text hierarchy |
| `sage`, `sageDark`, `sagePale` | Primary actions, positive status, selection |
| `coral`, `coralDark`, `coralPale` | SOS, urgent status, portrait rings |
| `gold`, `goldDark`, `goldPale` | Medicines, "needs attention" |
| `blue`, `bluePale` | Health metrics, landscape backdrop |

## Type

- Rounded system font for headings, names and the welcome title.
- The welcome title uses `@ScaledMetric`, so it grows with Dynamic Type.
- Status and supporting text use `subheadline` and `caption`.

## Components

| Component | Purpose |
| --- | --- |
| `LovableCard` | White rounded card with a soft shadow |
| `SeniorAvatar` | Bundled portrait when one matches the senior's first name, otherwise initials on a tinted circle |
| `SmallMetric` | Icon, label and value tile used in care summaries |
| `PlainPill` | Compact status label |
| `ReferenceBottomBar` | Tab bar with alert badge |
| `PrimaryActionButton`, `careField()` | Form actions and inputs |
| `OnboardingConnectionView` | Lottie animation of care travelling between two homes |

## Welcome screen

1. An illustration of two homes, Kathmandu and Austin, joined by a dotted arc. A coral heart travels along the arc and a soft glow appears when it arrives. It plays once each time the screen appears. With Reduce Motion on, the finished frame is shown without playback.
2. A centered title, "Care that travels across time zones."
3. A one sentence description of what is shared.
4. Sign in and create account form.

## Family home

From top to bottom:

1. **Greeting.** "Good evening," and the member's first name on two lines, with the family name below. A round initial button on the right opens Settings.
2. **Status card.** One sentence about the selected senior: "Ramesh sent an SOS", "Maya checked in today" or "Waiting to hear from Maya", with the most important follow-up underneath. It gains a coral outline during an SOS.
3. **Senior tiles.** A two column grid. Each tile shows the senior's portrait or initials with a small status badge (check, clock or exclamation), their first name and a colored status line. The selected senior has a sage outline. The last tile is a dashed "Add" tile.
4. **Care insight shortcut.** Opens the selected senior's care details.
5. **Footer.** "A little closer, every day."

Behind the Home tab sits a soft landscape: a coral sun and pale blue and coral waves at the top and bottom. Other tabs use the plain background.

## Account setup role cards

Two large cards with an icon, a rounded title and a one line description. The selected card fills with sage and shows a check mark.

## Bundled assets

| Asset | Location | Notes |
| --- | --- | --- |
| Welcome animation | `App/Resources/care-connection.json` | Original vector artwork made for this project. 360 by 206, 30 fps, 4 seconds. No external images or fonts. |
| Maya portrait | `App/Assets.xcassets/MayaPortrait.imageset` | Fictional person |
| Ramesh portrait | `App/Assets.xcassets/RameshPortrait.imageset` | Fictional person |
| Lakshmi portrait | `App/Assets.xcassets/LakshmiPortrait.imageset` | Fictional person |
| Hari portrait | `App/Assets.xcassets/HariPortrait.imageset` | Fictional person |

The portraits are generated images of fictional people, created for demonstration. None of them is a photograph of a real care recipient. To show a portrait for another senior, add an image set named `<FirstName>Portrait` (for example `SitaPortrait`) to the asset catalog.

## Accessibility

- Tiles read as "Name, status" and expose the selected trait.
- Decorative art (backdrop, avatars, icons) is hidden from VoiceOver.
- Key elements carry accessibility identifiers used by UI tests, such as `welcome.title`, `family.title`, `family.status`, `family.addSenior` and `family.settings`.
