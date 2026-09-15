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

- 2026-09-15: Demo mode is removed at the product owner's direction. The app always runs against Supabase with real accounts; `DemoCareRepository`, `DemoScenarioController` and demo auth are gone from CareCore. An in-memory repository remains only in the test target.
- 2026-09-15: Premium AI is free for now (no paywall, no fake purchase). `SubscriptionAccess`/`AccessPolicy` stay in CareCore for when RevenueCat returns. Insight and appointment prep remain rule-based summaries of real data.
- 2026-09-15: The user's role comes from `account_members.role`. A senior's login is linked to their senior record through `account_seniors.profile_id`, set only via `claim_senior()` or by the senior creating their own record (trigger-enforced).
- 2026-09-15: Apple Health syncs only on the linked senior's own iPhone and writes to that senior. Previously any signed-in phone could upload its owner's Health data onto the selected senior.
- 2026-09-15: Health day keys are the phone's local calendar day stored as midnight UTC; sleep counts toward the wake-up day after merging overlapping samples. The previous code attributed sleep to the start day and shifted dates for time zones ahead of UTC.
- 2026-09-15: Inserts use device-generated ids with ignore-duplicates so a dropped HTTP/3 connection can be retried once safely. Observed live: an idle QUIC connection hit its keep-alive limit and a POST failed with -1005.
- 2026-09-15: Family messaging is one conversation per care account (`messages`), refreshed over realtime. No push notifications yet.
- 2026-09-15: Schema changes are applied to the live project with the Supabase Management API from a git-ignored access token; they are tested first in `Supabase/tests/run_docker.sh`.
