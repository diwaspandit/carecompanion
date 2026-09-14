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
