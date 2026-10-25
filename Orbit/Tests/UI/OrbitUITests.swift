import XCTest

final class OrbitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeInPortraitAndLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.buttons["orbit.import.photos"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["orbit.import.files"].exists)
        XCTAssertTrue(app.buttons["orbit.import.photos"].isHittable)
        capture(app, name: "Orbit-Home-Portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = expectation(for: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, evaluatedWith: app)
        wait(for: [rotated], timeout: 10)
        XCTAssertTrue(app.buttons["orbit.import.photos"].exists)
        XCTAssertTrue(app.buttons["orbit.import.files"].exists)
        // The welcome card is deliberately scrollable in the shorter viewport.
        // Confirm the import controls can actually be reached after rotation.
        for _ in 0..<3 where !app.buttons["orbit.import.photos"].isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["orbit.import.photos"].isHittable)
        XCTAssertTrue(app.buttons["orbit.import.files"].isHittable)
        capture(app, name: "Orbit-Home-Landscape")
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
