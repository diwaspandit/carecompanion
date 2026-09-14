# CareCompanion status

Updated: 2026-09-14. Claude/Lovable reference UI plus functional demo click-through implemented on branch Dwmi01; iOS build and simulator launch verified.

## 2026-09-14 Phase 0 stabilization checkpoint (branch `phase-0-stabilize-demo`)

- Added a visible "demo data, not synced from HealthKit" notice on the family dashboard steps/sleep metrics and on the Health Timeline screen, per AGENTS.md's requirement that seeded data never be presented as HealthKit data.
- Attempted a full `xcodebuild test` run (unit tests + `CareCompanionDemoUITests`, which already covers the core demo path three times plus an SOS/reset path) on a booted iPhone 17 Pro simulator.
  - PASS: the app and test targets build cleanly.
  - BLOCKED (environment, not code): the UI test runner failed to initialize with `XCTDaemonErrorDomain Code=18 "Timed out waiting for AX loaded notification"` — the simulator's accessibility daemon did not come up in this sandboxed session. This is an environment limitation of the sandbox, not a defect in the app or the tests; it needs to be run outside this sandbox (a normal Xcode/Terminal session) to get a real pass/fail signal.
- PASS: `swift test` — 19 XCTest cases, 0 failures (re-verified after the copy change).
- PASS: `xcodebuild ... build` for the iOS Simulator — BUILD SUCCEEDED (re-verified after the copy change).
- STILL NOT COMPLETE: three consecutive 90-second demo runs, manual or via `CareCompanionDemoUITests`, have not been observed to pass — blocked on the sandbox's AX daemon issue above for the automated path; manual runs need a human or a non-sandboxed session.

## 2026-09-14 senior tab bar bug fix (branch `phase-0-stabilize-demo`)

- Bug: tapping "Medicines" or "Visits" in the senior's bottom tab bar (and the "Next Visit" card on Senior Home) switched the app's role to family and jumped to Diwas's Family Dashboard, instead of staying on Maya's own screen.
- Root cause: `SeniorTab` (`Sources/CareCore/AppNavigation.swift`) only defined `.home`, `.mood` and `.sos`. There was no senior-scoped destination for Medicines or Visits, so those buttons fell back to either `.home` (Medicines, silently a no-op) or `state.switchToFamily(tab: .appointments)` (Visits, an outright role switch) — never a bug in the family screens themselves.
- Fix: added `.medicines` and `.visits` cases to `SeniorTab`; added two new senior-scoped screens (`SeniorMedicinesScreen`, `SeniorVisitsScreen`) that reuse the existing `MedicineListView`/`NextVisitCard` content under the senior's own header and bottom bar; rewired the "Medicines" and "Visits" tab buttons and the "Next Visit" card to set `state.seniorTab` instead of switching role.
- Verified live on the iPhone 17 simulator: from Senior Home, tapping "Medicines" now shows Maya's own medicine list (tab highlighted, still on Maya's UI); tapping "Visits" now shows Maya's own next-visit card. Neither leaves the senior role.
- PASS: `swift test` — 19 XCTest cases, 0 failures (re-verified after the fix).
- PASS: `xcodebuild ... build` for the iOS Simulator — BUILD SUCCEEDED (re-verified after the fix).

## 2026-09-14 senior "Messages" tab bug fix (branch `phase-0-stabilize-demo`)

- Bug: the senior bottom tab bar's "Messages" button (chat-bubble icon) silently opened the Mood recording screen instead of a messages screen — `active: state.seniorTab == .mood` / `{ state.seniorTab = .mood }`. Same root cause class as the Medicines/Visits bug: no real senior-scoped destination existed for it.
- Fix: added a `.messages` `SeniorTab` case and a `SeniorMessagesScreen` that reuses the same "messaging is intentionally light for the demo" copy already used on the family side's `ChatsView` (AGENTS.md scopes out complex messaging). Rewired the "Messages" button to set `state.seniorTab = .messages`.
- The check-in → mood-recording flow (`AppState.checkIn()` sets `seniorTab = .mood` directly) was not touched and still works — this only removed the mislabeled manual shortcut into it.
- Verified live on the iPhone 17 simulator: "Messages" now shows its own screen, tab highlighted, no longer opens Mood.
- PASS: `swift test` — 19 XCTest cases, 0 failures (re-verified). PASS: iOS Simulator build (re-verified).

## 2026-09-14 family Profile screen (branch `phase-0-stabilize-demo`)

- New feature, not a bug fix: added a "Profile" tab (`person.crop.circle`) to the family bottom bar, replacing the standalone "Chats" tab button — matching `docs/LOVABLE_REFERENCE.md`'s live site, which has a Profile tab on the family side only (senior side has no Profile in the reference either; Home/Medicines/Visits only).
- Adapted rather than ported 1:1: the reference's Profile screen includes "Linked devices" (Apple Watch/iPhone battery + sync status) and stats captioned "Auto-calibrated from Apple Health" — both directly conflict with AGENTS.md's explicit exclusion of HealthKit/Apple Watch and its rule that seeded data must never claim HealthKit provenance. Kept the senior header, emergency contacts (with Add), medications (reusing `MedicineListView`), and a health-stats card, but relabeled the stats "Demo data for this preview, not synced from HealthKit." (same pattern as the Health Timeline/family dashboard notices) and dropped the Linked Devices section.
- "Switch role" is wired to `AppState.switchToSenior()` (already existed, unused until now) — this is the first thing in the app that fulfills onboarding's existing copy, "You can switch roles later in Settings."
- `ChatsView` itself is untouched and still reachable from Alert row "Message" actions (`state.familyTab = .chats`); only its persistent tab bar button was removed, matching the reference.
- Verified live on the iPhone 17 simulator: Home → family → Profile shows the full adapted layout; Switch role genuinely returns to Maya's Senior Home.
- PASS: `swift test` — 19 XCTest cases, 0 failures. PASS: iOS Simulator build — BUILD SUCCEEDED.

## 2026-09-14 checkpoint

- Implemented the Claude/Lovable-inspired SwiftUI demo: onboarding, senior home, mood recording, medications, SOS countdown, family dashboard, AI insight teaser/full state, appointment prep, paywall fallback and hidden demo menu.
- Added navigation state for onboarding/senior/family flows plus deterministic demo scenario reset paths.
- Added deterministic `MockAIService`, `CareInsight`, and `AppointmentPrep` with safety language that avoids diagnosis, treatment, emergency inference and disease-probability claims.
- Added medication toggling and updated demo data to named medications, 3 of 4 taken, Maya/Diwas story values and cardiology follow-up.
- RevenueCat entitlement seams are present through `SubscriptionAccess` and expected entitlement names (`plus_plan`, `pro_plan`, `premium_insights`). The running app currently uses a local Test Store fallback sheet because the RevenueCat SDK/package/API key are not configured in this repository yet.
- Added `docs/FULL_DEVELOPMENT_PLAN.md` as the phased production roadmap covering demo stabilization, service boundaries, Supabase information flow, RevenueCat sponsor/premium integration, Apple Health sync, safe AI and launch QA.

## 2026-09-14 verification

- PASS: `swift test` — 16 XCTest cases, 0 failures.
- PASS: `xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ONLY_ACTIVE_ARCH=YES build`.
- PASS: Installed and launched `com.carecompanion.txst` on the booted iPhone 17 simulator.
- PASS: Captured simulator screenshots for cold onboarding and family dashboard visual smoke checks.
- PASS: Checked live reference site at https://elder-link-guardian.lovable.app/ using gstack browse at 390x844 and captured `/private/tmp/lovable-onboarding.png`, `/private/tmp/lovable-senior.png`, and `/private/tmp/lovable-family.png`.
- PASS: Reworked SwiftUI to follow the Claude/Lovable mobile prototype more directly: onboarding role cards, senior home, medicines, next visit, mood picker, family dashboard, health timeline, alert center, appointments, bottom tab bars, and full-screen SOS states.
- PASS: Captured final native onboarding screenshot at `/private/tmp/carecompanion-claude-final-onboarding.png`.
- PASS: Functional demo wiring added: senior check-in advances to mood, mood hands off to family dashboard, alert badges are dynamic, alert actions call/message/dismiss, SOS hands off to family emergency, AI insight and appointment prep unlock through the paywall fallback, and buttons that were previously visual-only now show state changes or demo toasts.
- PASS: `swift test` after functional wiring — 19 XCTest cases, 0 failures.
- PASS: User verified the simulator demo flow works for demo on 2026-09-14.
- NOT COMPLETE: Real RevenueCatUI paywall/Test Store purchase is not wired to the SDK yet.
- NOT COMPLETE: Three consecutive fully manual 90-second demo runs have not been executed.

---

Historical baseline follows.

## Baseline evidence

- Read AGENTS.md and LOVABLE_REFERENCE.md completely.
- Initial tree contained only AGENTS.md, .gitignore and two docs. No Xcode project, app sources, packages or tests existed.
- Git root is the parent shipaton directory; initially no commits. Working branch: feat/carecompanion-foundation.
- No Xcode found in /Applications or Spotlight. Active developer directory: /Library/Developer/CommandLineTools.
- Swift compiler: Apple Swift 6.0.3. `xcrun simctl list devices available` fails because simctl is absent.
- Untouched `xcodebuild -version` failed. Newly scaffolded app build also fails before compilation because Xcode is absent. No known-good xcodebuild command yet.
- Prior “Last build: PASS” and “14/14 PASS” claims were unsupported and have been replaced with these observations.
- Lovable access resolved on 2026-09-14 using the updated public share link. Inspected onboarding, senior home, mood, family dashboard, appointments, alerts, health timeline and SOS countdown/confirmation. Nine reference screenshots and native translation notes are in docs/reference/.

## Implemented foundation

- Checked-in native Xcode project, shared app scheme, iOS 17 configuration and local CareCore package dependency.
- SwiftUI launch surface and warm design tokens, rounded card and large button components. This is a foundation screen, not completed onboarding.
- Care account/member/senior models, check-ins, moods, medications, health snapshots, appointments and alerts.
- CareRepository, deterministic DemoCareRepository and seven-day DemoHealthDataProvider.
- Observable AppState with shared role state, selected senior, check-in, mood, SOS acknowledgement and reset.
- DemoScenarioController for all six specified scenario markers; preview markers do not grant subscription access or generate actual AI preparation.
- SubscriptionService boundary and AccessPolicy for 1/5/25 seniors and active premium entitlements. RevenueCat itself is NOT integrated yet.
- Twelve XCTest cases written; execution blocked by missing XCTest in Command Line Tools.

## Verification

- PASS: portable CareCore `swift build` with writable /tmp caches.
- PASS: dependency-free core smoke checks for seed data, check-in, mood, SOS, access, reset and all six repeatable scenarios.
- PASS: project.pbxproj syntax (`plutil -lint`) and shared scheme XML parse.
- BLOCKED: `swift test` compiles CareCore then fails with `no such module 'XCTest'`.
- BLOCKED: iOS app build; Xcode and iOS SDK missing.
- NOT RUN: simulator UI tests, offline end-to-end demo, visual QA, RevenueCat purchases.
- Demo run: 0/3.

Reproduce portable build in the current sandbox:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/carecompanion-clang SWIFTPM_MODULECACHE_OVERRIDE=/tmp/carecompanion-modules swift build --disable-sandbox --cache-path /tmp/carecompanion-cache --scratch-path /tmp/carecompanion-build
sh Scripts/check-core.sh
```

The smoke executable is supplemental evidence and does not replace XCTest or iOS tests. The current app scheme has no iOS test target; add the UI test target in Phase 2 once Xcode can validate it.

## Phase gates

1. P0 foundation: implemented in part; iOS compilation and XCTest gate pending.
2. P0 senior/onboarding/SOS UI: pending Phase 1 build gate.
3. P0 family dashboard: pending.
4. P1 appointments and AI: pending.
5. P1 RevenueCat: pending; real dashboard configuration and public Test Store SDK key will be required at integration time.
6. P2 polish and three repeatable demos: pending.
7. P3 Supabase: deferred.
8. P3 live AI/charts: deferred.

## Human dependencies

NEED FROM HUMAN: Install Xcode at /Applications/Xcode.app, launch to complete setup, and install an iOS simulator runtime in Settings → Components.
WHY: Required iOS compiler, SDK, simulator and XCTest tools are absent.
WHERE IT GOES: /Applications/Xcode.app and Xcode Settings → Components.

Lovable authentication dependency: resolved. Public preview verified through gstack browse. Xcode rechecked on 2026-09-14: still unavailable.

## Next action

Once Xcode is available, use the DEVELOPER_DIR/xcodebuild command documented above, establish the actual passing app build, execute XCTest and fix failures before advancing to Phase 2. This checkpoint is partial foundation progress, not a stable iOS phase completion.

## Latest Lovable progress review

2026-09-14: Updated preview onboarding loads, but both senior and family entry points show a page-load error. Family retry also fails; console reports `useDemo must be used inside DemoProvider`. See docs/reference/PROGRESS_REVIEW.md. New demo features remain unverified until this provider/context regression is fixed in Lovable.
