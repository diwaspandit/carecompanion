import XCTest

/// Launch smoke tests that don't depend on a particular account. Signed-in flows are verified
/// against the live project (see docs/STATUS.md) because they need real users.
final class CareCompanionLaunchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchReachesWelcomeOrSignedInScreen() {
        let app = launchApp()
        let welcome = app.element("welcome.title")
        let family = app.element("family.title")
        let senior = app.element("senior.checkIn")
        let setup = app.element("setup.submit")
        let profile = app.element("profile.continue")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if [welcome, family, senior, setup, profile].contains(where: \.exists) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("App did not reach a usable screen within 20 seconds")
    }

    func testSignUpFormValidatesBeforeSubmitting() throws {
        let app = launchApp()
        guard app.element("welcome.title").waitForExistence(timeout: 10) else {
            throw XCTSkip("A session is already signed in on this simulator.")
        }
        app.segmentedControls["auth.mode"].buttons["Create account"].tap()
        XCTAssertTrue(app.element("auth.confirmPassword").waitForExistence(timeout: 2))

        let submit = app.buttons["auth.submit"]
        XCTAssertFalse(submit.isEnabled)

        app.textFields["auth.email"].tap()
        app.textFields["auth.email"].typeText("family@example.com")
        app.secureTextFields["auth.password"].tap()
        app.secureTextFields["auth.password"].typeText("short")
        XCTAssertTrue(app.element("form.error").waitForExistence(timeout: 2))
        XCTAssertFalse(submit.isEnabled)
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fast-sos", "-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        return app
    }
}

private extension XCUIApplication {
    func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }
}
