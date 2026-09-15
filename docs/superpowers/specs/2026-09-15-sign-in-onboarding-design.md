# Phase 5 Slice 1: Sign-in and Onboarding — Design

**Date:** 2026-09-15 · **Branch:** `phase-5-new` · **Plan:** [FULL_DEVELOPMENT_PLAN.md](../../FULL_DEVELOPMENT_PLAN.md), Phase 5

## Goal

Make production mode the normal way into the app. A new user signs in with an email code, creates or joins a family, and lands in the real app for their role. Demo mode stays one tap away.

This slice covers Phase 5's "Account onboarding" feature area and the exit criteria "A new family account can be created and used without demo data", "A caregiver can invite or join the same care account" and "Demo mode remains one tap away". Sign-out is included; the full Settings screen is a later slice.

## Decisions

| Question | Decision |
| --- | --- |
| Sign-in method | Email one-time code (6 digits) via Supabase `signInWithOTP` / `verifyOTP`. No magic link, no Sign in with Apple yet. |
| Senior setup | The family member creates the family and adds the senior. The senior signs in on their own phone, joins with the invite code as "senior", then links their login to the senior record ("This is me"). Seniors do not create families in this slice. |
| Role in production | Comes from the signed-in user's `account_members.role`. No role-choice screen and no "Switch role" in production. |
| Architecture | `AppSession` coordinator in CareCore behind `AuthSessionService` and a new `CareAccountService`; Supabase implementations in `App/Services`. Replaces `LiveModeController` / `LiveModeView`. |

## Launch routing

| Condition at launch | Destination |
| --- | --- |
| `--ui-testing` launch argument | Demo (existing role-choice screen) |
| Supabase not configured (no `Secrets.xcconfig`) | Welcome, with only "Try the demo" |
| Saved session restored | First unfinished onboarding step, or the app if complete |
| No session | Welcome |
| Saved session but server unreachable | "Can't reach CareCompanion" with Try again and Try the demo |

## Screens

All new screens live in `App/Features/Onboarding/`, one file each. Every step shows a busy state and an inline error. Every onboarding step after sign-in offers Sign out.

1. **Welcome** — "Get started" and "Try the demo". The demo opens the existing "I am a senior / family member" screen.
2. **Email** — email field and "Send code". Invalid emails are rejected locally with `EmailAddress.isValid`. New emails create the auth user (sign-in and sign-up are one step). DEBUG builds show a "Use password (debug)" link for test accounts.
3. **Code** — 6-digit field that submits when complete. "Resend code" is enabled 60 seconds after the last send. "Use a different email" returns to Email.
4. **Your name** — display name (required) and city (optional). Shown only while the profile's `display_name` is empty.
5. **Start or join a family** — *Start a family*: family name; creator joins as `family`. *Join with an invite code*: code plus "I'm a family member" or "I'm the senior".
6. **Add your senior** — shown when a family member's account has no senior: name, age, city, time zone (searchable, defaults to the phone's).
7. **Invite your family** — shown once, right after a family is created and its first senior is added: invite code with a Share button, then Continue.
8. **Which one is you?** — shown when the user joined as `senior` and no senior in the account is linked to their login. One unlinked senior: "This is me: <name>". Several: a list. None: "Ask your family to add you first" with Refresh.
9. **App** — `family` role → Family Dashboard; `senior` role → Senior Home.

**Moving between modes**

- Production Profile screens (family and senior) show "Sign out" instead of "Switch role", plus "Try the demo".
- Signed-in users can open the demo without signing out.
- The demo menu gains "Exit demo": back to Welcome, or back to the signed-in user's account.

## Architecture

### CareCore (unit-tested)

**`AuthSessionService`** (modified)

```swift
@MainActor public protocol AuthSessionService: AnyObject {
    var state: AuthSessionState { get }
    func restoreSession() async -> AuthSessionState
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(_ code: String, email: String) async throws
    /// Test accounts only; the UI offers it in DEBUG builds.
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}
```

`AuthSessionState` replaces `magicLinkSent(email:)` with `codeSent(email:)`. `sendMagicLink` and `handleOpenURL` are removed. `DemoAuthSessionService` stays.

**`CareAccountService`** (new)

```swift
public struct MemberProfile: Equatable, Sendable { public var displayName: String; public var city: String }

@MainActor public struct CareMembership {
    public let accountID: String
    public let inviteCode: String
    public let role: CareRole
    public let repository: any CareRepository
}

@MainActor public protocol CareAccountService: AnyObject {
    func loadProfile() async throws -> MemberProfile
    func updateProfile(_ profile: MemberProfile) async throws
    func loadMembership() async throws -> CareMembership?   // nil = no family yet
    func createFamily(name: String) async throws
    func joinFamily(inviteCode: String, role: CareRole) async throws
    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws
    func claimSenior(id: String) async throws
    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws
    func stopLiveUpdates() async
}
```

**`OnboardingRouter`** (new, pure)

`nextPhase(profile:membership:signedInProfileID:justCreatedFamily:) -> SessionPhase` decides the next step from server state, so relaunching mid-onboarding resumes at the right screen:

| Input | Phase |
| --- | --- |
| profile `displayName` empty | `needsProfile` |
| no membership | `needsFamily` |
| role `family`, no seniors | `needsSenior` |
| role `family`, family just created in this run, seniors exist | `inviteFamily(code)` |
| role `senior`, no senior with `profileID == signedInProfileID` | `needsSeniorLink(unlinked seniors)` |
| otherwise | `ready` |

**`AppSession`** (new, `@MainActor @Observable`)

- `phase: SessionPhase` — `restoring`, `welcome`, `enterEmail`, `enterCode(email:)`, `needsProfile`, `needsFamily`, `needsSenior`, `inviteFamily(code:)`, `needsSeniorLink([AccountSenior])`, `unreachable`, `ready`, `demo`.
- `activeState: AppState` — the demo `AppState` (owned for the app's lifetime) while in the demo or onboarding; the live `AppState` in `ready`.
- `liveAccountID: String?`, `isBusy: Bool`, `errorMessage: String?`, `canResendCode: Bool`.
- Actions: `start()`, `tryDemo()`, `exitDemo()`, `startSignIn()`, `sendCode(to:)`, `verifyCode(_:)`, `signInWithPassword(email:password:)` (DEBUG UI only), `resendCode()`, `useDifferentEmail()`, `saveProfile(_:)`, `createFamily(name:)`, `joinFamily(inviteCode:role:)`, `addSenior(...)`, `finishInvite()`, `claimSenior(id:)`, `retry()`, `signOut()`.
- Injected: `AuthSessionService?` (nil = Supabase not configured), `CareAccountService?`, `makeHealthProvider: () -> (any HealthDataProvider)?`, `isUITesting: Bool`, `now: () -> Date`.
- Entering `ready` builds `AppState(repository:healthProvider:currentProfileID:now: Date.init)`, marks it production, calls `enterAsMember(role:)` (selecting the linked senior for seniors) and starts live updates, refreshing the live state on change.
- `signOut()` stops live updates, signs out, drops the live state and returns to `welcome`.

**`AppState`** (modified)

- `isProduction: Bool` (init parameter, default `false`).
- `enterAsMember(role:)` sets `role`, `screen` and default tabs for that role.

### App target

- `SupabaseAuthSessionService` — `signInWithOTP(email:shouldCreateUser: true)`, `verifyOTP(email:token:type: .email)`, and the existing `signIn(email:password:)` (only reachable from the DEBUG link).
- `SupabaseCareAccountService` (new) — implements `CareAccountService`: profile read/update on `profiles`, membership (with `role`) from `account_members`, `create_care_account` / `join_care_account` / `claim_senior_profile` RPCs, senior insert, and realtime via `SupabaseCareRepository`. The static create/join helpers move here from `SupabaseCareRepository`.
- `CareCompanionApp` owns one `AppSession` and a `SessionRootView` that switches on `phase`: onboarding screens, the existing `RootView` for `ready` / `demo`.
- RevenueCat identity follows `session.liveAccountID` (logIn with the account ID when live, logOut otherwise).
- Removed: `LiveModeController.swift`, `LiveModeView.swift`, the demo menu's "Live Supabase" entry, and the `onOpenURL` magic-link handler. The `carecompanion://` URL scheme config stays (harmless, reusable later).

### Supabase

No schema change. Existing policies already allow profile self-update and membership reads; `create_care_account`, `join_care_account` and `claim_senior_profile` are in place and SQL-tested.

Dashboard change (human): Authentication → Email Templates → "Magic Link" template must include `{{ .Token }}` so the email carries the code. Documented in `docs/DATABASE.md`.

## Errors and edge cases

| Case | Behaviour |
| --- | --- |
| Invalid email | Inline "Enter a valid email address"; no request sent |
| Wrong or expired code | "That code didn't work. Check the email or send a new one." Code field clears |
| Resend within 60 s | Button disabled with remaining seconds |
| Wrong invite code | "No family found for that code." Entered code kept |
| Network or server error on any step | Inline message and Try again; state unchanged |
| Saved session, server unreachable at launch | `unreachable` phase: Try again, Try the demo |
| Session expired / unauthorized | Back to `welcome` |
| Senior already linked to another login | "<name> is already linked to another phone. Ask your family for help." |
| Joined as senior, no senior added yet | Waiting message with Refresh |
| App quit mid-onboarding | Next launch routes from server state to the first unfinished step (the invite screen is not re-shown) |
| Sign out | Stops realtime, RevenueCat logOut, drops live state, `welcome` |

## Testing

### Unit tests (`swift test`)

- `OnboardingRouter`: one test per routing table row.
- `AppSession` with in-memory fake `AuthSessionService` and `CareAccountService`:
  - not configured → `welcome`; `--ui-testing` → `demo`
  - restored session with complete account → `ready`, live `AppState` has correct role, `currentProfileID`, `isProduction`
  - restored session, server throws offline → `unreachable`; retry succeeds → `ready`
  - invalid email → error, no send; wrong code → error, stays on `enterCode`
  - resend blocked before 60 s, allowed after (injected clock)
  - create family → `needsSenior` → add senior → `inviteFamily` → `finishInvite` → `ready`
  - join with bad code → error, stays on `needsFamily`
  - join as senior → `needsSeniorLink` → claim → `ready` with the linked senior selected
  - `tryDemo` / `exitDemo` while signed in returns to the account
  - `signOut` from `ready` and from mid-onboarding → `welcome`, live updates stopped
- Existing 68 tests and the four demo UI tests keep passing (UI tests launch straight into the demo).

### Simulator runs (Claude drives the iPhone 17 simulator)

1. Demo: Welcome → Try the demo → role choice works; Exit demo returns to Welcome. Demo UI test suite passes.
2. Family: debug password sign-in as the family test account → name → start family → add Maya → invite code shown → Family Dashboard with live data.
3. Senior: sign out → sign in as the senior test account → join with that code as senior → "This is me: Maya" → Senior Home → Health sheet allows sync.
4. Errors: wrong invite code, wrong email code, sign out mid-onboarding, relaunch resumes mid-onboarding.
5. One real email-code sign-in, with the user reading the code from the inbox.

### Prerequisites from the user

- Apply `Supabase/migrations/20260915000003_senior_device_link.sql` to the live project (needed for simulator run 3).
- Family and senior test account emails and passwords, supplied as environment variables for the session, never committed.
- The `{{ .Token }}` email template change (needed for simulator run 5).

## Out of scope

Full Settings screen, editing senior or member profiles, removing members, leaving a family, multiple families per login, Sign in with Apple, onboarding copy localization (the localization slice covers all strings).
