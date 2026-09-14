# CareCompanion Complete Demo Design

Date: 2026-09-14

## Goal

Build CareCompanion as a complete, polished native SwiftUI demo for Maya Sharma in Kathmandu and Diwas in Austin.

The app should win the TXST Shipaton by making the judge understand the emotional problem in seconds, then proving that the product can run a reliable care loop: Maya checks in, Diwas sees useful context, premium AI prepares the family for care conversations, and SOS changes the family state immediately.

The primary success criterion is a flawless 90-second guided demo. The app should feel complete for that demo path, not broad for its own sake.

## Source Material

Use the CareCompanion v2 Claude Design prototype as the main visual reference.

Use these v2 design traits:

- Warm cream background, roughly `#FBF9F4`, with soft off-white cards.
- Deeper sage accents, roughly `#4F7A5B`, for primary actions and active states.
- Coral emergency color, roughly `#C9543A`, for SOS and emergency alerts.
- Editorial display headings inspired by the v2 Newsreader typography.
- Large rounded cards, 20-26 pt corner radius.
- Senior screens with very large controls and low cognitive load.
- Family screens with denser but still calm dashboard information.
- Floating rounded bottom navigation inside the safe area.
- Dramatic full-screen SOS countdown.

Do not port HTML, web state, web icons, or CSS. Translate the design into idiomatic SwiftUI with SF Symbols, Dynamic Type, accessibility labels, safe areas, and native navigation.

## Product Scope

Build one polished Maya and Diwas demo. Multi-senior architecture remains in the model, but the UI only shows Maya.

Included:

- Onboarding and role selection.
- Senior home.
- Check-in confirmation.
- Mood recording.
- Medicines list.
- Appointments list.
- SOS countdown and confirmation.
- Family dashboard.
- Health timeline.
- Alerts.
- AI insight teaser and full deterministic insight.
- Appointment AI preparation.
- Paywall surface that can later host RevenueCatUI.
- Hidden developer/demo controls for reset and scenario jumps.

Excluded from this phase:

- Organization UI.
- Real messaging.
- Real phone calls.
- Real push notifications.
- HealthKit.
- Supabase.
- Live AI.
- Production multi-senior management.
- Custom backend.

## Demo Flow

The app must support this complete path:

1. Launch to onboarding with “Care that travels across time zones.”
2. Select Senior.
3. Show Maya home.
4. Tap “I’m okay.”
5. Show check-in confirmation.
6. Continue to mood.
7. Record mood as Okay.
8. Switch to Family.
9. Show Diwas dashboard with Maya checked in.
10. Show medication adherence, mood, steps, sleep, resting heart rate, and local demo data context.
11. Show AI insight teaser.
12. Open paywall from the locked insight.
13. Unlock premium through the current demo unlock surface or RevenueCat when credentials are present.
14. Show full care insight.
15. Open Appointments.
16. Tap “Prepare with CareCompanion AI.”
17. Show recent observations and clinician questions.
18. Switch to Maya.
19. Trigger SOS.
20. Show animated 5-second countdown with cancel.
21. Complete countdown and show senior SOS confirmation.
22. Switch to Family.
23. Show emergency banner and active alert.

## Information Architecture

`RootView` decides whether to show onboarding, the senior shell, or the family shell.

Senior shell tabs:

- Home
- Medicines
- Visits

Family shell tabs:

- Home
- Health
- Alerts
- Visits
- Profile

Transient full-screen states:

- Check-in confirmation.
- Mood selection.
- SOS countdown.
- SOS confirmation.
- Paywall or subscription sheet.

The role switcher is part of the demo/developer affordance, not a production-facing primary flow. It can be hidden behind a long press, toolbar debug menu, or subtle development overlay that is not obvious during the judge demo.

## Screens

### Onboarding

Use the v2 editorial composition:

- Small CareCompanion brand mark at top.
- Large display headline: “Care that travels across time zones.”
- Short supporting copy.
- Bottom role selector with two large cards:
  - “I am a senior”
  - “I am a family member”

Selecting Senior sets `AppState.role = .senior`; selecting Family sets `AppState.role = .family`.

### Senior Home

Senior Home is optimized for Maya.

Content:

- Brand/SOS header.
- Date and “Good morning, Maya.”
- Large sage “I’m okay” card before check-in.
- Checked-in card after check-in, with mood and “Diwas can see this.”
- “Today’s medicines” rows with 3 of 4 taken.
- “Next visit” card.

The SOS button is always visible in the header and leads to the SOS countdown.

### Check-In Confirmation

After tapping “I’m okay,” show a calm confirmation screen:

- Large check icon.
- “You’re marked as okay.”
- “Diwas will see this on his dashboard right away.”
- Continue button to mood.

This confirmation should call `AppState.checkIn()` once.

### Mood

Show a full-screen, senior-friendly mood selection:

- “How are you feeling today?”
- Three oversized choices:
  - Good maps to `.great`
  - Okay maps to `.okay`
  - Not great maps to `.low`

Recording mood returns to Senior Home.

### Medicines

Show large rows for the four seeded medicines. The demo should start at 3 of 4 taken.

Rows can be toggled locally through state/repository when useful for demonstration. This is not a real medication reminder system.

### SOS Countdown

SOS is full-screen coral.

Behavior:

- Show warning icon, “Sending alert to your family,” explanatory copy, and large countdown from 5.
- Cancel returns to Senior Home without creating an alert.
- Letting countdown reach 0 calls `AppState.triggerSOS()` exactly once.
- Show senior confirmation: “Your alert was sent.”

Safety language:

- Do not say emergency services are coming.
- Do not imply a real push/SMS was sent.
- It is acceptable to say Diwas can see the alert in the demo dashboard.

### Family Dashboard

Family Home is Diwas’s main screen.

Content:

- “Good evening, Diwas.”
- Austin/Kathmandu time-zone card.
- Active SOS banner when present.
- Maya summary card:
  - Name, relationship, city.
  - Status chip: All good, Needs attention, or SOS.
  - Check-in status.
  - Mood.
  - Medicines 3 of 4.
  - Steps 2,840.
  - Sleep 6h 20m.
  - Resting heart rate 72 bpm.
- AI care insight card:
  - Free teaser by default.
  - Full insight when premium is unlocked.
  - Safety note that AI organizes care information and does not diagnose, prescribe, or detect emergencies.
- Missed medicine banner when evening medicine is not taken and no SOS is active.

Family dashboard must react to senior actions through shared `AppState`.

### Health Timeline

Health shows deterministic seven-day data.

Cards:

- Sleep bars, latest 6h 20m.
- Steps bars, latest 2,840.
- Resting heart rate line, latest 72 bpm.
- Medicine adherence ring, 92% weekly demo value.
- Mood trend.

Use simple custom SwiftUI shapes and bars first. Swift Charts is optional only if it does not slow the build.

Label data as demo data where appropriate. Never claim it came from HealthKit.

### Alerts

Alerts show care context, not diagnosis.

Include:

- Active SOS alert at the top when `AppState.hasEmergency` is true.
- Missed medicine alert when evening medicine is untaken.
- Quieter activity alert.
- Later check-in alert.
- Resolved historical SOS alert.

Call and Message actions should show a demo toast/sheet explaining that no real call/message is placed. Acknowledge/dismiss for the active SOS should call `AppState.acknowledgeEmergency()`.

### Appointments

Appointments show seeded Maya appointment plus optional static future cards.

Primary seeded appointment:

- `Routine check-up`
- Clinician from repository or display `Dr. Rana` if visual polish needs a specific card title.
- Date badge.
- Time/location/notes.
- Family mode shows “Prepare with CareCompanion AI.”
- Senior mode shows a reminder-set style note without implying real notification delivery.

When premium is locked, tapping AI prep opens paywall. When premium is unlocked, show deterministic prep:

- Recent observations:
  - Sleep lower than usual.
  - Resting heart rate 72 bpm within 67-74 range.
  - One evening medicine missed.
- Questions to discuss:
  - Any dizziness, fatigue, or routine changes?
  - Should the evening reminder be earlier?
  - Are sleep changes worth discussing?

No diagnosis, treatment recommendation, or probability estimate.

### Paywall

The paywall screen is a bridge to RevenueCatUI.

For this design pass:

- Keep a polished SwiftUI paywall fallback matching Claude v2.
- Route premium-gated actions through one place.
- If RevenueCatUI is available and configured, present the real RevenueCat paywall.
- If credentials/packages are blocked, use the demo fallback only for continuing UI work and mark it clearly in docs/status.

Entitlements that unlock premium:

- `premium_insights`
- `plus_plan`
- `pro_plan`

Premium unlock enables:

- Full AI Care Insight.
- Appointment Prep.

Check-in, mood, medicines, manual appointments, health metrics, and SOS remain free.

### Profile

Profile is a lightweight family tab for demo completeness:

- Diwas Sharma.
- Austin, Texas.
- Current plan label.
- Caring for Maya Sharma.
- Maya time zone.
- Quiet hours display.

Do not build editable account settings in this phase.

## State And Data

Keep the existing boundaries:

- `CareRepository`
- `DemoCareRepository`
- `AppState`
- `DemoScenarioController`
- `SubscriptionService` / `AccessPolicy`

Add or extend:

- A lightweight app screen enum for navigation state.
- `AIService` protocol.
- `MockAIService` deterministic implementation.
- Optional paywall context enum.
- Demo toast state for non-wired calls/messages.

Views must not call RevenueCat, Supabase, or AI APIs directly. Views act on `AppState` or injected services.

## AI Safety

Allowed:

- Summarizing recent changes.
- Organizing observations.
- Suggesting questions for a clinician.
- Suggesting family check-ins.

Not allowed:

- Diagnosis.
- Prescribing.
- Disease probability.
- Automated emergency detection.
- “This is urgent” based on passive health data.

Use language like:

- “worth discussing”
- “consider checking in”
- “recent change”
- “care context”
- “questions to ask”

## Visual System

Primary colors:

- Background: `#FBF9F4`
- Cream band/card: `#F3F1E8`, `#F9F7F0`
- Ink: `#1F2320`
- Secondary text: `#5A5F58`
- Muted text: `#8A8E86`
- Sage: `#4F7A5B`
- Dark sage: `#3F6B4C`
- Coral: `#C9543A`
- Amber: `#8A6119`
- Blue: `#2F6B8F`

Typography:

- Use system font for body and controls.
- Use a serif-like display style where available. If no bundled font is added, use `.serif` / `Font.custom` fallback carefully, or approximate with large `.system(.largeTitle, design: .serif)` headings.
- Do not add a remote font dependency.

Components:

- `CareScreen`
- `CareCard`
- `CarePrimaryButton`
- `CareSecondaryButton`
- `CareMetricTile`
- `CareBottomNav`
- `CareToast`
- `CareDateBadge`
- `CareStatusChip`
- `CareMiniChart`

Accessibility:

- Large tap targets.
- VoiceOver labels for all icon-only buttons.
- Dynamic Type-friendly vertical layouts.
- Reduce Motion support for countdown pulse and transitions.
- Sufficient contrast for text on sage/coral.

## Error Handling

Demo mode should not fail due to network.

If RevenueCat is not configured:

- Paywall fallback can unlock a local preview flag for UI demonstration.
- The app and status docs must not claim real purchase validation.

If AI service fails:

- Use deterministic fallback.
- Show retry only where it helps the demo.

If a user taps call/message:

- Show a toast explaining that the demo does not place real calls/messages.

## Testing

Core tests:

- Check-in is idempotent.
- Mood recording updates selected senior.
- SOS cancel does not create alert.
- SOS completion creates exactly one active alert.
- Acknowledging emergency clears `hasEmergency`.
- Reset clears role, check-in, SOS, premium preview, and appointment prep.
- Access policy unlocks premium only with correct entitlements/plan.
- Mock AI output is deterministic and medically safe.

Build verification:

- `xcodebuild` app build for the booted simulator.
- `swift test` or Xcode test target where available.
- Manual simulator pass through the 90-second demo.

Visual verification:

- Run the app in simulator after implementation.
- Check at least onboarding, senior home, mood, family dashboard, appointments, health, alerts, and SOS.
- Fix obvious text clipping/overlap before calling the work complete.

## Implementation Order

1. Add app navigation state and service boundaries.
2. Expand design system.
3. Build onboarding and role shells.
4. Build senior home, check-in confirmation, mood, medicines, appointments.
5. Build SOS countdown and confirmation.
6. Build family dashboard, health, alerts, appointments/prep, profile.
7. Add paywall fallback and RevenueCat seam.
8. Add hidden demo controls.
9. Add focused tests.
10. Build, run simulator, and polish.

## Completion Criteria

The phase is complete when:

- The app builds.
- The simulator runs the complete Maya/Diwas flow.
- Demo mode works offline.
- Check-in, mood, premium preview, appointment prep, and SOS state all propagate correctly.
- Safety language is compliant.
- Primary screens match Claude v2 direction closely enough to feel intentional and premium.
- Hidden demo reset works.
- Any RevenueCat limitation is documented honestly.
