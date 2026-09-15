import XCTest

final class CareCompanionDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoPathRunOne() throws {
        try runCoreDemoPath()
    }

    func testDemoPathRunTwo() throws {
        try runCoreDemoPath()
    }

    func testDemoPathRunThree() throws {
        try runCoreDemoPath()
    }

    func testSOSAndDemoResetPath() throws {
        let app = launchApp()

        app.element("onboarding.senior").tap()
        XCTAssertTrue(app.element("senior.sos").waitForExistence(timeout: 3))
        app.element("senior.sos").tap()

        XCTAssertTrue(app.element("sos.notified.title").waitForExistence(timeout: 8))
        app.element("sos.backToFamily").tap()

        XCTAssertTrue(app.element("alerts.title").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("alerts.sos").exists)

        openDemoMenu(in: app)
        app.element("demo.reset").tap()

        XCTAssertTrue(app.element("onboarding.title").waitForExistence(timeout: 3))
    }

    func testExitDemoReturnsToWelcome() throws {
        let app = launchApp()

        XCTAssertTrue(app.element("onboarding.logo").waitForExistence(timeout: 6))
        app.element("onboarding.logo").press(forDuration: 1.1)
        XCTAssertTrue(app.element("demo.exit").waitForExistence(timeout: 3))
        app.element("demo.exit").tap()

        XCTAssertTrue(app.element("welcome.title").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("welcome.tryDemo").exists)
    }

    private func runCoreDemoPath() throws {
        let app = launchApp()

        XCTAssertTrue(app.element("onboarding.title").waitForExistence(timeout: 6))
        app.element("onboarding.senior").tap()

        XCTAssertTrue(app.element("senior.checkIn").waitForExistence(timeout: 3))
        app.element("senior.checkIn").tap()

        XCTAssertTrue(app.element("mood.okay").waitForExistence(timeout: 6))
        app.element("mood.okay").tap()

        XCTAssertTrue(app.element("family.title").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("family.checkedIn").exists)
        XCTAssertTrue(app.element("family.medications").exists)
        XCTAssertTrue(app.element("family.steps").exists)
        XCTAssertTrue(app.element("family.sleep").exists)

        app.element("insight.unlock").tap()
        XCTAssertTrue(app.element("paywall.buy").waitForExistence(timeout: 3))
        app.element("paywall.buy").tap()
        XCTAssertTrue(app.element("insight.full").waitForExistence(timeout: 3))

        app.element("tab.appointments").tap()
        XCTAssertTrue(app.element("appointment.prepare").waitForExistence(timeout: 3))
        app.element("appointment.prepare").tap()
        XCTAssertTrue(app.element("appointment.prep.ready").waitForExistence(timeout: 3))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--fast-sos", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }

    private func openDemoMenu(in app: XCUIApplication) {
        if app.element("family.avatar").exists {
            app.element("family.avatar").press(forDuration: 1.1)
        } else {
            app.element("alerts.title").press(forDuration: 1.1)
        }
        XCTAssertTrue(app.element("demo.reset").waitForExistence(timeout: 3))
    }
}

private extension XCUIApplication {
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }
}
