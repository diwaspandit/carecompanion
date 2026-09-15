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
