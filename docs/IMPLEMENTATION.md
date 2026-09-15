# CareCompanion Implementation Plan

**Goal:** A flawless, repeatable 90-second native iOS care demo for Maya in Kathmandu and Diwas in Austin.
**Architecture:** SwiftUI views consume one observable AppState. Repository, health, AI and subscription boundaries isolate integrations. Demo care data is local and deterministic; paid access comes from RevenueCat customer entitlements.
**Technology:** Swift, SwiftUI, iOS 17+, NavigationStack, async/await, XCTest, RevenueCat and RevenueCatUI. No backend dependency on the demo path.
**Specifications:** Read AGENTS.md and docs/LOVABLE_REFERENCE.md in full before execution.

## Build gate and initial inspection

The initial repository has no app, Xcode project, package, tests or build configuration. Git has no commits. Xcode is absent; Command Line Tools provides Swift 6.0.3 but not simctl or the iOS SDK. The untouched `xcodebuild -version` fails. Therefore no known-good iOS build command exists yet. Previous STATUS.md pass claims are unsupported.

After Xcode is installed, run from CareCompanion:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
swift test
```

Use `xcrun simctl list devices available` to select an actual device UUID for `xcodebuild test -destination 'platform=iOS Simulator,id=<UUID>'`. Do not describe these commands as known-good until actually successful. Portable package tests are additional evidence, not a substitute for iOS compilation.

## Phase 1 — P0 foundation (in progress)

Files: Package.swift, Sources/CareCore/{Models,DemoCareRepository,AppState,DemoScenarioController,AccessPolicy}.swift, Tests/CareCoreTests/CareCoreTests.swift, App/{CareCompanionApp,DesignSystem}.swift, CareCompanion.xcodeproj, Config/App.xcconfig.

- [x] Scaffold app target and shared scheme with iOS 17 deployment target, generated Info.plist, explicit bundle identifier, no signing requirement for simulator builds.
- [ ] Test deterministic seed values, check-in idempotence, per-senior isolation, mood propagation, alert lifecycle, reset and access boundaries.
- [x] Implement CareAccount, AccountMember, AccountSenior and care entities with stable IDs.
- [x] Implement CareRepository and DemoCareRepository; inject DemoHealthDataProvider.
- [x] Implement observable AppState and deterministic scenarios. Synthetic premium preview must never grant purchased access.
- [x] Establish warm off-white, sage and coral tokens, rounded cards and accessible large controls.
- [ ] Compile, test, update STATUS and commit. Do not advance to Phase 2 with the iOS build gate unresolved.

## Phase 2 — P0 senior experience

Files: App/Features/{Onboarding,SeniorHome,Mood,SOS}View.swift; Tests/CareCoreTests/SOSTests.swift; iOS UI tests.

- [ ] Translate reference into native role selection and Maya's home. Preserve “Care that travels across time zones.”
- [ ] Bind “I'm okay” and mood choices to AppState; show confirmation and allow editing mood.
- [ ] Implement a cancellable 5-second SOS using a deadline, handling backgrounding and double taps. Never suggest local demo sends an actual emergency message.
- [ ] Test cancel before deadline, exactly-once alert, dismissal/background behavior and large Dynamic Type.
- [ ] Build, test, fix, update status and checkpoint.

## Phase 3 — P0 family experience

Files: App/Features/{FamilyDashboard,FamilyEmergency}View.swift; state propagation tests.

- [ ] Show Maya, check-in, 3/4 medication adherence, mood, 2,840 steps, 6h 20min sleep and 72 bpm, explicitly identified as demo data.
- [ ] Switching roles preserves state; active SOS takes visual priority and can be acknowledged.
- [ ] Test role switches, emergency acknowledgement and reset without stale state.
- [ ] Build, test, fix, update status and checkpoint.

## Phase 4 — P1 appointment and deterministic AI

Files: Sources/CareCore/{AIService,MockAIService}.swift; App/Features/{Appointments,CareInsight,AppointmentPrep}View.swift.

- [ ] Manual appointment creation/editing; seeded Maya appointment.
- [ ] Async deterministic insight and appointment preparation with loading, retry and reset cancellation.
- [ ] Full AI content checks AccessPolicy; teaser remains free. Clinician questions and observations only; no diagnosis or prescriptions.
- [ ] Test premium denial, changing observations, cancellation and deterministic fallback.
- [ ] Build, test, fix, update status and checkpoint.

## Phase 5 — P1 real RevenueCat

Files: App/Services/RevenueCatSubscriptionService.swift; App/Features/SubscriptionView.swift; Config/Secrets.xcconfig (ignored); docs/REVENUECAT.md.

- [ ] Resolve official purchases-ios package and link RevenueCat and RevenueCatUI. Pin resolved version.
- [ ] Configure with human-provided Test Store public SDK key; never use a secret API key in iOS.
- [ ] Human dashboard setup: Plus and Pro products, current offering and RevenueCatUI paywall; grant plus_plan + premium_insights for Plus and pro_plan + premium_insights for Pro.
- [ ] Present RevenueCatUI paywall and customer center; refresh entitlements after purchase, restore and foregrounding. Surface errors and cancellation without granting access.
- [ ] Enforce senior limits 1/5/25 and premium AI through AccessPolicy. Check-in, SOS, mood and manual appointments stay free.
- [ ] Test entitlement expiration, restore, purchase cancellation and real Test Store unlock on simulator. Never replace this gate with a simulated purchase.
- [ ] Build, test, fix, update status and checkpoint.

## Phase 6 — P2 judging quality

- [ ] Refine animations, haptics, VoiceOver order, contrast, Reduce Motion, Dynamic Type and small-screen layouts.
- [ ] Hidden developer menu resets all care state and pending work; reset does not erase or fabricate RevenueCat purchases.
- [ ] UI tests cover the complete role/check-in/mood/emergency path and reset.
- [ ] Perform full 90-second demo three consecutive times; include real Test Store paywall/unlock and offline care/AI fallback.
- [ ] Clean build, tests, screenshots, exact reproduction commands, status and stable commit.

## Phase 7 — P3 only after P0–P2 verified

- [ ] Supabase schema/migrations for account-scoped entities with RLS, anonymous auth and Realtime; implement SupabaseCareRepository behind the existing interface.
- [ ] Test cross-account isolation and reconnect behavior. Live service failure never disables local demo mode.
- [ ] Build, test, fix, update status and checkpoint.

## Phase 8 — optional P3

- [ ] LiveAIService calls authenticated server-side Supabase function; provider secret stays server-side. Validate structured safe output and fall back to MockAIService.
- [ ] Optional Swift Charts only if valuable to judging and all prior gates pass.
- [ ] Build, test, fix, update status and checkpoint. Stop adding features at completeness; perform QA.
