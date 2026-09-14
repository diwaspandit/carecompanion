# Lovable visual inspection

Inspected 2026-09-14 with gstack browse at a 390 × 844 viewport. The public share link in ../LOVABLE_REFERENCE.md now grants access and redirects into the prototype. Screenshots are full-page captures; the fixed bottom bar appears at its viewport position. These are reference screenshots, not native iOS screenshots or evidence of a passing app demo.

## Native translation notes

| Screen | Observed reference | Native implementation direction |
| --- | --- | --- |
| Onboarding | Small heart icon in a pale sage circle, bold left-aligned headline, generous empty space, two large role cards anchored toward the bottom. Senior card sage; family card white with border. | Preserve exact headline and hierarchy. SF Symbols, Dynamic Type and flexible spacing rather than fixed screen coordinates. |
| Senior Home | Compact brand/SOS header, large greeting/date, dominant sage check-in card, circular check icon, rounded medicine rows and next-visit card. | Large touch targets; confirmation followed by mood selection; shared state drives the family dashboard. Native safe-area tab placement. |
| Mood | Full-screen question, supporting instruction, three vertically stacked oversized face/label buttons. | Three accessible mood buttons; align display labels with domain values. Capture 03 is the mood screen reached after check-in, not the transient check-in confirmation. |
| Family | Family heading and location, avatar selector, AI card, Maya card containing check-in pill and two-column metric tiles, coral alert banner. | Show Maya only. Include 72 bpm alongside the required steps, sleep, medications and mood. Premium AI teaser precedes real RevenueCat paywall. |
| Appointments | Header with sage Add pill, rounded calendar, upcoming cards with circular date badge, clinician, time/location and notes. | Native appointment form and detail navigation, preserve date-badge/card language, add gated AI preparation. No reminder delivery claim unless implemented. |
| Alerts | Large rounded cards with category icon/time, brief explanation and action row. Coral emergency, amber medication, blue health accents. | Emergency state comes from explicit SOS. No automatic medical emergency inference or unimplemented call/message controls. |
| Health timeline | Seven-day scope; separate rounded sleep, steps, heart-rate, adherence and mood cards. Sage activity/sleep graphics, coral heart rate. | Basic health metrics remain free. Charts remain optional P3. AI wording must agree with the actual local history. |
| SOS | Full coral screen, warning icon, large centered five-second countdown, bottom white Cancel button. Transitions to full sage confirmation. | Preserve dramatic hierarchy and cancellation; use a deadline and handle lifecycle changes. Explicit demo wording must distinguish local family state from real-world notifications. |

## Required differences from prototype

- Prototype shows Ramesh, a second family contact and chats. Hackathon implementation focuses on Maya and Diwas and excludes messaging infrastructure.
- Prototype SOS says family was notified and help is coming. The local native demo must not imply real notification delivery or guaranteed assistance.
- Prototype AI describes changes that must not be copied blindly into the deterministic dataset. Generate consistent observations and clinician questions, without diagnosis or prescribing.
- Prototype AI is visible without purchase; native premium access must use real RevenueCat customer entitlements.
- Dates, clinicians and medicine names shown here are reference content, not a replacement for the agreed native demo seed.
- Gray and white-on-sage text need native contrast checks; existing darker accessible text tokens can complement the prescribed palette.
- Do not reproduce the Lovable editing badge or web bottom-bar behavior.

## Evidence

01-onboarding.png, 02-senior.png, 03-mood.png, 04-family.png, 05-appointments.png, 06-alerts.png, 07-health.png, 08-sos.png (countdown at 5), 09-sos-state.png (prototype confirmation).

Check-in was tapped and led to mood selection; Okay was selected. SOS countdown and confirmation were observed. No call/message buttons were activated. Dedicated medicine-reminder screen, appointment Add flow and transient check-in confirmation remain uninspected.
