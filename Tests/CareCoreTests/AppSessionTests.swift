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
