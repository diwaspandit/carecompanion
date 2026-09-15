# Engineering decisions

- 2026-09-14: Existing repository is a specification-only starting point. Replace unsupported build/test pass claims with observed evidence.
- Use a portable CareCore Swift package for deterministic domain/state tests, plus a checked-in native Xcode app project. This permits useful foundation verification with Command Line Tools while Xcode installation is blocked.
- Use Observation on iOS 17/macOS 14, a main-actor AppState, value snapshots and stable seed IDs. Role switching shares a single state instance.
- Demo premium scenario is an explicit preview marker, not subscription authorization. Actual access is determined by active RevenueCat entitlements only.
- Local care reset restores identical seed IDs/dates and clears role/preview/transient state; it preserves separately owned subscription access.
- No Supabase or live AI implementation until the required P0–P2 build, purchase and demo gates pass.
- Phase 1 may be prepared and portable code tested while Xcode is unavailable, but no later phase is claimed complete or started past the build gate.
- Native Xcode project is checked in directly, avoiding an extra XcodeGen installation requirement. Its syntax is validated; only Xcode can verify package resolution and iOS compilation.
- SwiftPM cache paths are redirected to /tmp for this sandbox. Command Line Tools can compile CareCore but does not ship XCTest; retain XCTest coverage and use a separate dependency-free smoke executable for limited interim behavior verification.

- 2026-09-14: Public Lovable reference inspected; screenshots and translation notes captured in docs/reference/. Preserve its visual hierarchy while retaining Maya-only scope, real RevenueCat gating and honest local-demo SOS wording. No native feature phase advanced while Xcode remains unavailable.

- 2026-09-14 (Phase 2): Vendor-backed services live in `App/Services/` (app target), not `Sources/CareCore/` as the Phase 2 file list suggested. CareCore keeps only protocols, demo implementations and pure mapping, so `swift test` stays offline and dependency-free. This matches Phase 3's `App/Services/RevenueCatSubscriptionService.swift` placement.
- 2026-09-14 (Phase 2): The iOS app connects with the Supabase Swift SDK and the publishable key, with RLS as the security boundary. There is no custom server and no direct Postgres connection from the app, and the service_role key is never in the client.
- 2026-09-14 (Phase 2): Every care table denormalizes `account_id`, so RLS is one membership lookup and realtime can filter per account. Inserts also check `senior_in_account` to block cross-account senior references.
- 2026-09-14 (Phase 2): Medication "taken" is derived from the latest `medication_events` row on the senior's local day, not stored as a flag.
- 2026-09-14 (Phase 2): Supabase host is stored without the scheme in xcconfig, because `//` starts a comment there. Custom keys go through `Config/Info.plist`, since generated Info.plist ignores custom `INFOPLIST_KEY_*`.
- 2026-09-14 (Phase 2): Production mode is not wired into app startup yet. The demo stays the only launch path until Phase 5 provides sign-in and account onboarding UI.
- 2026-09-15 (Phase 0–4 gap fixes): Apple Health is tied to a senior device link (`account_seniors.profile_id`, set only by `claim_senior_profile`), enforced by a trigger, restrictive `health_snapshots` policies and `AppState.healthSyncEligibility`. Without it, a family member opening Health permissions would store their own health data as the senior's.
- 2026-09-15: Demo mode has no HealthKit provider at all, rather than a runtime toggle. The plan allows a development toggle, but none is needed while the Live Supabase developer screen exists.
- 2026-09-15: Incremental (anchored) HealthKit sync deferred to Phase 7. The seven-day re-fetch is idempotent (upsert on senior, date, source) and cheap for three metrics.
- 2026-09-15: RevenueCat app user ID is the care account ID, so the whole family shares a subscription. `subscription_statuses` is left for a server-side RevenueCat webhook; writing it from the client would let a phone forge entitlements.
- 2026-09-15: `--ui-testing` skips RevenueCat configuration so the demo UI tests stay offline and deterministic even with real secrets on the machine.
