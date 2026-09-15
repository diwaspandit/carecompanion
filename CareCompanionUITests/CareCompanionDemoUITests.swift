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

    func testFamilyLandingAndCareDetails() throws {
        let app = launchApp()
        app.element("onboarding.family").tap()
        XCTAssertTrue(app.element("family.title").waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Waiting to hear from Ma"].exists)
        XCTAssertTrue(app.element("family.openCare").isHittable)
        XCTAssertFalse(app.element("family.steps").exists)
        attachScreenshot(app, name: "Family home - initial")

        app.element("family.openWifeCare").tap()
        XCTAssertTrue(app.element("wife.name").waitForExistence(timeout: 3))
        XCTAssertEqual(app.element("wife.name").label, "Wife")
        XCTAssertEqual(app.element("wife.steps").label, "6,420")
        XCTAssertTrue(app.element("wife.checkedIn").exists)
        XCTAssertTrue(app.element("wife.medications").exists)
        XCTAssertTrue(app.element("wife.mood").exists)
        XCTAssertTrue(app.element("wife.sleep").exists)
        XCTAssertTrue(app.element("wife.heartRate").exists)
        XCTAssertTrue(app.element("wife.demoDataNotice").exists)
        XCTAssertFalse(app.element("family.medications").exists)
        attachScreenshot(app, name: "Wife care details")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        for name in ["Dad", "Princess"] {
            let card = app.element("family.sample.\(name.lowercased())")
            XCTAssertTrue(card.isHittable)
            card.tap()
            XCTAssertTrue(app.element("sampleProfile.name").waitForExistence(timeout: 3))
            XCTAssertEqual(app.element("sampleProfile.name").label, name)
            app.buttons["sampleProfile.done"].tap()
        }
        XCTAssertTrue(app.staticTexts["Waiting to hear from Ma"].exists)

        app.element("family.openCare").tap()
        XCTAssertTrue(app.element("family.steps").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("family.medications").exists)
        XCTAssertTrue(app.element("family.sleep").exists)
        XCTAssertTrue(app.element("family.heartRate").exists)
        attachScreenshot(app, name: "Maya care details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.element("family.openCare").waitForExistence(timeout: 3))
    }

    func testFamilyLandingReflectsCheckIn() throws {
        let app = launchApp()
        app.element("onboarding.senior").tap()
        app.element("senior.checkIn").tap()
        XCTAssertTrue(app.element("mood.okay").waitForExistence(timeout: 6))
        app.element("mood.okay").tap()
        XCTAssertTrue(app.staticTexts["Ma checked in today"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["Waiting to hear from Ma"].exists)
        attachScreenshot(app, name: "Family home - checked in")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

        app.element("tab.home").tap()
        XCTAssertTrue(app.staticTexts["Ma sent an SOS"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "Family home - SOS")
        app.element("family.status").tap()
        XCTAssertTrue(app.element("alerts.sos").waitForExistence(timeout: 3))

        openDemoMenu(in: app)
        app.element("demo.reset").tap()

        XCTAssertTrue(app.element("onboarding.title").waitForExistence(timeout: 3))
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
        app.element("family.openCare").tap()
        XCTAssertTrue(app.element("family.medications").waitForExistence(timeout: 3))
        XCTAssertTrue(app.element("family.medications").exists)
        XCTAssertTrue(app.element("family.steps").exists)
        XCTAssertTrue(app.element("family.sleep").exists)

        app.element("insight.unlock").tap()
        XCTAssertTrue(app.element("paywall.buy").waitForExistence(timeout: 3))
        app.element("paywall.buy").tap()
        XCTAssertTrue(app.element("insight.full").waitForExistence(timeout: 3))

        app.navigationBars.buttons.element(boundBy: 0).tap()
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
