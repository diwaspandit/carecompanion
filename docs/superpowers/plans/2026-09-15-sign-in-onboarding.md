# Sign-in and Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make production mode the normal way into CareCompanion: email-code sign-in, create or join a family, add or link the senior, then land in the app for your role, with the demo one tap away.

**Architecture:** A new `AppSession` coordinator in the CareCore package owns the launch phase and the `AppState` on screen. It talks to `AuthSessionService` (email codes) and a new `CareAccountService`; a pure `OnboardingRouter` picks the next step from server state. Supabase implementations live in `App/Services`, and new SwiftUI screens in `App/Features/Onboarding/` render each phase. `LiveModeController` / `LiveModeView` are removed.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), Observation, XCTest via `swift test`, Supabase Swift SDK 2.x (app target only), RevenueCat.

**Spec:** [docs/superpowers/specs/2026-09-15-sign-in-onboarding-design.md](../specs/2026-09-15-sign-in-onboarding-design.md)

## Global Constraints

- iOS 17 deployment target; Swift 6 language mode in both the package (`swift-tools-version: 6.0`) and app (`SWIFT_VERSION = 6.0`).
- CareCore stays vendor-free: no `import Supabase` / `RevenueCat` / `HealthKit` under `Sources/CareCore`.
- Views never call Supabase, RevenueCat or AI APIs directly (AGENTS.md).
- Demo mode must work without Supabase, network AI or backend availability; `--ui-testing` launches straight into the demo.
- Sign-in method: email one-time code, 6 digits, `signInWithOTP(email:shouldCreateUser: true)` / `verifyOTP(email:token:type: .email)`.
- Resend code enabled 60 seconds after the last send.
- Production role comes from `account_members.role`; production UI never shows "Switch role" or the demo menu.
- Error copy (verbatim):
  - invalid email: `Enter a valid email address`
  - wrong code: `That code didn't work. Check the email or send a new one.`
  - wrong invite: `No family found for that code.`
  - offline: `Can't reach CareCompanion. Check your connection and try again.`
  - senior already linked: `<name> is already linked to another phone. Ask your family for help.`
  - fallback: `Something went wrong. Please try again.`
- Never commit secrets or test-account passwords.

## Commands

```bash
# Unit tests (the Command Line Tools toolchain lacks XCTest)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test

# iOS Simulator build (arm64 only; the x86_64 slice fails to link CareCore)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project CareCompanion.xcodeproj -scheme CareCompanion -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath .build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 build

# Demo UI tests on the booted iPhone 17
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project CareCompanion.xcodeproj -scheme CareCompanion -destination "platform=iOS Simulator,name=iPhone 17" -derivedDataPath .build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 -only-testing:CareCompanionUITests
```

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/CareCore/CareServiceErrors.swift` (modify) | Adds `invalidCode`, `inviteNotFound`, `seniorAlreadyLinked` |
| `Sources/CareCore/AuthSessionService.swift` (modify) | Email-code auth interface; `codeSent` state; demo bypass |
| `Sources/CareCore/CareAccountService.swift` (create) | `MemberProfile`, `CareMembership`, `CareAccountService` interface |
| `Sources/CareCore/OnboardingRouter.swift` (create) | `SessionPhase` and pure `nextPhase` routing |
| `Sources/CareCore/AppState.swift` (modify) | `isProduction`, `enterAsMember(role:)` |
| `Sources/CareCore/AppSession.swift` (create) | Launch/onboarding coordinator |
| `Tests/CareCoreTests/SessionFakes.swift` (create) | In-memory fake auth, account service and repository |
| `Tests/CareCoreTests/OnboardingRouterTests.swift` (create) | Routing table tests |
| `Tests/CareCoreTests/AppSessionTests.swift` (create) | Session behaviour tests |
| `App/Services/SupabaseAuthSessionService.swift` (modify) | Email codes; error mapping for codes and invites |
| `App/Services/SupabaseCareRepository.swift` (modify) | `load(client:accountID:)`; create/join helpers removed |
| `App/Services/SupabaseCareAccountService.swift` (create) | Supabase `CareAccountService` |
| `App/Features/Onboarding/*.swift` (create) | Scaffold + one file per screen + `SessionRootView` |
| `App/CareCompanionApp.swift` (modify) | Owns `AppSession`; production Profile buttons; demo menu "Exit demo" |
| `App/Services/LiveModeController.swift`, `App/Features/LiveModeView.swift` (delete) | Replaced by the real flow |
| `CareCompanion.xcodeproj/project.pbxproj` (modify) | Register new app files, drop deleted ones |

---

### Task 1: Email-code auth interface and typed onboarding errors

**Files:**
- Modify: `Sources/CareCore/CareServiceErrors.swift`
- Modify: `Sources/CareCore/AuthSessionService.swift`
- Modify: `Tests/CareCoreTests/CareRecordsTests.swift:170-179` (`testDemoAuthNeverRequiresNetworkOrSignIn`)
- Modify: `App/Services/SupabaseAuthSessionService.swift`
- Modify: `App/Services/LiveModeController.swift`, `App/Features/LiveModeView.swift`, `App/CareCompanionApp.swift:25` (compile fixes only; both LiveMode files are deleted in Task 8)

**Interfaces:**
- Produces:
  - `CareServiceError.invalidCode`, `.inviteNotFound`, `.seniorAlreadyLinked`
  - `AuthSessionState.codeSent(email: String)` (replaces `magicLinkSent`)
  - `protocol AuthSessionService { var state; restoreSession() async -> AuthSessionState; sendEmailCode(to:) async throws; verifyEmailCode(_:email:) async throws; signIn(email:password:) async throws; signOut() async throws }`

- [ ] **Step 1: Write the failing test**

Replace `testDemoAuthNeverRequiresNetworkOrSignIn` in `Tests/CareCoreTests/CareRecordsTests.swift` and add an error test below it:

```swift
    @MainActor
    func testDemoAuthNeverRequiresNetworkOrSignIn() async throws {
        let auth = DemoAuthSessionService()
        let restored = await auth.restoreSession()
        XCTAssertEqual(restored, .demo)
        try await auth.sendEmailCode(to: "diwas@example.com")
        try await auth.verifyEmailCode("123456", email: "diwas@example.com")
        try await auth.signIn(email: "diwas@example.com", password: "unused")
        XCTAssertEqual(auth.state, .demo)
        try await auth.signOut()
        XCTAssertEqual(auth.state, .demo)
    }

    func testOnboardingErrorsHaveDescriptions() {
        for error in [CareServiceError.invalidCode, .inviteNotFound, .seniorAlreadyLinked] {
            XCTAssertNotNil(error.errorDescription)
        }
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AuthSessionTests`
Expected: compile FAIL — `value of type 'DemoAuthSessionService' has no member 'sendEmailCode'` and `type 'CareServiceError' has no member 'invalidCode'`.

- [ ] **Step 3: Implement in CareCore**

In `Sources/CareCore/CareServiceErrors.swift`, add after `case invalidState(String)`:

```swift
    /// Email sign-in code was wrong or expired
    case invalidCode

    /// No care account matches the invite code
    case inviteNotFound

    /// The senior record is already linked to another login
    case seniorAlreadyLinked
```

and in `errorDescription` add before `case .unknown`:

```swift
        case .invalidCode:
            return "That code didn't work. Check the email or send a new one."
        case .inviteNotFound:
            return "No family found for that code."
        case .seniorAlreadyLinked:
            return "This senior is already linked to another phone."
```

In `Sources/CareCore/AuthSessionService.swift`, replace from `public enum AuthSessionState` through the end of `DemoAuthSessionService` with:

```swift
public enum AuthSessionState: Equatable, Sendable {
    /// Offline demo: no account, no network.
    case demo
    case signedOut
    case codeSent(email: String)
    case signedIn(AuthenticatedUser)
}

@MainActor public protocol AuthSessionService: AnyObject {
    var state: AuthSessionState { get }
    /// Restores a persisted session without prompting the user.
    func restoreSession() async -> AuthSessionState
    /// Emails a one-time sign-in code. Creates the user if the email is new.
    func sendEmailCode(to email: String) async throws
    /// Completes sign-in with the emailed code. Throws `.invalidCode` when it is wrong or expired.
    func verifyEmailCode(_ code: String, email: String) async throws
    /// Test accounts only; the UI offers it in DEBUG builds.
    func signIn(email: String, password: String) async throws
    func signOut() async throws
}

/// Demo-mode bypass: always "signed in" to the local demo, never touches the network.
@MainActor public final class DemoAuthSessionService: AuthSessionService {
    public let state: AuthSessionState = .demo

    public init() {}

    public func restoreSession() async -> AuthSessionState { state }
    public func sendEmailCode(to email: String) async throws {}
    public func verifyEmailCode(_ code: String, email: String) async throws {}
    public func signIn(email: String, password: String) async throws {}
    public func signOut() async throws {}
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS, 69 tests, 0 failures.

- [ ] **Step 5: Update the Supabase auth service**

In `App/Services/SupabaseAuthSessionService.swift`:

1. Replace `sendMagicLink(to:)` with:

```swift
    func sendEmailCode(to email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isValid(email) else {
            throw CareServiceError.invalidState("Enter a valid email address")
        }
        do {
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
            state = .codeSent(email: email)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        do {
            let response = try await client.auth.verifyOTP(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                token: code.trimmingCharacters(in: .whitespacesAndNewlines),
                type: .email)
            guard case .session(let session) = response else { throw CareServiceError.invalidCode }
            state = .signedIn(Self.user(from: session.user))
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
```

2. Delete `handleOpenURL(_:)`, and change the `signIn(email:password:)` doc comment to `/// Test accounts only; the UI offers it in DEBUG builds.`
3. In `SupabaseErrorMapper.map`, replace the `AuthError` line and the `P0002` case:

```swift
        if let authError = error as? AuthError {
            if case .sessionMissing = authError { return .unauthorized }
            if authError.errorCode == .otpExpired || authError.errorCode == .invalidCredentials { return .invalidCode }
            return .vendorUnavailable
        }
```

```swift
            case "P0002": return .inviteNotFound
```

- [ ] **Step 6: Keep the app compiling until Task 8 removes LiveMode**

- `App/Services/LiveModeController.swift`: delete `sendMagicLink(to:)` and `handleOpenURL(_:)`.
- `App/Features/LiveModeView.swift`: delete the `TextField("Email"…)` block's following `Button("Send magic link") { … }` line only (keep the email and password fields and password sign-in).
- `App/CareCompanionApp.swift`: delete the line `.onOpenURL { url in Task { await live.handleOpenURL(url) } }`.

- [ ] **Step 7: Build the app**

Run the iOS Simulator build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Sources/CareCore/CareServiceErrors.swift Sources/CareCore/AuthSessionService.swift Tests/CareCoreTests/CareRecordsTests.swift App/Services/SupabaseAuthSessionService.swift App/Services/LiveModeController.swift App/Features/LiveModeView.swift App/CareCompanionApp.swift
git commit -m "feat: switch auth to email sign-in codes with typed onboarding errors"
```

---
### Task 2: Onboarding model and router

**Files:**
- Create: `Sources/CareCore/CareAccountService.swift`
- Create: `Sources/CareCore/OnboardingRouter.swift`
- Create: `Tests/CareCoreTests/SessionFakes.swift`
- Create: `Tests/CareCoreTests/OnboardingRouterTests.swift`

**Interfaces:**
- Consumes: `CareRepository`, `AccountSenior.profileID`, `CareRole` (existing)
- Produces:
  - `struct MemberProfile: Equatable, Sendable { var displayName: String; var city: String; init(displayName:city:) }`
  - `@MainActor struct CareMembership { let accountID: String; let inviteCode: String; let role: CareRole; let repository: any CareRepository; init(accountID:inviteCode:role:repository:) }`
  - `@MainActor protocol CareAccountService: AnyObject` with `loadProfile() async throws -> MemberProfile`, `updateProfile(_:) async throws`, `loadMembership() async throws -> CareMembership?`, `createFamily(name:) async throws`, `joinFamily(inviteCode:role:) async throws`, `addSenior(name:age:city:timeZoneIdentifier:) async throws`, `claimSenior(id:) async throws`, `startLiveUpdates(onChange:) async throws`, `stopLiveUpdates() async`
  - `enum SessionPhase: Equatable, Sendable` — `restoring, welcome, enterEmail, enterCode(email: String), needsProfile, needsFamily, needsSenior, inviteFamily(code: String), needsSeniorLink([AccountSenior]), unreachable, ready, demo`
  - `enum OnboardingRouter { static func nextPhase(profile: MemberProfile, membership: CareMembership?, signedInProfileID: String, justCreatedFamily: Bool) -> SessionPhase }`
  - Test fakes (test target only): `StubCareRepository(seniors:)`, `FakeAuthSessionService`, `FakeCareAccountService`

- [ ] **Step 1: Write the test fakes**

Create `Tests/CareCoreTests/SessionFakes.swift`:

```swift
import Foundation
@testable import CareCore

/// Repository whose snapshot is the demo seed with a chosen senior list. Writes are no-ops.
@MainActor final class StubCareRepository: CareRepository {
    var snapshot: CareSnapshot

    init(seniors: [AccountSenior]) {
        var seed = DemoCareRepository().snapshot
        seed.seniors = seniors
        snapshot = seed
    }

    func refresh() async throws {}
    func checkIn(seniorID: String, at date: Date) async throws {}
    func recordMood(_ mood: Mood, seniorID: String, at date: Date) async throws {}
    func toggleMedication(id: String) async throws {}
    func recordMedicationEvent(medicationID: String, taken: Bool, at date: Date) async throws {}
    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) async throws {}
    func saveAppointment(_ appointment: Appointment) async throws {}
    func deleteAppointment(id: String) async throws {}
    func triggerSOS(seniorID: String, at date: Date) async throws {}
    func acknowledgeAlerts(seniorID: String) async throws {}
    func saveCareInsight(_ insight: CareInsight, seniorID: String) async throws {}
    func saveAppointmentPrep(_ prep: AppointmentPrep, appointmentID: String) async throws {}
    func addSenior(_ senior: AccountSenior) async throws { snapshot.seniors.append(senior) }
    func updateSenior(_ senior: AccountSenior) async throws {}
    func reset() async {}
}

enum Fixture {
    static let accountID = "account-1"
    static let diwasID = "profile-diwas"
    static let mayaID = "profile-maya"

    static func maya(linkedTo profileID: String? = nil) -> AccountSenior {
        AccountSenior(id: "senior-maya", accountID: accountID, name: "Maya Sharma", age: 74,
                      city: "Kathmandu, Nepal", timeZoneIdentifier: "Asia/Kathmandu", profileID: profileID)
    }

    @MainActor static func membership(role: CareRole, seniors: [AccountSenior]) -> CareMembership {
        CareMembership(accountID: accountID, inviteCode: "ABCD1234", role: role,
                       repository: StubCareRepository(seniors: seniors))
    }
}

@MainActor final class FakeAuthSessionService: AuthSessionService {
    var state: AuthSessionState
    var validCode = "123456"
    var profileIDOnSignIn = Fixture.diwasID
    var sendError: CareServiceError?
    private(set) var sentCodes: [String] = []
    private(set) var signOutCount = 0

    init(state: AuthSessionState = .signedOut) { self.state = state }

    func restoreSession() async -> AuthSessionState { state }

    func sendEmailCode(to email: String) async throws {
        if let sendError { throw sendError }
        sentCodes.append(email)
        state = .codeSent(email: email)
    }

    func verifyEmailCode(_ code: String, email: String) async throws {
        guard code == validCode else { throw CareServiceError.invalidCode }
        state = .signedIn(AuthenticatedUser(id: profileIDOnSignIn, email: email))
    }

    func signIn(email: String, password: String) async throws {
        state = .signedIn(AuthenticatedUser(id: profileIDOnSignIn, email: email))
    }

    func signOut() async throws {
        signOutCount += 1
        state = .signedOut
    }
}

/// In-memory family backend. Server-side rules that matter to routing are mirrored here.
@MainActor final class FakeCareAccountService: CareAccountService {
    var profile = MemberProfile(displayName: "", city: "")
    var role: CareRole?
    var seniors: [AccountSenior] = []
    var signedInProfileID = Fixture.diwasID
    var validInviteCode = "ABCD1234"
    /// Thrown by the next call to any method, then cleared.
    var nextError: CareServiceError?
    private(set) var liveUpdatesRunning = false

    private func failIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func loadProfile() async throws -> MemberProfile {
        try failIfNeeded()
        return profile
    }

    func updateProfile(_ profile: MemberProfile) async throws {
        try failIfNeeded()
        self.profile = profile
    }

    func loadMembership() async throws -> CareMembership? {
        try failIfNeeded()
        guard let role else { return nil }
        return Fixture.membership(role: role, seniors: seniors)
    }

    func createFamily(name: String) async throws {
        try failIfNeeded()
        role = .family
    }

    func joinFamily(inviteCode: String, role: CareRole) async throws {
        try failIfNeeded()
        guard inviteCode == validInviteCode else { throw CareServiceError.inviteNotFound }
        self.role = role
    }

    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws {
        try failIfNeeded()
        seniors.append(AccountSenior(id: "senior-\(seniors.count + 1)", accountID: Fixture.accountID, name: name,
                                     age: age, city: city, timeZoneIdentifier: timeZoneIdentifier))
    }

    func claimSenior(id: String) async throws {
        try failIfNeeded()
        guard role == .senior else { throw CareServiceError.unauthorized }
        guard let index = seniors.firstIndex(where: { $0.id == id }) else { throw CareServiceError.invalidState("Senior not found") }
        if let owner = seniors[index].profileID, owner != signedInProfileID { throw CareServiceError.seniorAlreadyLinked }
        seniors[index].profileID = signedInProfileID
    }

    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws {
        try failIfNeeded()
        liveUpdatesRunning = true
    }

    func stopLiveUpdates() async { liveUpdatesRunning = false }
}
```

- [ ] **Step 2: Write the failing router tests**

Create `Tests/CareCoreTests/OnboardingRouterTests.swift`:

```swift
import XCTest
@testable import CareCore

@MainActor final class OnboardingRouterTests: XCTestCase {
    private let named = MemberProfile(displayName: "Diwas", city: "Austin")

    private func route(profile: MemberProfile? = nil, membership: CareMembership?, as profileID: String = Fixture.diwasID,
                       justCreated: Bool = false) -> SessionPhase {
        OnboardingRouter.nextPhase(profile: profile ?? named, membership: membership,
                                   signedInProfileID: profileID, justCreatedFamily: justCreated)
    }

    func testMissingNameNeedsProfileFirst() {
        let blank = MemberProfile(displayName: "  ", city: "")
        XCTAssertEqual(route(profile: blank, membership: Fixture.membership(role: .family, seniors: [Fixture.maya()])), .needsProfile)
    }

    func testNoMembershipNeedsFamily() {
        XCTAssertEqual(route(membership: nil), .needsFamily)
    }

    func testFamilyWithoutSeniorNeedsSenior() {
        XCTAssertEqual(route(membership: Fixture.membership(role: .family, seniors: [])), .needsSenior)
    }

    func testJustCreatedFamilyWithSeniorShowsInvite() {
        XCTAssertEqual(route(membership: Fixture.membership(role: .family, seniors: [Fixture.maya()]), justCreated: true),
                       .inviteFamily(code: "ABCD1234"))
    }

    func testReturningFamilyIsReady() {
        XCTAssertEqual(route(membership: Fixture.membership(role: .family, seniors: [Fixture.maya()])), .ready)
    }

    func testSeniorWithoutLinkChoosesAmongUnlinkedSeniors() {
        let ramesh = AccountSenior(id: "senior-ramesh", accountID: Fixture.accountID, name: "Ramesh", age: 78,
                                   city: "", timeZoneIdentifier: "UTC", profileID: "profile-other")
        let phase = route(membership: Fixture.membership(role: .senior, seniors: [Fixture.maya(), ramesh]), as: Fixture.mayaID)
        XCTAssertEqual(phase, .needsSeniorLink([Fixture.maya()]))
    }

    func testSeniorBeforeFamilyAddsThemWaitsWithEmptyList() {
        XCTAssertEqual(route(membership: Fixture.membership(role: .senior, seniors: []), as: Fixture.mayaID), .needsSeniorLink([]))
    }

    func testLinkedSeniorIsReady() {
        let phase = route(membership: Fixture.membership(role: .senior, seniors: [Fixture.maya(linkedTo: Fixture.mayaID)]),
                          as: Fixture.mayaID)
        XCTAssertEqual(phase, .ready)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter OnboardingRouterTests`
Expected: compile FAIL — `cannot find type 'CareAccountService'` / `cannot find 'OnboardingRouter' in scope`.

- [ ] **Step 4: Implement the model**

Create `Sources/CareCore/CareAccountService.swift`:

```swift
import Foundation

/// The signed-in person's own profile (shown as "Diwas · Austin" on the dashboard).
public struct MemberProfile: Equatable, Sendable {
    public var displayName: String
    public var city: String

    public init(displayName: String, city: String) {
        self.displayName = displayName
        self.city = city
    }
}

/// The signed-in person's place in a family account.
@MainActor public struct CareMembership {
    public let accountID: String
    public let inviteCode: String
    public let role: CareRole
    public let repository: any CareRepository

    public init(accountID: String, inviteCode: String, role: CareRole, repository: any CareRepository) {
        self.accountID = accountID
        self.inviteCode = inviteCode
        self.role = role
        self.repository = repository
    }
}

/// Account setup for the signed-in user. Production: Supabase. Tests: in-memory fake.
@MainActor public protocol CareAccountService: AnyObject {
    func loadProfile() async throws -> MemberProfile
    func updateProfile(_ profile: MemberProfile) async throws
    /// nil when the user has not created or joined a family yet.
    func loadMembership() async throws -> CareMembership?
    /// Creates a family account with the signed-in user as a `family` member.
    func createFamily(name: String) async throws
    /// Throws `.inviteNotFound` for an unknown code.
    func joinFamily(inviteCode: String, role: CareRole) async throws
    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws
    /// Links the signed-in senior member to a senior record. Throws `.seniorAlreadyLinked` or `.unauthorized`.
    func claimSenior(id: String) async throws
    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws
    func stopLiveUpdates() async
}
```

Create `Sources/CareCore/OnboardingRouter.swift`:

```swift
import Foundation

/// Where the app is between launch and the care screens.
public enum SessionPhase: Equatable, Sendable {
    case restoring
    case welcome
    case enterEmail
    case enterCode(email: String)
    case needsProfile
    case needsFamily
    case needsSenior
    case inviteFamily(code: String)
    /// Senior member choosing which senior record is them; empty until the family adds one.
    case needsSeniorLink([AccountSenior])
    case unreachable
    case ready
    case demo
}

/// Picks the next onboarding step from server state, so relaunching mid-setup resumes correctly.
public enum OnboardingRouter {
    @MainActor
    public static func nextPhase(profile: MemberProfile, membership: CareMembership?,
                                 signedInProfileID: String, justCreatedFamily: Bool) -> SessionPhase {
        guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .needsProfile }
        guard let membership else { return .needsFamily }
        let seniors = membership.repository.snapshot.seniors
        switch membership.role {
        case .family:
            if seniors.isEmpty { return .needsSenior }
            if justCreatedFamily { return .inviteFamily(code: membership.inviteCode) }
            return .ready
        case .senior:
            if seniors.contains(where: { $0.profileID == signedInProfileID }) { return .ready }
            return .needsSeniorLink(seniors.filter { $0.profileID == nil })
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS, 77 tests, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/CareCore/CareAccountService.swift Sources/CareCore/OnboardingRouter.swift Tests/CareCoreTests/SessionFakes.swift Tests/CareCoreTests/OnboardingRouterTests.swift
git commit -m "feat: add care account service interface and onboarding router"
```

---

### Task 3: Production flag and role entry on AppState

**Files:**
- Modify: `Sources/CareCore/AppState.swift`
- Test: `Tests/CareCoreTests/AppSessionTests.swift` (create; later tasks add to it)

**Interfaces:**
- Produces: `AppState.init(repository:healthProvider:currentProfileID:isProduction:now:)` (`isProduction` defaults to `false`), `public let isProduction: Bool`, `public func enterAsMember(role: CareRole)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CareCoreTests/AppSessionTests.swift`:

```swift
import XCTest
@testable import CareCore

@MainActor final class AppStateProductionTests: XCTestCase {
    func testDemoStateIsNotProduction() {
        XCTAssertFalse(AppState(repository: DemoCareRepository()).isProduction)
    }

    func testFamilyMemberEntersDashboard() {
        let state = AppState(repository: DemoCareRepository(), isProduction: true)
        state.enterAsMember(role: .family)
        XCTAssertEqual(state.role, .family)
        XCTAssertEqual(state.screen, .familyDashboard)
        XCTAssertEqual(state.familyTab, .dashboard)
    }

    func testSeniorMemberEntersSeniorHome() {
        let state = AppState(repository: DemoCareRepository(), isProduction: true)
        state.seniorTab = .profile
        state.enterAsMember(role: .senior)
        XCTAssertEqual(state.role, .senior)
        XCTAssertEqual(state.screen, .seniorHome)
        XCTAssertEqual(state.seniorTab, .home)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppStateProductionTests`
Expected: compile FAIL — `extra argument 'isProduction' in call`.

- [ ] **Step 3: Implement**

In `Sources/CareCore/AppState.swift`:

After `public let currentProfileID: String?` add:

```swift
    /// Real account data. Production hides demo-only controls (role switching, demo menu).
    public let isProduction: Bool
```

Change the initializer signature and body start to:

```swift
    public init(
        repository: any CareRepository,
        healthProvider: (any HealthDataProvider)? = nil,
        currentProfileID: String? = nil,
        isProduction: Bool = false,
        now: @escaping () -> Date = { DemoCareRepository.referenceDate }
    ) {
        self.repository = repository
        self.healthProvider = healthProvider
        self.currentProfileID = currentProfileID
        self.isProduction = isProduction
```

After `chooseRole(_:)` add:

```swift
    /// Production entry: the role comes from the account membership, not a role-choice screen.
    public func enterAsMember(role: CareRole) {
        chooseRole(role)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS, 80 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/CareCore/AppState.swift Tests/CareCoreTests/AppSessionTests.swift
git commit -m "feat: mark production app state and enter by membership role"
```

---
### Task 4: AppSession launch, demo and sign-in

**Files:**
- Create: `Sources/CareCore/AppSession.swift`
- Modify: `Tests/CareCoreTests/AppSessionTests.swift` (append)

**Interfaces:**
- Consumes: Task 1 `AuthSessionService`, `CareServiceError` cases; Task 2 `CareAccountService`, `CareMembership`, `SessionPhase`, `OnboardingRouter`, fakes; Task 3 `AppState(…isProduction:…)`, `enterAsMember(role:)`
- Produces (`@MainActor @Observable public final class AppSession`):
  - `init(auth: (any AuthSessionService)?, accounts: (any CareAccountService)?, demoState: AppState, makeHealthProvider: @escaping () -> (any HealthDataProvider)? = { nil }, isUITesting: Bool = false, now: @escaping () -> Date = Date.init)`
  - `phase: SessionPhase`, `activeState: AppState`, `isBusy: Bool`, `errorMessage: String?`, `isSignInAvailable: Bool`, `isSignedIn: Bool`, `liveAccountID: String?`, `secondsUntilResend() -> Int`, `static let resendDelay: TimeInterval = 60`
  - `start()`, `retry()`, `tryDemo()`, `exitDemo()`, `startSignIn()`, `sendCode(to:)`, `verifyCode(_:)`, `signInWithPassword(email:password:)`, `resendCode()`, `useDifferentEmail()`, `signOut()` — all `async` except `tryDemo`, `startSignIn`, `useDifferentEmail`
  - Internal helpers Task 5 uses (same file): `route()`, `runStep(_:onError:)`, `static func message(for:) -> String`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CareCoreTests/AppSessionTests.swift`:

```swift
@MainActor final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000)
}

@MainActor final class AppSessionLaunchTests: XCTestCase {
    private let clock = TestClock()

    private func session(auth: FakeAuthSessionService? = FakeAuthSessionService(),
                         accounts: FakeCareAccountService? = FakeCareAccountService(),
                         isUITesting: Bool = false) -> AppSession {
        AppSession(auth: auth, accounts: accounts, demoState: AppState(repository: DemoCareRepository()),
                   isUITesting: isUITesting, now: { [clock] in clock.now })
    }

    private func completeFamily() -> (FakeAuthSessionService, FakeCareAccountService) {
        let auth = FakeAuthSessionService(state: .signedIn(AuthenticatedUser(id: Fixture.diwasID, email: "diwas@example.com")))
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Diwas", city: "Austin")
        accounts.role = .family
        accounts.seniors = [Fixture.maya()]
        return (auth, accounts)
    }

    func testUITestingStartsInDemo() async {
        let session = session(isUITesting: true)
        await session.start()
        XCTAssertEqual(session.phase, .demo)
        XCTAssertFalse(session.activeState.isProduction)
    }

    func testWithoutSupabaseStartsAtWelcomeWithoutSignIn() async {
        let session = session(auth: nil, accounts: nil)
        await session.start()
        XCTAssertEqual(session.phase, .welcome)
        XCTAssertFalse(session.isSignInAvailable)
    }

    func testNoSavedSessionShowsWelcome() async {
        let session = session()
        await session.start()
        XCTAssertEqual(session.phase, .welcome)
        XCTAssertTrue(session.isSignInAvailable)
    }

    func testRestoredCompleteFamilyIsReadyWithProductionState() async {
        let (auth, accounts) = completeFamily()
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.activeState.isProduction)
        XCTAssertEqual(session.activeState.role, .family)
        XCTAssertEqual(session.activeState.screen, .familyDashboard)
        XCTAssertEqual(session.activeState.currentProfileID, Fixture.diwasID)
        XCTAssertEqual(session.liveAccountID, Fixture.accountID)
        XCTAssertTrue(accounts.liveUpdatesRunning)
    }

    func testRestoredSeniorSelectsTheirLinkedSenior() async {
        let auth = FakeAuthSessionService(state: .signedIn(AuthenticatedUser(id: Fixture.mayaID, email: nil)))
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Maya", city: "")
        accounts.role = .senior
        let ramesh = AccountSenior(id: "senior-ramesh", accountID: Fixture.accountID, name: "Ramesh", age: 78,
                                   city: "", timeZoneIdentifier: "UTC")
        accounts.seniors = [ramesh, Fixture.maya(linkedTo: Fixture.mayaID)]
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.activeState.selectedSeniorID, "senior-maya")
        XCTAssertEqual(session.activeState.screen, .seniorHome)
    }

    func testRestoreWhileOfflineShowsUnreachableThenRetrySucceeds() async {
        let (auth, accounts) = completeFamily()
        accounts.nextError = .offline
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        XCTAssertEqual(session.phase, .unreachable)
        await session.retry()
        XCTAssertEqual(session.phase, .ready)
    }

    func testExpiredSessionReturnsToWelcome() async {
        let (auth, accounts) = completeFamily()
        accounts.nextError = .unauthorized
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        XCTAssertEqual(session.phase, .welcome)
        XCTAssertEqual(auth.signOutCount, 1)
    }

    func testInvalidEmailIsRejectedWithoutSending() async {
        let auth = FakeAuthSessionService()
        let session = session(auth: auth)
        await session.start()
        session.startSignIn()
        await session.sendCode(to: "not-an-email")
        XCTAssertEqual(session.phase, .enterEmail)
        XCTAssertEqual(session.errorMessage, "Enter a valid email address")
        XCTAssertTrue(auth.sentCodes.isEmpty)
    }

    func testWrongCodeStaysOnCodeEntry() async {
        let session = session()
        await session.start()
        session.startSignIn()
        await session.sendCode(to: " diwas@example.com ")
        XCTAssertEqual(session.phase, .enterCode(email: "diwas@example.com"))
        await session.verifyCode("000000")
        XCTAssertEqual(session.phase, .enterCode(email: "diwas@example.com"))
        XCTAssertEqual(session.errorMessage, "That code didn't work. Check the email or send a new one.")
    }

    func testResendWaitsSixtySeconds() async {
        let auth = FakeAuthSessionService()
        let session = session(auth: auth)
        await session.start()
        session.startSignIn()
        await session.sendCode(to: "diwas@example.com")
        XCTAssertEqual(session.secondsUntilResend(), 60)
        await session.resendCode()
        XCTAssertEqual(auth.sentCodes.count, 1)
        clock.now += 60
        XCTAssertEqual(session.secondsUntilResend(), 0)
        await session.resendCode()
        XCTAssertEqual(auth.sentCodes.count, 2)
    }

    func testCorrectCodeForNewUserAsksForName() async {
        let session = session()
        await session.start()
        session.startSignIn()
        await session.sendCode(to: "diwas@example.com")
        await session.verifyCode("123456")
        XCTAssertEqual(session.phase, .needsProfile)
        XCTAssertTrue(session.isSignedIn)
    }

    func testDemoWhileSignedInReturnsToAccount() async {
        let (auth, accounts) = completeFamily()
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        session.tryDemo()
        XCTAssertEqual(session.phase, .demo)
        XCTAssertFalse(session.activeState.isProduction)
        XCTAssertNil(session.liveAccountID)
        await session.exitDemo()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertTrue(session.activeState.isProduction)
    }

    func testSignOutFromReadyResetsEverything() async {
        let (auth, accounts) = completeFamily()
        let session = session(auth: auth, accounts: accounts)
        await session.start()
        await session.signOut()
        XCTAssertEqual(session.phase, .welcome)
        XCTAssertEqual(auth.signOutCount, 1)
        XCTAssertFalse(accounts.liveUpdatesRunning)
        XCTAssertFalse(session.activeState.isProduction)
        XCTAssertFalse(session.isSignedIn)
        XCTAssertNil(session.liveAccountID)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppSessionLaunchTests`
Expected: compile FAIL — `cannot find 'AppSession' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/CareCore/AppSession.swift`:

```swift
import Foundation
import Observation

/// Owns launch and onboarding: restores the session, walks a new user through setup, and holds
/// the AppState on screen (the demo one, or the live one once the account is ready).
@MainActor @Observable public final class AppSession {
    public static let resendDelay: TimeInterval = 60
    static let invalidEmailMessage = "Enter a valid email address"
    static let fallbackMessage = "Something went wrong. Please try again."

    public private(set) var phase: SessionPhase = .restoring
    public private(set) var activeState: AppState
    public private(set) var isBusy = false
    public var errorMessage: String?

    private var membership: CareMembership?
    private var liveState: AppState?
    private var signedInProfileID: String?
    private var lastCodeSentAt: Date?
    private var justCreatedFamily = false
    private var phaseBeforeDemo: SessionPhase?

    @ObservationIgnored private let auth: (any AuthSessionService)?
    @ObservationIgnored private let accounts: (any CareAccountService)?
    @ObservationIgnored private let demoState: AppState
    @ObservationIgnored private let makeHealthProvider: () -> (any HealthDataProvider)?
    @ObservationIgnored private let isUITesting: Bool
    @ObservationIgnored private let now: () -> Date

    public init(
        auth: (any AuthSessionService)?,
        accounts: (any CareAccountService)?,
        demoState: AppState,
        makeHealthProvider: @escaping () -> (any HealthDataProvider)? = { nil },
        isUITesting: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.accounts = accounts
        self.demoState = demoState
        self.makeHealthProvider = makeHealthProvider
        self.isUITesting = isUITesting
        self.now = now
        activeState = demoState
    }

    /// False on a build without Supabase secrets: only the demo is offered.
    public var isSignInAvailable: Bool { auth != nil && accounts != nil }
    public var isSignedIn: Bool { signedInProfileID != nil }
    /// The family account whose data is on screen; nil in the demo and during onboarding.
    public var liveAccountID: String? { phase == .ready ? membership?.accountID : nil }

    public func secondsUntilResend() -> Int {
        guard let lastCodeSentAt else { return 0 }
        return max(0, Int((Self.resendDelay - now().timeIntervalSince(lastCodeSentAt)).rounded(.up)))
    }

    // MARK: - Launch

    public func start() async {
        if isUITesting {
            activeState = demoState
            phase = .demo
            return
        }
        guard let auth, isSignInAvailable else {
            phase = .welcome
            return
        }
        phase = .restoring
        if case .signedIn(let user) = await auth.restoreSession() {
            signedInProfileID = user.id
            await route()
        } else {
            phase = .welcome
        }
    }

    public func retry() async {
        await route()
    }

    // MARK: - Demo

    public func tryDemo() {
        if phase != .demo { phaseBeforeDemo = phase }
        errorMessage = nil
        activeState = demoState
        phase = .demo
    }

    /// Back to where the user was (their account if signed in), with the demo reset for next time.
    public func exitDemo() async {
        await demoState.resetDemo()
        let previous = phaseBeforeDemo ?? .welcome
        phaseBeforeDemo = nil
        if previous == .ready, let liveState {
            activeState = liveState
            phase = .ready
        } else {
            activeState = demoState
            phase = [.demo, .restoring, .ready].contains(previous) ? .welcome : previous
        }
    }

    // MARK: - Sign-in

    public func startSignIn() {
        errorMessage = nil
        phase = .enterEmail
    }

    public func useDifferentEmail() {
        startSignIn()
    }

    public func sendCode(to rawEmail: String) async {
        guard let auth else { return }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailAddress.isValid(email) else {
            errorMessage = Self.invalidEmailMessage
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await auth.sendEmailCode(to: email)
            lastCodeSentAt = now()
            phase = .enterCode(email: email)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    public func resendCode() async {
        guard case .enterCode(let email) = phase, secondsUntilResend() == 0 else { return }
        await sendCode(to: email)
    }

    public func verifyCode(_ code: String) async {
        guard let auth, case .enterCode(let email) = phase else { return }
        await signIn { try await auth.verifyEmailCode(code, email: email) }
    }

    /// Test accounts only; offered in DEBUG builds.
    public func signInWithPassword(email: String, password: String) async {
        guard let auth else { return }
        await signIn { try await auth.signIn(email: email, password: password) }
    }

    private func signIn(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
            return
        }
        isBusy = false
        guard case .signedIn(let user) = auth?.state else {
            errorMessage = Self.fallbackMessage
            return
        }
        signedInProfileID = user.id
        await route()
    }

    public func signOut() async {
        await accounts?.stopLiveUpdates()
        try? await auth?.signOut()
        membership = nil
        liveState = nil
        signedInProfileID = nil
        lastCodeSentAt = nil
        justCreatedFamily = false
        phaseBeforeDemo = nil
        errorMessage = nil
        isBusy = false
        activeState = demoState
        phase = .welcome
    }

    // MARK: - Routing

    /// Reloads profile and membership from the server and moves to the next unfinished step.
    func route() async {
        guard let accounts, let signedInProfileID else {
            phase = .welcome
            return
        }
        isBusy = true
        errorMessage = nil
        do {
            let profile = try await accounts.loadProfile()
            let membership = try await accounts.loadMembership()
            self.membership = membership
            let next = OnboardingRouter.nextPhase(profile: profile, membership: membership,
                                                  signedInProfileID: signedInProfileID,
                                                  justCreatedFamily: justCreatedFamily)
            isBusy = false
            if next == .ready, let membership {
                await enterReady(membership)
            } else {
                phase = next
            }
        } catch CareServiceError.unauthorized {
            await signOut()
        } catch {
            isBusy = false
            if phase == .restoring || phase == .unreachable {
                phase = .unreachable
            } else {
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Runs one onboarding write, then routes onward. On failure the phase stays put with a message.
    func runStep(_ work: (any CareAccountService) async throws -> Void,
                 onError: (Error) -> String = { AppSession.message(for: $0) }) async {
        guard let accounts else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await work(accounts)
        } catch {
            isBusy = false
            errorMessage = onError(error)
            return
        }
        isBusy = false
        await route()
    }

    private func enterReady(_ membership: CareMembership) async {
        let state = AppState(repository: membership.repository, healthProvider: makeHealthProvider(),
                             currentProfileID: signedInProfileID, isProduction: true, now: Date.init)
        if membership.role == .senior,
           let linked = state.snapshot.seniors.first(where: { $0.profileID == signedInProfileID }) {
            state.selectSenior(id: linked.id)
        }
        state.enterAsMember(role: membership.role)
        liveState = state
        activeState = state
        phase = .ready
        do {
            try await accounts?.startLiveUpdates { [weak state] in await state?.refresh() }
        } catch {
            state.showDemoToast("Live updates are paused. Changes appear when you reopen the app.")
        }
    }

    static func message(for error: Error) -> String {
        switch error as? CareServiceError {
        case .invalidCode: "That code didn't work. Check the email or send a new one."
        case .inviteNotFound: "No family found for that code."
        case .offline: "Can't reach CareCompanion. Check your connection and try again."
        case .invalidState(let message) where message == invalidEmailMessage: invalidEmailMessage
        default: fallbackMessage
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS, 93 tests, 0 failures. If Swift 6 reports a sendability error on `now` closures in the test helper, keep the `[clock]` capture list and mark `TestClock` `@MainActor` as written; do not add `@unchecked Sendable`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CareCore/AppSession.swift Tests/CareCoreTests/AppSessionTests.swift
git commit -m "feat: add AppSession for launch, demo and email-code sign-in"
```

---
### Task 5: AppSession onboarding steps

**Files:**
- Modify: `Sources/CareCore/AppSession.swift` (append an extension)
- Modify: `Tests/CareCoreTests/AppSessionTests.swift` (append)

**Interfaces:**
- Consumes: Task 4 `route()`, `runStep(_:onError:)`, `message(for:)`, `errorMessage`
- Produces (all `async` on `AppSession`): `saveProfile(displayName:city:)`, `createFamily(name:)`, `joinFamily(inviteCode:role:)`, `addSenior(name:age:city:timeZoneIdentifier:)`, `finishInvite()`, `claimSenior(id:)`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/CareCoreTests/AppSessionTests.swift`:

```swift
@MainActor final class AppSessionOnboardingTests: XCTestCase {
    private func signedInSession(as profileID: String, accounts: FakeCareAccountService) -> AppSession {
        accounts.signedInProfileID = profileID
        let auth = FakeAuthSessionService(state: .signedIn(AuthenticatedUser(id: profileID, email: nil)))
        return AppSession(auth: auth, accounts: accounts, demoState: AppState(repository: DemoCareRepository()))
    }

    func testNewFamilyReachesReadyThroughInvite() async {
        let accounts = FakeCareAccountService()
        let session = signedInSession(as: Fixture.diwasID, accounts: accounts)
        await session.start()
        XCTAssertEqual(session.phase, .needsProfile)
        await session.saveProfile(displayName: " Diwas ", city: "Austin")
        XCTAssertEqual(accounts.profile, MemberProfile(displayName: "Diwas", city: "Austin"))
        XCTAssertEqual(session.phase, .needsFamily)
        await session.createFamily(name: "Sharma family")
        XCTAssertEqual(session.phase, .needsSenior)
        await session.addSenior(name: "Maya Sharma", age: 74, city: "Kathmandu", timeZoneIdentifier: "Asia/Kathmandu")
        XCTAssertEqual(session.phase, .inviteFamily(code: "ABCD1234"))
        await session.finishInvite()
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.activeState.role, .family)
    }

    func testBlankNamesAreRejectedLocally() async {
        let accounts = FakeCareAccountService()
        let session = signedInSession(as: Fixture.diwasID, accounts: accounts)
        await session.start()
        await session.saveProfile(displayName: "   ", city: "")
        XCTAssertEqual(session.errorMessage, "Enter your name")
        XCTAssertEqual(session.phase, .needsProfile)
    }

    func testWrongInviteCodeKeepsFamilyStep() async {
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Sunita", city: "")
        let session = signedInSession(as: "profile-sunita", accounts: accounts)
        await session.start()
        await session.joinFamily(inviteCode: "WRONG", role: .family)
        XCTAssertEqual(session.phase, .needsFamily)
        XCTAssertEqual(session.errorMessage, "No family found for that code.")
    }

    func testSeniorJoinsLinksAndLandsOnSeniorHome() async {
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Maya", city: "")
        accounts.seniors = [Fixture.maya()]
        let session = signedInSession(as: Fixture.mayaID, accounts: accounts)
        await session.start()
        await session.joinFamily(inviteCode: " abcd1234 ", role: .senior)
        XCTAssertEqual(session.phase, .needsSeniorLink([Fixture.maya()]))
        await session.claimSenior(id: "senior-maya")
        XCTAssertEqual(session.phase, .ready)
        XCTAssertEqual(session.activeState.selectedSenior?.profileID, Fixture.mayaID)
        XCTAssertEqual(session.activeState.screen, .seniorHome)
    }

    func testClaimingSeniorLinkedElsewhereNamesThem() async {
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Maya", city: "")
        accounts.role = .senior
        accounts.seniors = [Fixture.maya()]
        let session = signedInSession(as: Fixture.mayaID, accounts: accounts)
        await session.start()
        accounts.seniors[0].profileID = "profile-other"
        await session.claimSenior(id: "senior-maya")
        XCTAssertEqual(session.errorMessage, "Maya Sharma is already linked to another phone. Ask your family for help.")
        XCTAssertEqual(session.phase, .needsSeniorLink([Fixture.maya()]))
    }

    func testOfflineStepShowsMessageAndStays() async {
        let accounts = FakeCareAccountService()
        accounts.profile = MemberProfile(displayName: "Diwas", city: "")
        let session = signedInSession(as: Fixture.diwasID, accounts: accounts)
        await session.start()
        accounts.nextError = .offline
        await session.createFamily(name: "Sharma family")
        XCTAssertEqual(session.phase, .needsFamily)
        XCTAssertEqual(session.errorMessage, "Can't reach CareCompanion. Check your connection and try again.")
    }

    func testSignOutMidOnboardingReturnsToWelcome() async {
        let accounts = FakeCareAccountService()
        let session = signedInSession(as: Fixture.diwasID, accounts: accounts)
        await session.start()
        await session.signOut()
        XCTAssertEqual(session.phase, .welcome)
        XCTAssertFalse(session.isSignedIn)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppSessionOnboardingTests`
Expected: compile FAIL — `value of type 'AppSession' has no member 'saveProfile'`.

- [ ] **Step 3: Implement**

Append to `Sources/CareCore/AppSession.swift`:

```swift
// MARK: - Onboarding steps

extension AppSession {
    public func saveProfile(displayName: String, city: String) async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter your name"
            return
        }
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        await runStep { try await $0.updateProfile(MemberProfile(displayName: name, city: city)) }
    }

    public func createFamily(name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter a family name"
            return
        }
        await runStep { accounts in
            try await accounts.createFamily(name: name)
            self.markFamilyCreated()
        }
    }

    public func joinFamily(inviteCode: String, role: CareRole) async {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            errorMessage = "Enter the invite code"
            return
        }
        await runStep { try await $0.joinFamily(inviteCode: code, role: role) }
    }

    public func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Enter their name"
            return
        }
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        await runStep { try await $0.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZoneIdentifier) }
    }

    public func finishInvite() async {
        clearFamilyCreated()
        await route()
    }

    public func claimSenior(id: String) async {
        var name = "This senior"
        if case .needsSeniorLink(let seniors) = phase, let senior = seniors.first(where: { $0.id == id }) {
            name = senior.name
        }
        await runStep({ try await $0.claimSenior(id: id) }, onError: { error in
            switch error as? CareServiceError {
            case .seniorAlreadyLinked: "\(name) is already linked to another phone. Ask your family for help."
            case .unauthorized: "Only someone who joined as the senior can do this."
            default: AppSession.message(for: error)
            }
        })
    }
}
```

In the class body (Task 4 file), add these two methods under `// MARK: - Routing`, because `justCreatedFamily` is `private`:

```swift
    func markFamilyCreated() { justCreatedFamily = true }
    func clearFamilyCreated() { justCreatedFamily = false }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: PASS, 100 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/CareCore/AppSession.swift Tests/CareCoreTests/AppSessionTests.swift
git commit -m "feat: add onboarding steps to AppSession"
```

---
### Task 6: Supabase account service

**Files:**
- Create: `App/Services/SupabaseCareAccountService.swift`
- Modify: `App/Services/SupabaseCareRepository.swift:30-67` (`load`, `createAccount`, `joinAccount`), `MembershipRow` near the write payloads
- Modify: `App/Services/LiveModeController.swift` (compile fix until Task 8 deletes it)
- Modify: `CareCompanion.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 2 `CareAccountService`, `MemberProfile`, `CareMembership`; Task 1 error cases; existing `SupabaseCareRepository.startRealtime(onChange:)`, `stopRealtime()`, `addSenior(_:)`, `claimSeniorProfile(seniorID:)`, `inviteCode`, `accountID`
- Produces: `@MainActor final class SupabaseCareAccountService: CareAccountService` with `init(client: SupabaseClient)`; `SupabaseCareRepository.load(client:accountID:now:)`

There is no unit-test target for the app, so this task is verified by building and by the simulator runs in Task 9. Server rules it relies on are already covered by `Supabase/tests/run_local.sh`.

- [ ] **Step 1: Narrow the repository loader**

In `App/Services/SupabaseCareRepository.swift`, replace `load(client:now:)`, `createAccount` and `joinAccount` (the three static functions after `private init`) with:

```swift
    /// Loads one care account's data. Membership is resolved by SupabaseCareAccountService.
    static func load(client: SupabaseClient, accountID: String,
                     now: @escaping () -> Date = Date.init) async throws -> SupabaseCareRepository {
        do {
            let records = try await fetchRecords(client: client, accountID: accountID, now: now())
            return try SupabaseCareRepository(client: client, accountID: accountID, records: records, now: now)
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
```

Delete the `private struct MembershipRow` payload at the bottom of the file.

- [ ] **Step 2: Create the account service**

Create `App/Services/SupabaseCareAccountService.swift`:

```swift
import CareCore
import Foundation
import Supabase

/// Production CareAccountService: profile, membership and family setup through Supabase (RLS and
/// security-definer RPCs enforce the rules). Keeps the loaded repository for realtime.
@MainActor final class SupabaseCareAccountService: CareAccountService {
    private let client: SupabaseClient
    private var repository: SupabaseCareRepository?

    init(client: SupabaseClient) {
        self.client = client
    }

    func loadProfile() async throws -> MemberProfile {
        try await mapped {
            let row: ProfileRow = try await client.from("profiles")
                .select("display_name, city").eq("id", value: try await profileID()).single().execute().value
            return MemberProfile(displayName: row.displayName, city: row.city)
        }
    }

    func updateProfile(_ profile: MemberProfile) async throws {
        try await mapped {
            try await client.from("profiles")
                .update(ProfileRow(displayName: profile.displayName, city: profile.city))
                .eq("id", value: try await profileID()).execute()
        }
    }

    func loadMembership() async throws -> CareMembership? {
        try await mapped {
            let rows: [MembershipRoleRow] = try await client.from("account_members")
                .select("account_id, role").eq("profile_id", value: try await profileID())
                .order("created_at").limit(1).execute().value
            guard let row = rows.first else {
                await stopLiveUpdates()
                repository = nil
                return nil
            }
            guard let role = CareRole(rawValue: row.role) else {
                throw CareServiceError.invalidState("Unknown member role: \(row.role)")
            }
            if let repository, repository.accountID == row.accountID {
                try await repository.refresh()
            } else {
                await stopLiveUpdates()
                repository = try await SupabaseCareRepository.load(client: client, accountID: row.accountID)
            }
            guard let repository else { return nil }
            return CareMembership(accountID: row.accountID, inviteCode: repository.inviteCode, role: role,
                                  repository: repository)
        }
    }

    func createFamily(name: String) async throws {
        try await mapped {
            try await client.rpc("create_care_account", params: ["account_name": name, "member_role": "family"]).execute()
        }
    }

    func joinFamily(inviteCode: String, role: CareRole) async throws {
        try await mapped {
            try await client.rpc("join_care_account", params: ["code": inviteCode, "member_role": role.rawValue]).execute()
        }
    }

    func addSenior(name: String, age: Int, city: String, timeZoneIdentifier: String) async throws {
        guard let repository else { throw CareServiceError.invalidState("No care account loaded") }
        try await repository.addSenior(AccountSenior(id: UUID().uuidString, accountID: repository.accountID, name: name,
                                                     age: age, city: city, timeZoneIdentifier: timeZoneIdentifier))
    }

    func claimSenior(id: String) async throws {
        guard let repository else { throw CareServiceError.invalidState("No care account loaded") }
        do {
            try await repository.claimSeniorProfile(seniorID: id)
        } catch let error as PostgrestError where error.code == "23505" {
            throw CareServiceError.seniorAlreadyLinked
        }
    }

    func startLiveUpdates(onChange: @escaping @MainActor () async -> Void) async throws {
        try await repository?.startRealtime(onChange: onChange)
    }

    func stopLiveUpdates() async {
        await repository?.stopRealtime()
    }

    private func profileID() async throws -> String {
        try await client.auth.session.user.id.uuidString.lowercased()
    }

    private func mapped<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch {
            throw SupabaseErrorMapper.map(error)
        }
    }
}

private struct ProfileRow: Codable, Sendable {
    let displayName: String
    let city: String
    enum CodingKeys: String, CodingKey { case city, displayName = "display_name" }
}

private struct MembershipRoleRow: Decodable {
    let accountID: String
    let role: String
    enum CodingKeys: String, CodingKey { case role, accountID = "account_id" }
}
```

Note: `SupabaseCareRepository.perform` rethrows raw `PostgrestError` for code `23505`, which is what `claimSenior` catches.

- [ ] **Step 3: Keep LiveModeController compiling**

In `App/Services/LiveModeController.swift`, replace the bodies that used the removed helpers:

```swift
    func createAccount(name: String, role: CareRole) async {
        guard let client else { return }
        await run { try await SupabaseCareAccountService(client: client).createFamily(name: name) }
        await loadAccount(reportMissing: true)
    }

    func joinAccount(code: String, role: CareRole) async {
        guard let client else { return }
        await run { try await SupabaseCareAccountService(client: client).joinFamily(inviteCode: code, role: role) }
        await loadAccount(reportMissing: true)
    }
```

and in `loadAccount(reportMissing:)` replace the `do` body with:

```swift
            guard let membership = try await SupabaseCareAccountService(client: client).loadMembership() else {
                repository = nil
                if reportMissing { message = "No care account found for this user." }
                return
            }
            repository = membership.repository as? SupabaseCareRepository
```

(delete the now-unreachable `catch CareServiceError.invalidState` branch).

- [ ] **Step 4: Register the new file in the Xcode project**

Run:

```bash
python3 - <<'PY'
p = 'CareCompanion.xcodeproj/project.pbxproj'
s = open(p).read()
anchor = 'A00000000000000000000073 = {isa = PBXBuildFile; fileRef = A00000000000000000000072;};'
assert anchor in s
s = s.replace(anchor, anchor + '\n\tA00000000000000000000074 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App/Services/SupabaseCareAccountService.swift; sourceTree = "<group>";};\n\tA00000000000000000000075 = {isa = PBXBuildFile; fileRef = A00000000000000000000074;};')
s = s.replace('A00000000000000000000072, A00000000000000000000010', 'A00000000000000000000072, A00000000000000000000074, A00000000000000000000010')
s = s.replace('A00000000000000000000071, A00000000000000000000073)', 'A00000000000000000000071, A00000000000000000000073, A00000000000000000000075)')
open(p, 'w').write(s)
PY
plutil -lint CareCompanion.xcodeproj/project.pbxproj
```

Expected: `CareCompanion.xcodeproj/project.pbxproj: OK`.

- [ ] **Step 5: Build**

Run the iOS Simulator build command.
Expected: `** BUILD SUCCEEDED **`. Also run `swift test` — still 100 tests passing.

- [ ] **Step 6: Commit**

```bash
git add App/Services/SupabaseCareAccountService.swift App/Services/SupabaseCareRepository.swift App/Services/LiveModeController.swift CareCompanion.xcodeproj/project.pbxproj
git commit -m "feat: add Supabase care account service for onboarding"
```

---
### Task 7: Onboarding screens

**Files (all create, under `App/Features/Onboarding/`):**
- `OnboardingScaffold.swift` — shared layout, field, buttons, choice row
- `WelcomeView.swift`, `EmailEntryView.swift`, `CodeEntryView.swift`, `ProfileSetupView.swift`, `FamilySetupView.swift`, `AddSeniorView.swift` (includes `TimeZonePickerView`), `InviteFamilyView.swift`, `SeniorLinkView.swift`, `UnreachableView.swift`
- Modify: `CareCompanion.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 4/5 `AppSession` (read from `@Environment(AppSession.self)`); `CareTheme`, `CircleIcon`, `AvatarCircle`, `LovableCard`, `ReferenceButtonStyle` from `App/DesignSystem.swift`
- Produces (internal SwiftUI views used by Task 8's `SessionRootView`): `WelcomeView()`, `EmailEntryView()`, `CodeEntryView(email:)`, `ProfileSetupView()`, `FamilySetupView()`, `AddSeniorView()`, `InviteFamilyView(code:)`, `SeniorLinkView(seniors:)`, `UnreachableView()`

Screens are thin: every decision and error lives in `AppSession` (tested in Tasks 4–5). This task is verified by building here and by simulator runs in Task 9. Accessibility identifiers are given for those runs.

- [ ] **Step 1: Create the shared scaffold**

`App/Features/Onboarding/OnboardingScaffold.swift`:

```swift
import CareCore
import SwiftUI

/// Common layout for onboarding steps: title, optional subtitle, content, inline error, busy overlay.
struct OnboardingScaffold<Content: View>: View {
    @Environment(AppSession.self) private var session
    let title: String
    var subtitle: String?
    var showsSignOut = true
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    if showsSignOut && session.isSignedIn {
                        Button("Sign out") { Task { await session.signOut() } }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CareTheme.secondaryText)
                            .accessibilityIdentifier("onboarding.signOut")
                    }
                }
                .frame(minHeight: 44)

                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(CareTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("onboarding.title")
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 17))
                        .foregroundStyle(CareTheme.secondaryText)
                }

                content

                if let message = session.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CareTheme.coral)
                        .accessibilityIdentifier("onboarding.error")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CareTheme.background.ignoresSafeArea())
        .overlay { if session.isBusy { ProgressView().controlSize(.large) } }
        .disabled(session.isBusy)
    }
}

struct OnboardingField: View {
    let label: String
    @Binding var text: String
    var isSecure = false
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CareTheme.mutedText)
            Group {
                if isSecure {
                    SecureField(label, text: $text)
                } else {
                    TextField(label, text: $text)
                }
            }
            .font(.system(size: 19))
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            .accessibilityIdentifier(identifier)
        }
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var enabled = true
    let identifier: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Text(title).font(.system(size: 19, weight: .black))
        }
        .buttonStyle(ReferenceButtonStyle(fill: enabled ? CareTheme.sage : CareTheme.sage.opacity(0.45), height: 58, radius: 29))
        .disabled(!enabled)
        .accessibilityIdentifier(identifier)
    }
}

struct OnboardingLinkButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(CareTheme.sageDark)
            .frame(maxWidth: .infinity, minHeight: 48)
            .accessibilityIdentifier(identifier)
    }
}

struct OnboardingChoiceRow: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(selected ? CareTheme.sageDark : CareTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 18, weight: .black)).foregroundStyle(CareTheme.ink)
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                }
                Spacer()
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selected ? CareTheme.sageDark : CareTheme.cardStroke, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}
```

- [ ] **Step 2: Create Welcome, Email and Code screens**

`App/Features/Onboarding/WelcomeView.swift`:

```swift
import CareCore
import SwiftUI

struct WelcomeView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CircleIcon(systemName: "heart.text.square", color: CareTheme.sageDark, size: 56, iconSize: 25, fillOpacity: 0.20)
                .padding(.top, 70)
                .padding(.bottom, 32)
            Text("Care that travels\nacross time zones.")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(CareTheme.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcome.title")
            Text("Sign in to share check-ins, medicines and visits with your family.")
                .font(.system(size: 17))
                .foregroundStyle(CareTheme.secondaryText)
                .padding(.top, 16)
            Spacer()
            if session.isSignInAvailable {
                OnboardingPrimaryButton(title: "Get started", identifier: "welcome.getStarted") { session.startSignIn() }
            } else {
                Text("Sign-in isn't set up in this build.")
                    .font(.system(size: 14))
                    .foregroundStyle(CareTheme.mutedText)
                    .frame(maxWidth: .infinity)
            }
            OnboardingLinkButton(title: "Try the demo", identifier: "welcome.tryDemo") { session.tryDemo() }
                .padding(.top, 12)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(CareTheme.background.ignoresSafeArea())
    }
}
```

`App/Features/Onboarding/EmailEntryView.swift`:

```swift
import CareCore
import SwiftUI

struct EmailEntryView: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    #if DEBUG
    @State private var usePassword = false
    @State private var password = ""
    #endif

    var body: some View {
        OnboardingScaffold(title: "What's your email?",
                           subtitle: "We'll email you a 6-digit code. No password needed.",
                           showsSignOut: false) {
            OnboardingField(label: "Email", text: $email, identifier: "email.field")
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            OnboardingPrimaryButton(title: "Send code", enabled: !email.isEmpty, identifier: "email.send") {
                await session.sendCode(to: email)
            }
            #if DEBUG
            if usePassword {
                OnboardingField(label: "Password (test accounts)", text: $password, isSecure: true, identifier: "email.password")
                OnboardingPrimaryButton(title: "Sign in with password", enabled: !email.isEmpty && !password.isEmpty,
                                        identifier: "email.passwordSignIn") {
                    await session.signInWithPassword(email: email, password: password)
                }
            } else {
                OnboardingLinkButton(title: "Use password (debug)", identifier: "email.usePassword") { usePassword = true }
            }
            #endif
            // Not signed in yet, so signing out simply returns to Welcome.
            OnboardingLinkButton(title: "Back", identifier: "email.back") { Task { await session.signOut() } }
        }
    }
}
```

`App/Features/Onboarding/CodeEntryView.swift`:

```swift
import CareCore
import SwiftUI

struct CodeEntryView: View {
    @Environment(AppSession.self) private var session
    let email: String
    @State private var code = ""

    var body: some View {
        OnboardingScaffold(title: "Enter your code", subtitle: "We sent a 6-digit code to \(email).", showsSignOut: false) {
            OnboardingField(label: "6-digit code", text: $code, identifier: "code.field")
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .onChange(of: code) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    guard digits == newValue else {
                        code = digits
                        return
                    }
                    if digits.count == 6 { Task { await session.verifyCode(digits) } }
                }
            OnboardingPrimaryButton(title: "Continue", enabled: code.count == 6, identifier: "code.verify") {
                await session.verifyCode(code)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = session.secondsUntilResend()
                OnboardingLinkButton(title: seconds > 0 ? "Resend code in \(seconds)s" : "Resend code",
                                     identifier: "code.resend") {
                    Task { await session.resendCode() }
                }
                .disabled(seconds > 0)
            }
            OnboardingLinkButton(title: "Use a different email", identifier: "code.changeEmail") { session.useDifferentEmail() }
        }
        .onChange(of: session.errorMessage) { _, message in
            if message != nil { code = "" }
        }
    }
}
```

- [ ] **Step 3: Create Profile, Family and Add Senior screens**

`App/Features/Onboarding/ProfileSetupView.swift`:

```swift
import CareCore
import SwiftUI

struct ProfileSetupView: View {
    @Environment(AppSession.self) private var session
    @State private var displayName = ""
    @State private var city = ""

    var body: some View {
        OnboardingScaffold(title: "What should your family call you?",
                           subtitle: "Your name appears on your family's screens.") {
            OnboardingField(label: "Your name", text: $displayName, identifier: "profile.name")
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            OnboardingField(label: "City (optional)", text: $city, identifier: "profile.city")
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
            OnboardingPrimaryButton(title: "Continue", enabled: !displayName.isEmpty, identifier: "profile.continue") {
                await session.saveProfile(displayName: displayName, city: city)
            }
        }
    }
}
```

`App/Features/Onboarding/FamilySetupView.swift`:

```swift
import CareCore
import SwiftUI

struct FamilySetupView: View {
    private enum Mode: Hashable { case start, join }

    @Environment(AppSession.self) private var session
    @State private var mode = Mode.start
    @State private var familyName = ""
    @State private var inviteCode = ""
    @State private var joinAsSenior = false

    var body: some View {
        OnboardingScaffold(title: "Start or join a family",
                           subtitle: "Everyone caring for the same person shares one family.") {
            Picker("Start or join", selection: $mode) {
                Text("Start a family").tag(Mode.start)
                Text("Join with a code").tag(Mode.join)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("family.mode")

            switch mode {
            case .start:
                OnboardingField(label: "Family name", text: $familyName, identifier: "family.name")
                    .textInputAutocapitalization(.words)
                Text("Next you'll add the person your family cares for.")
                    .font(.system(size: 15))
                    .foregroundStyle(CareTheme.secondaryText)
                OnboardingPrimaryButton(title: "Create family", enabled: !familyName.isEmpty, identifier: "family.create") {
                    await session.createFamily(name: familyName)
                }
            case .join:
                OnboardingField(label: "Invite code", text: $inviteCode, identifier: "family.inviteCode")
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Text("Who are you in this family?")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CareTheme.mutedText)
                OnboardingChoiceRow(title: "I'm a family member", subtitle: "I help look after someone",
                                    selected: !joinAsSenior, identifier: "family.joinAsFamily") { joinAsSenior = false }
                OnboardingChoiceRow(title: "I'm the senior", subtitle: "My family looks after me",
                                    selected: joinAsSenior, identifier: "family.joinAsSenior") { joinAsSenior = true }
                OnboardingPrimaryButton(title: "Join family", enabled: !inviteCode.isEmpty, identifier: "family.join") {
                    await session.joinFamily(inviteCode: inviteCode, role: joinAsSenior ? .senior : .family)
                }
            }
        }
    }
}
```

`App/Features/Onboarding/AddSeniorView.swift`:

```swift
import CareCore
import SwiftUI

struct AddSeniorView: View {
    @Environment(AppSession.self) private var session
    @State private var name = ""
    @State private var age = 75
    @State private var city = ""
    @State private var timeZone = TimeZone.current.identifier

    var body: some View {
        OnboardingScaffold(title: "Who are you caring for?", subtitle: "Add the senior your family looks after.") {
            OnboardingField(label: "Their name", text: $name, identifier: "senior.name")
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            Stepper(value: $age, in: 40...120) {
                Text("Age \(age)").font(.system(size: 19, weight: .bold)).foregroundStyle(CareTheme.ink)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            .accessibilityIdentifier("senior.age")
            OnboardingField(label: "City (optional)", text: $city, identifier: "senior.city")
                .textInputAutocapitalization(.words)
            NavigationLink {
                TimeZonePickerView(selection: $timeZone)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Their time zone").font(.system(size: 15, weight: .bold)).foregroundStyle(CareTheme.mutedText)
                        Text(TimeZonePickerView.label(for: timeZone)).font(.system(size: 19)).foregroundStyle(CareTheme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(CareTheme.secondaryText)
                }
                .padding(16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CareTheme.cardStroke))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("senior.timeZone")
            OnboardingPrimaryButton(title: "Add senior", enabled: !name.isEmpty, identifier: "senior.add") {
                await session.addSenior(name: name, age: age, city: city, timeZoneIdentifier: timeZone)
            }
        }
    }
}

struct TimeZonePickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static func label(for identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: " ")
    }

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { Self.label(for: $0).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(zones, id: \.self) { zone in
            Button {
                selection = zone
                dismiss()
            } label: {
                HStack {
                    Text(Self.label(for: zone)).foregroundStyle(CareTheme.ink)
                    Spacer()
                    if zone == selection {
                        Image(systemName: "checkmark").foregroundStyle(CareTheme.sageDark)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search city or region")
        .navigationTitle("Time zone")
    }
}
```

- [ ] **Step 4: Create Invite, Senior Link and Unreachable screens**

`App/Features/Onboarding/InviteFamilyView.swift`:

```swift
import CareCore
import SwiftUI

struct InviteFamilyView: View {
    @Environment(AppSession.self) private var session
    let code: String

    var body: some View {
        OnboardingScaffold(title: "Invite your family",
                           subtitle: "Share this code with the senior and anyone else helping. They enter it after signing in.") {
            LovableCard {
                VStack(spacing: 8) {
                    Text("Invite code").font(.system(size: 15, weight: .bold)).foregroundStyle(CareTheme.mutedText)
                    Text(code)
                        .font(.system(size: 40, weight: .black, design: .monospaced))
                        .kerning(4)
                        .foregroundStyle(CareTheme.ink)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("invite.code")
                }
                .frame(maxWidth: .infinity)
            }
            ShareLink(item: "Join our family on CareCompanion. Sign in and enter invite code \(code).") {
                Label("Share code", systemImage: "square.and.arrow.up")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(CareTheme.sageDark)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
                    .overlay(Capsule().stroke(CareTheme.cardStroke))
            }
            .accessibilityIdentifier("invite.share")
            OnboardingPrimaryButton(title: "Continue", identifier: "invite.continue") { await session.finishInvite() }
        }
    }
}
```

`App/Features/Onboarding/SeniorLinkView.swift`:

```swift
import CareCore
import SwiftUI

struct SeniorLinkView: View {
    @Environment(AppSession.self) private var session
    let seniors: [AccountSenior]

    var body: some View {
        OnboardingScaffold(title: seniors.count == 1 ? "Is this you?" : "Which one is you?",
                           subtitle: "Linking this phone shares your check-ins with your family, and Apple Health data if you allow it.") {
            if seniors.isEmpty {
                Text("Your family hasn't added you yet. Ask them to add you, then tap Refresh.")
                    .font(.system(size: 17))
                    .foregroundStyle(CareTheme.secondaryText)
                OnboardingPrimaryButton(title: "Refresh", identifier: "seniorLink.refresh") { await session.retry() }
            } else {
                ForEach(seniors) { senior in
                    Button {
                        Task { await session.claimSenior(id: senior.id) }
                    } label: {
                        HStack(spacing: 14) {
                            AvatarCircle(text: initials(senior.name), color: CareTheme.gold, size: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("This is me: \(senior.name)").font(.system(size: 19, weight: .black)).foregroundStyle(CareTheme.ink)
                                Text(["\(senior.age) years", senior.city].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.system(size: 14)).foregroundStyle(CareTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(CareTheme.secondaryText)
                        }
                        .padding(18)
                        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CareTheme.cardStroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("seniorLink.claim")
                }
            }
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}
```

`App/Features/Onboarding/UnreachableView.swift`:

```swift
import CareCore
import SwiftUI

struct UnreachableView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        OnboardingScaffold(title: "Can't reach CareCompanion",
                           subtitle: "Check your connection and try again. Your family's information is safe.") {
            OnboardingPrimaryButton(title: "Try again", identifier: "unreachable.retry") { await session.retry() }
            OnboardingLinkButton(title: "Try the demo", identifier: "unreachable.tryDemo") { session.tryDemo() }
        }
    }
}
```

- [ ] **Step 5: Register the ten files in the Xcode project**

Run:

```bash
python3 - <<'PY'
p = 'CareCompanion.xcodeproj/project.pbxproj'
s = open(p).read()
names = ['OnboardingScaffold', 'WelcomeView', 'EmailEntryView', 'CodeEntryView', 'ProfileSetupView',
         'FamilySetupView', 'AddSeniorView', 'InviteFamilyView', 'SeniorLinkView', 'UnreachableView']
anchor = 'A00000000000000000000075 = {isa = PBXBuildFile; fileRef = A00000000000000000000074;};'
assert anchor in s
entries, refs, builds = [], [], []
for i, name in enumerate(names):
    ref, build = f'A{76 + 2 * i:023d}', f'A{77 + 2 * i:023d}'
    entries.append(f'\t{ref} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App/Features/Onboarding/{name}.swift; sourceTree = "<group>";}};')
    entries.append(f'\t{build} = {{isa = PBXBuildFile; fileRef = {ref};}};')
    refs.append(ref)
    builds.append(build)
s = s.replace(anchor, anchor + '\n' + '\n'.join(entries))
s = s.replace('A00000000000000000000074, A00000000000000000000010', 'A00000000000000000000074, ' + ', '.join(refs) + ', A00000000000000000000010')
s = s.replace('A00000000000000000000073, A00000000000000000000075)', 'A00000000000000000000073, A00000000000000000000075, ' + ', '.join(builds) + ')')
open(p, 'w').write(s)
PY
plutil -lint CareCompanion.xcodeproj/project.pbxproj
grep -c "App/Features/Onboarding/" CareCompanion.xcodeproj/project.pbxproj
```

Expected: `OK` and `10`. IDs used: `A…076`–`A…095`.

- [ ] **Step 6: Build**

Run the iOS Simulator build command.
Expected: `** BUILD SUCCEEDED **` with no warnings from `App/Features/Onboarding`.

- [ ] **Step 7: Commit**

```bash
git add App/Features/Onboarding CareCompanion.xcodeproj/project.pbxproj
git commit -m "feat: add sign-in and onboarding screens"
```

---
### Task 8: Wire AppSession into the app and remove the developer Live Supabase screen

**Files:**
- Create: `App/Features/Onboarding/SessionRootView.swift`
- Modify: `App/CareCompanionApp.swift` (app struct, `RootView`, `OnboardingView` logo, both Profile screens, `DemoMenuView`)
- Modify: `CareCompanionUITests/CareCompanionDemoUITests.swift`
- Delete: `App/Services/LiveModeController.swift`, `App/Features/LiveModeView.swift`
- Modify: `CareCompanion.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 4/5 `AppSession`; Task 6 `SupabaseCareAccountService(client:)`; Task 7 screens; existing `SubscriptionController.start(applyingTo:)`, `refresh(applyingTo:)`, `identify(accountID:applyingTo:)`
- Produces: `SessionRootView()`; `RootView` becomes internal (not `private`); UI identifiers `onboarding.logo`, `demo.exit`, `senior.profile.signOut`, `senior.profile.tryDemo`, `profile.signOut`, `profile.tryDemo`

- [ ] **Step 1: Write the failing UI test**

In `CareCompanionUITests/CareCompanionDemoUITests.swift`, add after `testSOSAndDemoResetPath`:

```swift
    func testExitDemoReturnsToWelcome() throws {
        let app = launchApp()

        XCTAssertTrue(app.element("onboarding.logo").waitForExistence(timeout: 6))
        app.element("onboarding.logo").press(forDuration: 1.1)
        XCTAssertTrue(app.element("demo.exit").waitForExistence(timeout: 3))
        app.element("demo.exit").tap()

        XCTAssertTrue(app.element("welcome.title").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("welcome.tryDemo").exists)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run the demo UI test command with `-only-testing:CareCompanionUITests/CareCompanionDemoUITests/testExitDemoReturnsToWelcome`.
Expected: FAIL at `onboarding.logo` `waitForExistence` (no such identifier yet).

- [ ] **Step 3: Create SessionRootView**

`App/Features/Onboarding/SessionRootView.swift`:

```swift
import CareCore
import SwiftUI

/// Top of the view tree: onboarding screens by phase, or the care app for the active AppState.
struct SessionRootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .ready, .demo:
                RootView()
                    .id(ObjectIdentifier(session.activeState))
                    .environment(session.activeState)
            case .restoring:
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CareTheme.background.ignoresSafeArea())
            case .welcome:
                WelcomeView()
            default:
                NavigationStack { step }
                    .tint(CareTheme.sageDark)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }

    @ViewBuilder private var step: some View {
        switch session.phase {
        case .enterEmail: EmailEntryView()
        case .enterCode(let email): CodeEntryView(email: email)
        case .needsProfile: ProfileSetupView()
        case .needsFamily: FamilySetupView()
        case .needsSenior: AddSeniorView()
        case .inviteFamily(let code): InviteFamilyView(code: code)
        case .needsSeniorLink(let seniors): SeniorLinkView(seniors: seniors)
        case .unreachable: UnreachableView()
        case .restoring, .welcome, .ready, .demo: EmptyView()
        }
    }
}
```

- [ ] **Step 4: Replace the app struct**

In `App/CareCompanionApp.swift`, replace the whole `struct CareCompanionApp: App { … }` with:

```swift
@main
struct CareCompanionApp: App {
    @State private var session = CareCompanionApp.makeSession()
    @State private var subscriptions = SubscriptionController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SessionRootView()
                .environment(session)
                .environment(subscriptions)
                .preferredColorScheme(.light)
                .task {
                    await session.start()
                    await subscriptions.start(applyingTo: session.activeState)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await subscriptions.refresh(applyingTo: session.activeState) }
                }
                .onChange(of: session.liveAccountID) { _, accountID in
                    // Subscriptions belong to the family account, so every member shares Plus/Pro.
                    Task { await subscriptions.identify(accountID: accountID, applyingTo: session.activeState) }
                }
        }
    }

    /// Demo mode never reads Apple Health; the live AppState gets HealthKit once an account is ready.
    @MainActor private static func makeSession() -> AppSession {
        let client = SupabaseConfig.sharedClient
        let auth: (any AuthSessionService)? = client.map { SupabaseAuthSessionService(client: $0) }
        let accounts: (any CareAccountService)? = client.map { SupabaseCareAccountService(client: $0) }
        return AppSession(auth: auth, accounts: accounts, demoState: AppState(repository: DemoCareRepository()),
                          makeHealthProvider: { HealthKitHealthDataProvider() }, isUITesting: CareRuntime.isUITesting)
    }
}
```

- [ ] **Step 5: Update RootView and the demo onboarding logo**

In `App/CareCompanionApp.swift`:

1. Change `private struct RootView: View {` to `struct RootView: View {`.
2. In `RootView.body`, replace `.sheet(isPresented: $showDemoMenu) { DemoMenuView() }` with:

```swift
        // Demo scenarios write care data, so the demo menu never opens on a real account.
        .sheet(isPresented: Binding(get: { showDemoMenu && !state.isProduction }, set: { showDemoMenu = $0 })) {
            DemoMenuView()
        }
```

3. In `OnboardingView`, after `.onLongPressGesture { showDemoMenu = true }` on the `CircleIcon(systemName: "heart.text.square", …)`, add `.accessibilityIdentifier("onboarding.logo")`.

- [ ] **Step 6: Production actions on both Profile screens**

Add near the other small shared views in `App/CareCompanionApp.swift` (e.g. above `private struct MedicineListView`):

```swift
/// "Switch role" in the demo; "Try the demo" and "Sign out" on a real account.
private struct ProfileSessionActions: View {
    @Environment(AppState.self) private var state
    @Environment(AppSession.self) private var session
    let identifierPrefix: String
    let switchRole: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if state.isProduction {
                ProfileActionRow(title: "Try the demo", identifier: "\(identifierPrefix).tryDemo") { session.tryDemo() }
                ProfileActionRow(title: "Sign out", tint: CareTheme.coral, identifier: "\(identifierPrefix).signOut") {
                    Task { await session.signOut() }
                }
            } else {
                ProfileActionRow(title: "Switch role", identifier: "\(identifierPrefix).switchRole", action: switchRole)
            }
        }
    }
}

private struct ProfileActionRow: View {
    let title: String
    var tint = CareTheme.ink
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 16, weight: .black)).foregroundStyle(tint)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .black)).foregroundStyle(CareTheme.secondaryText)
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(CareTheme.cardStroke))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
```

In `SeniorProfileScreen`, replace the entire `Button { state.switchToFamily() } label: { … } .buttonStyle(.plain) .accessibilityIdentifier("senior.profile.switchRole")` block with:

```swift
                    ProfileSessionActions(identifierPrefix: "senior.profile") { state.switchToFamily() }
```

In `FamilyProfileView`, replace the entire `Button { state.switchToSenior() } label: { … } .buttonStyle(.plain) .accessibilityIdentifier("profile.switchRole")` block with:

```swift
            ProfileSessionActions(identifierPrefix: "profile") { state.switchToSenior() }
```

- [ ] **Step 7: Demo menu "Exit demo" and developer section removal**

In `DemoMenuView`:

1. Add `@Environment(AppSession.self) private var session` below the existing `@Environment` properties.
2. Add a new first section inside the `List`:

```swift
                Section {
                    Button("Exit demo") {
                        dismiss()
                        Task { await session.exitDemo() }
                    }
                    .accessibilityIdentifier("demo.exit")
                }
```

3. Delete the whole `#if DEBUG Section("Developer") { NavigationLink("Live Supabase") { LiveModeView() } … } #endif` block.

- [ ] **Step 8: Delete LiveMode files and update the Xcode project**

```bash
git rm App/Services/LiveModeController.swift App/Features/LiveModeView.swift
python3 - <<'PY'
p = 'CareCompanion.xcodeproj/project.pbxproj'
s = open(p).read()
lines = [l for l in s.split('\n') if not any(l.strip().startswith(f'A000000000000000000000{n} =') for n in ('53', '54', '55', '56'))]
s = '\n'.join(lines)
for n in ('53', '54', '55', '56'):
    s = s.replace(f'A000000000000000000000{n}, ', '')
anchor = 'A00000000000000000000095 = {isa = PBXBuildFile; fileRef = A00000000000000000000094;};'
assert anchor in s
s = s.replace(anchor, anchor + '\n\tA00000000000000000000096 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App/Features/Onboarding/SessionRootView.swift; sourceTree = "<group>";};\n\tA00000000000000000000097 = {isa = PBXBuildFile; fileRef = A00000000000000000000096;};')
s = s.replace('A00000000000000000000094, A00000000000000000000010', 'A00000000000000000000094, A00000000000000000000096, A00000000000000000000010')
s = s.replace('A00000000000000000000095)', 'A00000000000000000000095, A00000000000000000000097)')
open(p, 'w').write(s)
PY
plutil -lint CareCompanion.xcodeproj/project.pbxproj
grep -c "LiveMode" CareCompanion.xcodeproj/project.pbxproj
grep -rn "LiveMode" App Sources Tests CareCompanionUITests
```

Expected: `OK`, `0`, and no grep matches.

- [ ] **Step 9: Build and run all tests**

1. Run `swift test`. Expected: 100 tests, 0 failures.
2. Run the iOS Simulator build. Expected: `** BUILD SUCCEEDED **`.
3. Run the full demo UI test command. Expected: `testDemoPathRunOne/Two/Three`, `testSOSAndDemoResetPath` and `testExitDemoReturnsToWelcome` all pass, `** TEST SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add App CareCompanionUITests CareCompanion.xcodeproj/project.pbxproj
git commit -m "feat: launch through AppSession sign-in and onboarding

Replaces the developer Live Supabase screen with the real flow. Production
Profile screens offer Try the demo and Sign out; the demo menu gains Exit
demo and never opens on a real account."
```

---
### Task 9: Documentation and simulator verification

**Files:**
- Modify: `docs/DATABASE.md`, `docs/HEALTHKIT.md`, `docs/REVENUECAT.md`, `docs/DECISIONS.md`, `docs/STATUS.md`, `docs/FULL_DEVELOPMENT_PLAN.md`

**Interfaces:**
- Consumes: the finished app from Task 8.
- Produces: documented setup and recorded verification evidence.

**Prerequisites (ask the user; do not guess or fabricate):**
1. Migration `Supabase/migrations/20260915000003_senior_device_link.sql` applied in the live project's SQL Editor.
2. Supabase Dashboard → Authentication → Email Templates → **Magic Link** template body includes `{{ .Token }}` (e.g. `Your CareCompanion code is {{ .Token }}`).
3. Family and senior test accounts (email + password), given to this session as environment variables `FAMILY_TEST_EMAIL`, `FAMILY_TEST_PASSWORD`, `SENIOR_TEST_EMAIL`, `SENIOR_TEST_PASSWORD`. Never write them to files.
4. Tell the user that runs 2–3 create a new family ("Plan test family <date>") in the live project, and that the family test account must not already belong to a family (the app uses the first membership). If it does, ask for fresh test accounts.

- [ ] **Step 1: Update docs**

`docs/DATABASE.md`:
- In "Setup checklist (live project)", replace step 3 with: `3. Dashboard → Authentication → Email Templates → Magic Link: include {{ .Token }} in the body so sign-in emails carry the 6-digit code the app asks for. Keep Providers → Email enabled.`
- In the "Account information flow" diagram, replace the magic-link lines with `Diwas->>Auth: signInWithOTP(email)` and `Diwas->>Auth: verifyOTP(email, code) → session`, and Maya's line with `Maya->>Auth: email code sign-in`.
- In "Verifying the live project", replace the three "check realtime by hand" steps with: `1. Sign in on the simulator as the family test user (DEBUG builds: Email → "Use password (debug)"). 2. Finish onboarding and open the Family Dashboard. 3. Write as the senior user (e.g. a medication_events row). The dashboard updates without interaction.`
- In "Senior device link", replace `Until Phase 5 onboarding, the link is made from Developer → Live Supabase → "I am <senior>".` with `Seniors make the link during onboarding ("Which one is you?").`
- In "Not in this phase", delete the bullet starting `Production mode is reachable only through the Debug-only developer screen`.

`docs/HEALTHKIT.md`: no "Live Supabase" steps should remain; run `grep -n "Live Supabase\|I am <senior>" docs/*.md` and reword each hit to point at onboarding.

`docs/DECISIONS.md`, append:

```markdown
- 2026-09-15 (Phase 5 slice 1): Sign-in is an emailed 6-digit code, not a magic link. Seniors often read email on a different device than the one being set up, which breaks deep links. Sign in with Apple waits until the project has a paid developer team.
- 2026-09-15: `AppSession` in CareCore owns launch and onboarding behind `AuthSessionService` and `CareAccountService`, so every routing and error path is unit-tested without Supabase. It replaced the Debug-only Live Supabase screen.
- 2026-09-15: Production role comes from `account_members.role`. Production hides "Switch role" and never opens the demo menu, because demo scenarios would write to real care data.
- 2026-09-15: Only family members create families in this slice; seniors join with the invite code and link themselves.
```

and change the Phase 2 line `Production mode is not wired into app startup yet…` by appending ` Superseded 2026-09-15: production is the normal launch path via AppSession.`

`docs/FULL_DEVELOPMENT_PLAN.md`, Phase 5: tick `Account onboarding: create family account, join by invite, select role, add senior.` only after simulator runs 2 and 3 pass. Tick exit criteria `A new family account can be created and used without demo data.`, `A caregiver can invite or join the same care account.` and `Demo mode remains one tap away for judging and sales demos.` only with evidence from runs 1–3.

- [ ] **Step 2: Automated verification**

Run and record exact results:
1. `swift test` — expected 100 tests, 0 failures.
2. `Supabase/tests/run_local.sh` — expected `RLS TESTS PASSED`, `SENIOR LINK TESTS PASSED`.
3. iOS Simulator build — expected `** BUILD SUCCEEDED **`.
4. Demo UI tests — expected five tests pass.

- [ ] **Step 3: Simulator runs (drive the iPhone 17 simulator; screenshot after each numbered checkpoint)**

Install the Debug build (`.build/DerivedData/Build/Products/Debug-iphonesimulator/CareCompanion.app`) and launch without `--ui-testing`. To start clean, uninstall first: `xcrun simctl uninstall booted com.carecompanion.txst`.

1. **Demo:** Welcome shows "Get started" and "Try the demo" → Try the demo → role choice → I am a senior → long-press the logo → Exit demo → Welcome.
2. **Family:** Get started → enter `$FAMILY_TEST_EMAIL` → Use password (debug) → sign in → name "Plan Tester", city "Austin" → Start a family "Plan test family" → add senior "Maya Test", 74, "Kathmandu", time zone search "Kathmandu" → invite code shown (record it) → Continue → Family Dashboard. Profile tab shows "Try the demo" and "Sign out", no "Switch role". Long-press the avatar: no demo menu.
3. **Senior:** Profile → Sign out → Welcome → sign in as `$SENIOR_TEST_EMAIL` with password → name "Maya" → Join with a code → recorded code → I'm the senior → Join family → "This is me: Maya Test" → Senior Home. Tap the Health button: the sheet offers "Allow Health Access" (not the family-device message).
4. **Errors and resume:**
   - Wrong code: Profile → Sign out → Get started → `$SENIOR_TEST_EMAIL` → Send code → type `000000` → error "That code didn't work. Check the email or send a new one." and "Resend code in …s" counting down. (Sends one real email; tell the user.)
   - Sign out mid-onboarding: Use a different email → Use password (debug) → sign in as the senior → Profile → Sign out → Welcome.
   - Resume and wrong invite (only if the user provides a third test account with no family): sign in with it → enter a name → on "Start or join a family" terminate the app (`xcrun simctl terminate booted com.carecompanion.txst`) → relaunch → it resumes at "Start or join a family" → Join with a code → `WRONG123` → "No family found for that code."
5. **Real email code (user assists):** sign out → Get started → the user's chosen email → Send code → ask the user for the 6-digit code from the inbox → enter it → reaches "What should your family call you?" or the app.

Any failure: stop, use superpowers:systematic-debugging, add a failing unit test in `AppSessionTests` where the logic is in CareCore, fix, rerun Step 2 and the failed run.

- [ ] **Step 4: Record results in STATUS**

Add a top section to `docs/STATUS.md`:

```markdown
## 2026-09-15 Phase 5 slice 1: sign-in and onboarding (branch `phase-5-new`)

Production is now the normal launch path: email-code sign-in, start or join a family, add or link the senior, then the app for your role. Demo stays one tap away. Spec: docs/superpowers/specs/2026-09-15-sign-in-onboarding-design.md. Plan: docs/superpowers/plans/2026-09-15-sign-in-onboarding.md.

**Verification:**
- <PASS/FAIL with counts for each Step 2 command>
- <PASS/FAIL for each simulator run 1–5, with what was observed>

**Not done in this slice:** full Settings screen, editing senior/member profiles, removing members, leaving a family, multiple families per login, Sign in with Apple.
```

Fill the two placeholder bullets with the actual observed results before committing; never mark a run PASS that was not observed.

- [ ] **Step 5: Commit**

```bash
git add docs
git commit -m "docs: record Phase 5 sign-in and onboarding setup and verification"
```
