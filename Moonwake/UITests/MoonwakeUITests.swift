import XCTest

final class MoonwakeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false; XCUIDevice.shared.orientation = .landscapeLeft }
    override func tearDownWithError() throws {
        // Stop the renderer before XCTest finishes its recording and attachments.
        let running = XCUIApplication()
        if running.state != .notRunning { running.terminate() }
    }
    private func app(realm: Int? = nil, reset: Bool = true) -> XCUIApplication {
        let app=XCUIApplication(); app.launchArguments=["--ui-testing","--skip-intro"]
        if reset { app.launchArguments.append("--reset-save") }
        if let realm { app.launchArguments += ["--realm",String(realm)] }
        app.launch(); return app
    }
    private func snapshot(_ name: String, app: XCUIApplication) {
        // Capture the oriented display; the app-window crop can use portrait
        // coordinates for a landscape-only app on newer simulator runtimes.
        let attachment=XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTitleBeginCombatPauseAndResume() {
        // This flow includes three captures and simulator crash-log collection
        // at teardown. Keep a bounded allowance for that infrastructure work.
        executionTimeAllowance = 240
        let app=app()
        XCTAssertTrue(app.buttons["title.begin"].waitForExistence(timeout:15))
        snapshot("01-Moonwake-Title",app:app)
        app.buttons["title.begin"].tap()
        XCTAssertTrue(app.buttons["game.attack"].waitForExistence(timeout:10))
        app.buttons["game.attack"].tap(); app.buttons["game.dash"].tap(); app.buttons["game.pulse"].tap()
        app.buttons["game.pause"].tap()
        XCTAssertTrue(app.buttons["pause.resume"].waitForExistence(timeout:5))
        snapshot("02-Pause",app:app)
        app.buttons["pause.resume"].tap()
        XCTAssertTrue(app.buttons["game.attack"].waitForExistence(timeout:5))
        snapshot("03-Moonshore-Gameplay",app:app)
    }
    func testJournalUpgradesAndSettingsAreFunctional() {
        let app=app(realm:0)
        XCTAssertTrue(app.buttons["game.pause"].waitForExistence(timeout:15))
        app.buttons["game.pause"].tap(); app.buttons["pause.journal"].tap()
        XCTAssertTrue(app.buttons["menu.back"].waitForExistence(timeout:5)); snapshot("04-Journal",app:app)
        app.buttons["menu.back"].tap()
        if app.buttons["game.pause"].exists { app.buttons["game.pause"].tap() }
        app.buttons["pause.upgrades"].tap(); XCTAssertTrue(app.buttons["menu.back"].waitForExistence(timeout:5)); snapshot("05-Upgrades",app:app)
        app.buttons["menu.back"].tap()
        if app.buttons["game.pause"].exists { app.buttons["game.pause"].tap() }
        app.buttons["pause.settings"].tap(); XCTAssertTrue(app.buttons["menu.back"].waitForExistence(timeout:5)); snapshot("06-Settings",app:app)
    }
    func testAllFiveRegionsRenderNativeGameplay() {
        for realm in 0..<5 {
            let app=app(realm:realm)
            XCTAssertTrue(app.buttons["game.attack"].waitForExistence(timeout:15))
            // The initial camera settles over the first few rendered frames.
            RunLoop.current.run(until:Date().addingTimeInterval(1.0))
            snapshot("Realm-\(realm)-Native-Gameplay",app:app)
            app.terminate()
        }
    }
    func testSavedJourneyCanContinueAfterRelaunch() {
        let first=app(); XCTAssertTrue(first.buttons["title.begin"].waitForExistence(timeout:15)); first.buttons["title.begin"].tap()
        XCTAssertTrue(first.buttons["game.pause"].waitForExistence(timeout:10)); first.buttons["game.pause"].tap(); first.buttons["pause.title"].tap()
        first.terminate()
        let second=app(reset:false); XCTAssertTrue(second.buttons["title.continue"].waitForExistence(timeout:15)); second.buttons["title.continue"].tap()
        XCTAssertTrue(second.buttons["game.attack"].waitForExistence(timeout:10))
    }
}
