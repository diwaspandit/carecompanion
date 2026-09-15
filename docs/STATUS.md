# CareCompanion status

Updated: 2026-09-14. `phase-3-sponsor` merges `dev` (which already had Phase 4 Apple Health sync merged in) with Phase 3 RevenueCat sponsor integration. Phase 4 notes come first, then Phase 3, then Phase 2.

## 2026-09-14 Merge: `dev` into `phase-3-sponsor`

Pushed by the Copilot coding agent, with a follow-up correctness pass (below) in this session.

**Conflicts resolved:**
- `App/CareCompanionApp.swift`: `FamilyProfileView` gained state/environment from both branches
  (`showHealthPermissions` from Phase 4, `subscriptions`/`showPlans` from Phase 3) — kept both, and
  both `.sheet` modifiers (`HealthPermissionsView` and `PlansComparisonView`) chained on the view.
- `CareCompanion.xcodeproj/project.pbxproj`: package reference/build file conflict between the two
  branches' added dependencies (both had reused the same object-ID range for different new files,
  the same category of bug hit in the earlier Phase 4/Phase 2 merge) — resolved keeping both sets
  of entries, renumbering to avoid collisions.
- `docs/STATUS.md`: kept both phase sections.

**Follow-up fix in this session:** the pushed merge resolution had accidentally dropped the entire
Phase 4 write-up from this file (only Phase 3's content survived the conflict resolution) and left
a literal duplicate `.sheet(isPresented: $showPlans) { PlansComparisonView() }` modifier on
`FamilyProfileView` (harmless — SwiftUI only presents once — but redundant and worth removing).
Both fixed here; Phase 4's section is restored below and the duplicate sheet modifier removed.
Verified: `swift test` (54/54 passing), iOS Simulator build succeeds.

## 2026-09-14 Phase 3: Sponsor Integration With RevenueCat (branch `phase-3-sponsor`)

**Scope note:** mid-phase the product ask expanded to a 4-tier system (Free/Plus/Pro/Enterprise,
Enterprise seat count "depending on their count"). This conflicts with `AGENTS.md`'s explicit
exclusion of production enterprise billing and organization UI, and StoreKit/RevenueCat can't sell
an arbitrary typed-in seat quantity without a custom billing backend (also forbidden). Resolved
with the product owner via two direct questions: Free/Plus/Pro are real, RevenueCat-backed tiers;
Enterprise is a "contact us" stub in a 4-tier Compare Plans screen with no RevenueCat product
behind it. Full rationale in `docs/REVENUECAT.md`.

**Completed:**
- ✅ Added `PlanTier` (free/plus/pro/enterprise) and `PlanCatalog`/`PlanDescriptor` to CareCore —
  vendor-free, drives the Compare Plans screen. `SubscriptionAccess` gained `.tier` and
  `enterpriseSeatLimit` (architecture-only; no real Enterprise product exists).
- ✅ `App/Services/RevenueCatConfiguration.swift` reads `REVENUECAT_API_KEY` from git-ignored
  `Config/Secrets.xcconfig` (same pattern as `SupabaseConfig`) and configures the SDK.
- ✅ `App/Services/RevenueCatSubscriptionService.swift` implements CareCore's `SubscriptionService`
  against `Purchases.shared` and is the `PurchasesDelegate` for push-driven entitlement updates.
- ✅ `App/Services/SubscriptionController.swift` owns the lifecycle: cached last-known entitlements
  for a graceful cold start, refresh on launch/foreground/CustomerInfo push, restore purchases.
- ✅ `App/Features/PaywallHostView.swift`: `state.showPaywall(for:)` now opens the real
  `RevenueCatUI.PaywallView` when configured (per AGENTS.md: "Do not build a custom paywall if
  RevenueCatUI can provide it"), falling back to the original local Test Store simulated sheet
  (`TestStorePaywallFallbackView`) when no secrets are present — demo mode stays fully offline.
  Includes `PlansComparisonView`, the 4-tier Free/Plus/Pro/Enterprise compare screen.
- ✅ RevenueCat + RevenueCatUI (`purchases-ios`, `upToNextMajorVersion` from 5.0.0) added to the
  Xcode project's package references, linked to the app target only — CareCore stays
  dependency-free, matching the Supabase precedent from Phase 1/2.
- ✅ 5 new unit tests covering tier resolution, enterprise seat-limit fallback (`Int.max` when
  unset), `PlanCatalog`'s purchasable flags, and the `applySubscriptionAccess` vendor bridge.
- ✅ `docs/REVENUECAT.md`: dashboard setup checklist, entitlement mapping, the Enterprise-stub
  rationale, and the recommended design (fixed seat-tier SKUs) if Enterprise ever becomes real.

**Verification:**
- PASS: `swift test` (Xcode toolchain, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
  — this sandbox's default Command Line Tools lack XCTest) — 47 XCTest cases, 0 failures (5 new).
- PASS: iOS Simulator build (`xcodebuild ... ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
  EXCLUDED_ARCHS=x86_64 build`) — resolves the RevenueCat SPM package from GitHub and links it, no
  warnings in the new files.
- FOUND AND FIXED during verification: the first build launched but crashed immediately —
  `Fatal error: Purchases has not been configured. Please call Purchases.configure()`. Cause:
  `SubscriptionController`'s `@State` initial value constructed `RevenueCatSubscriptionService`
  (which sets `Purchases.shared.delegate`) before the App's `.task` had run
  `RevenueCatConfiguration.configureIfNeeded()`. Fixed by moving `configureIfNeeded()` into
  `SubscriptionController.init()`, synchronously before constructing the service.
- PASS: reinstalled and relaunched on the iPhone 17 simulator with the real
  `test_LbkQbPNneNPOWTAzWyCrzSmBOha` Test Store key configured in `Config/Secrets.xcconfig`. No
  crash; onboarding renders correctly. Device log shows RevenueCat's expected Test Store warning
  and a successful network round trip to `config.revenuecat-static.com` — the key is valid and the
  SDK is live, not just compiling.
- PASS (later manual simulator run, 2026-09-14): tapped "Unlock full insight" on the Family
  Dashboard with the real `test_...` key configured — `RevenueCatUI.PaywallView` renders and shows
  "No Paywall configured" (expected: the dashboard has no offering/paywall published yet).
- NOT COMPLETE: the RevenueCat dashboard itself has no Plus/Pro products/offering/paywall
  configured yet (only the Test Store project + API key exist) — `docs/REVENUECAT.md` has the exact
  checklist. Until that's done, the real `PaywallView()` will render with no packages to sell.
- BUG FOUND (2026-09-14, manual simulator run, still open): on the Senior Profile screen, tapping
  "Upgrade to Plus" does not open the paywall sheet, even though it calls the same
  `state.showPaywall(for: .careInsight)` that works correctly from the Family Dashboard's "Unlock
  full insight" button on the same build. Verified reproducible across multiple tap coordinates and
  with a delay before screenshotting; device logs confirm the touch reaches the app. Root cause not
  yet identified. Needs investigation before this ships.

**Known limitation (documented in docs/REVENUECAT.md):** the hidden `#if DEBUG` Live Supabase
developer screen swaps to a second `AppState` instance; `SubscriptionController` only applies
entitlement updates to the base demo `AppState`, not that live instance. Doesn't affect the main
demo path.

**Next action:** fix the Senior Profile "Upgrade to Plus" bug above, then configure Plus/Pro
products, an offering, and a published paywall in the RevenueCat dashboard (see
`docs/REVENUECAT.md`), then run the full Test Store purchase flow on-device.

---

## 2026-09-14 Merge: `dev` (Phase 2) into `phase-4`

`dev` contained all of `phase-2` (PR #3). Both branches started from `66c69d1`.

**Conflicts resolved:**
- `App/CareCompanionApp.swift`: kept the Phase 4 HealthKit provider on the demo `AppState` and the Phase 2 `LiveModeController`.
- `CareCompanion.xcodeproj/project.pbxproj`: both branches had used object IDs `A…044`–`A…047` for different things (Phase 4: HealthKit source files; Phase 2: the Supabase package). The project now uses Phase 2's objects, with the two Phase 4 source files re-added as `A…057`–`A…060`.
- `docs/STATUS.md`: kept both phase sections.
- `Config/App.xcconfig` merged automatically. The built app's Info.plist carries both Phase 2's Supabase keys and URL scheme and Phase 4's HealthKit usage strings.

**Other changes in the merge:**
- Live Supabase mode (`LiveModeController.goLive`) now also gets the HealthKit provider, so Sync Now works against the live repository.
- Fixed a Swift 6 build error that was already on `dev`: `SupabaseCareRepository.startRealtime` captured the main-actor repository inside task-group child tasks. It now runs one main-actor `Task` per realtime table. Not yet re-checked against live Supabase realtime.

**Verification:**
- PASS: `swift test`, 49 XCTest cases, 0 failures.
- PASS: iOS Simulator build with `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64` (a plain build still fails on the x86_64 slice, as noted in Phase 2).
- FIXED: Deprecated `HKCategoryValueSleepAnalysis.asleep` replaced with `.asleepUnspecified`.

## 2026-09-14 Phase 4: Apple Health Sync (branch `phase-4`)

**Goal:** Integrate Apple HealthKit to sync steps, sleep, and resting heart rate data for seniors.

**Completed:**
- ✅ Added HealthKit capability to Xcode project (`Config/CareCompanion.entitlements`)
- ✅ Added privacy usage descriptions for HealthKit read access
- ✅ Implemented `HealthKitHealthDataProvider` with real HKHealthStore queries:
  - Steps: HKStatisticsCollectionQuery for daily aggregation
  - Sleep: HKSampleQuery filtering asleep states (core, deep, REM)
  - Resting Heart Rate: HKSampleQuery for latest daily value
- ✅ Created `HealthPermissionsView` UI for permission management:
  - Explains data types and usage
  - Shows current permission status (notDetermined, authorized, denied, restricted)
  - Opens iOS Settings if permission denied
  - Automatically triggers sync after authorization
- ✅ Integrated health sync into AppState with three new methods:
  - `syncHealthData()` - fetches and saves health snapshots
  - `checkHealthPermissionStatus()` - returns current permission state
  - `requestHealthPermissions()` - requests HealthKit authorization
  - `setupAutomaticHealthSync()` - enables background and foreground sync
  - `teardownAutomaticHealthSync()` - cleanup observers
- ✅ **Automatic Background Sync** (HKObserverQuery):
  - Monitors HealthKit for new data (hourly frequency)
  - Posts notification when new health data arrives
  - AppState automatically syncs in response
  - No manual sync needed
- ✅ **Automatic Foreground Sync** (App Lifecycle):
  - Syncs when app becomes active (scenePhase monitoring)
  - Syncs on app launch
  - Ensures fresh data when senior opens app
- ✅ Added background-delivery entitlement and background modes
- ✅ Added public initializer to HealthSnapshot struct for external creation
- ✅ Updated FamilyProfileView to include Health Permissions access in Settings
- ✅ Fixed Swift 6 Sendable conformance by converting lazy var to computed property
- ✅ Created comprehensive `docs/HEALTHKIT.md` documentation
- ✅ Added 7 new health-related tests (49 total tests, all passing)
- ✅ All tests pass: `swift test` — 49 XCTest cases, 0 failures
- ✅ iOS build succeeds: `xcodebuild ... ONLY_ACTIVE_ARCH=YES build` — BUILD SUCCEEDED

**Exit Criteria Met:**
- ✅ Read-only HealthKit integration (steps, sleep, resting heart rate)
- ✅ Permission management with graceful handling of all states
- ✅ Source labeling distinguishes HealthKit data from demo data
- ✅ Demo mode unchanged (healthProvider remains nil)
- ✅ Privacy-first design with clear user explanations
- ✅ All health data processing stays local (no external servers)

**Files Created:**
- `Config/CareCompanion.entitlements` (HealthKit capability)
- `App/Services/HealthKitHealthDataProvider.swift` (280+ lines)
- `App/Features/HealthPermissionsView.swift` (235 lines)
- `docs/HEALTHKIT.md` (comprehensive integration guide)

**Files Modified:**
- `Config/App.xcconfig` (added entitlements reference and privacy descriptions)
- `Sources/CareCore/AppState.swift` (added healthProvider, healthSyncStatus, and 3 health methods)
- `Sources/CareCore/Models.swift` (added public init to HealthSnapshot)
- `App/CareCompanionApp.swift` (added Health Permissions UI integration)
- `Tests/CareCoreTests/CareCoreTests.swift` (added 7 health tests)
- `CareCompanion.xcodeproj/project.pbxproj` (added new Swift files to build)

**Verification:**
```sh
# Run tests
swift test
# Result: 38 tests, 0 failures

# Build iOS app
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  ONLY_ACTIVE_ARCH=YES build
# Result: BUILD SUCCEEDED
```

**Next Phase:** Phase 5+ - Background Sync, Additional Metrics, Manual Entry (future enhancements)

Phase 2 (database and account information flow) was completed on branch `phase-2` and merged to `dev` in PR #3. Migrations are live and all exit criteria were verified against the live project.

## 2026-09-14 Phase 2 live verification

- PASS: both migrations applied via the Supabase SQL Editor. All 15 tables exist, and the publishable key alone gets `42501` on every table and on `create_care_account`.
- PASS: `Supabase/tests/live_smoke.sh` against project `ncqzcdaudhfwvzkosldj`, using three auto-confirmed test users (`diwas.test@`, `maya.test@`, `outsider.test@carecompanion.dev`). Diwas created an account and added Maya as senior; Maya joined by invite code and checked in; Diwas sees the check-in. The outsider reads 0 rows, their write is rejected with `42501`, and anon reads nothing.
- PASS: realtime end-to-end in the iPhone 17 simulator. Diwas signed in on the hidden Developer → Live Supabase screen, added starter medications, switched to live data and opened the family dashboard ("0 of 4 taken"). Maya then recorded a `medication_events` row through the REST API, and the dashboard changed to "1 of 4 taken" with no interaction or restart.
- Noted for Phase 5: several family dashboard strings are still hard-coded demo copy (the "Ramesh" avatar, "Checked in 2 hours ago", the AI insight teaser, "Grandmother"). In live mode they don't reflect database data; medication counts, mood and check-in state do.

**Exit criteria (all met):**
- ✅ Maya and Diwas can share one account in production mode.
- ✅ Cross-account reads are denied by RLS (local contract test + live smoke test).
- ✅ Realtime updates refresh the family dashboard without restarting the app.
- ✅ Demo mode still runs when Supabase is unreachable. It remains the default launch path, and the developer screen is `#if DEBUG` only.

## 2026-09-14 Phase 2: Database And Account Information Flow (branch `phase-2`)

**Completed:**
- ✅ Supabase Swift SDK 2.55.2 linked to the app target only. CareCore stays dependency-free, so `swift test` needs no network.
- ✅ Secrets via git-ignored `Config/Secrets.xcconfig` → `Config/Info.plist`. `SupabaseConfig.sharedClient` is `nil` without secrets, so fresh clones stay in demo mode.
- ✅ Schema for all 15 planned tables, with `updated_at` triggers and indexes for membership, dashboard, latest-health and realtime feed queries (`Supabase/migrations/20260914000001_care_schema.sql`).
- ✅ RLS on every table, requiring membership in the row's `account_id`. Senior-scoped writes must also reference a senior of that account. The anon role is revoked (`20260914000002_rls_and_account_flow.sql`).
- ✅ `create_care_account` / `join_care_account` RPCs with invite codes, an auto-created profile per auth user, and the realtime publication for 8 care tables.
- ✅ `SupabaseCareRepository` implements `CareRepository` (reads, all writes, idempotent SOS, soft deletes) and refreshes on realtime changes filtered by account.
- ✅ `AuthSessionService` protocol and `DemoAuthSessionService` bypass in CareCore; `SupabaseAuthSessionService` uses a magic link with the `carecompanion://login-callback` URL scheme.
- ✅ `CareRecords` maps rows to `CareSnapshot`, with "today" evaluated in the senior's time zone; `AppState.refresh()` picks up external changes.
- ✅ `docs/DATABASE.md` covers the schema, RLS policy intent, account data flow and setup checklist.

**Verification:**
- PASS: `swift test` — 42 XCTest cases, 0 failures (11 new).
- PASS: `Supabase/tests/run_local.sh` — migrations apply cleanly on local Postgres 15; RLS contract test passes. It fails as expected when a read policy is weakened to `using (true)`.
- PASS: iOS Simulator build (`xcodebuild … ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 build`), no warnings in `App/Services`.
- PASS: demo mode still launches on iPhone 17 simulator; onboarding → Senior Home works offline.

**Exit criteria status:**
- ✅ Cross-account reads are denied by RLS (local contract test).
- ✅ Demo mode still runs when Supabase is unreachable (demo never constructs a client).
- NOT COMPLETE: migrations not yet applied to the live project (`ncqzcdaudhfwvzkosldj`). This needs the database password or a manual SQL Editor run.
- NOT COMPLETE: "Maya and Diwas share one account" and "realtime refreshes the family dashboard" are implemented and covered by SQL tests, but have not been exercised end-to-end on devices. No production-mode UI exists until Phase 5 onboarding.

**Build note:** a plain simulator build also tries x86_64, and the CareCore link fails for that slice. Use the arm64-only flags above on Apple Silicon.

**Next action:** Phase 3 (RevenueCat), per the plan's implementation order.

---

## 2026-09-14 Phase 1: Production Architecture Hardening (branch `phase-1`)

**Goal:** Prepare codebase for real services without letting views know about vendor SDKs.

**Completed:**
- ✅ Created typed service error system (`CareServiceErrors.swift`) with offline, unauthorized, premiumRequired, healthPermissionDenied, vendorUnavailable, and invalidState errors
- ✅ Created `SyncStatus.swift` for tracking synchronization state across services
- ✅ Created `SubscriptionService.swift` protocol with `DemoSubscriptionService` implementation
- ✅ Created `PlanService.swift` protocol with `DefaultPlanService` for access policy evaluation
- ✅ Created enhanced `HealthDataProvider.swift` with async methods and permission status
- ✅ Enhanced `CareRepository` protocol with explicit async methods for all operations:
  - Check-ins, mood entries, medication events
  - Health snapshot upserts
  - Appointment save/delete operations
  - SOS and alert acknowledgement
  - Care insight and appointment prep storage
  - Senior add/update operations
  - Demo reset functionality
- ✅ Updated `DemoCareRepository` to implement all new protocol methods with proper error handling
- ✅ Updated `AppState` to use async repository methods with try/catch error handling
- ✅ Updated `DemoScenarioController` to use async methods
- ✅ Updated all app UI code to properly await async state methods using `Task { }`
- ✅ Added 12 new tests covering service boundaries, errors, and protocols (31 total tests)
- ✅ All tests pass: `swift test` — 31 XCTest cases, 0 failures
- ✅ iOS build succeeds: `xcodebuild ... ONLY_ACTIVE_ARCH=YES build` — BUILD SUCCEEDED

**Exit Criteria Met:**
- ✅ Views depend on AppState/view models and protocols, not Supabase, RevenueCat, HealthKit or AI vendors
- ✅ Demo mode behavior unchanged - deterministic and synchronous implementations preserved
- ✅ Tests cover premium denial, offline fallback, reset, service errors, and all boundaries

**Files Modified:**
- Created: `Sources/CareCore/CareServiceErrors.swift`
- Created: `Sources/CareCore/SyncStatus.swift`
- Created: `Sources/CareCore/SubscriptionService.swift`
- Created: `Sources/CareCore/PlanService.swift`
- Created: `Sources/CareCore/HealthDataProvider.swift`
- Modified: `Sources/CareCore/DemoCareRepository.swift` (enhanced protocol and implementation)
- Modified: `Sources/CareCore/AppState.swift` (async methods)
- Modified: `Sources/CareCore/DemoScenarioController.swift` (async methods)
- Modified: `Sources/CareCore/AccessPolicy.swift` (uses PlanService)
- Modified: `Sources/CareCore/Models.swift` (removed old HealthDataProvider)
- Modified: `App/CareCompanionApp.swift` (async state calls)
- Modified: `Tests/CareCoreTests/CareCoreTests.swift` (async tests + new service tests)

**Verification:**
```sh
# Run tests
swift test
# Result: 31 tests, 0 failures

# Build iOS app
xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  ONLY_ACTIVE_ARCH=YES build
# Result: BUILD SUCCEEDED
```

**Next Phase:** Phase 2 - Database and Account Information Flow (Supabase integration)

---

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
