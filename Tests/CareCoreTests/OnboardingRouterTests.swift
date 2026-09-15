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
