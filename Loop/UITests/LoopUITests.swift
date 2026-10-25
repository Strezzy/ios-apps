import XCTest

final class LoopUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testCreateCropAndExportAnimation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let project = app.buttons["project-Coastal motion"]
        XCTAssertTrue(project.waitForExistence(timeout: 40))
        capture("Loop-Home", app: app)
        reveal(project, in: app)
        project.tap()
        XCTAssertTrue(app.otherElements["editorCanvas"].waitForExistence(timeout: 20))
        capture("Loop-Editor", app: app)
        app.buttons["tool-crop"].tap()
        reveal(app.buttons["aspect-portrait"], in: app)
        app.buttons["aspect-portrait"].tap()
        app.swipeDown()
        capture("Loop-Crop", app: app)
        reveal(app.buttons["tool-overlays"], in: app)
        app.buttons["tool-overlays"].tap()
        reveal(app.buttons["add-blur"], in: app)
        app.buttons["add-blur"].tap()
        XCTAssertTrue(app.buttons["trackOverlay"].exists)
        app.swipeDown()
        capture("Loop-Overlays", app: app)
        reveal(app.buttons["tool-export"], in: app)
        app.buttons["tool-export"].tap()
        capture("Loop-Export-Settings", app: app)
        reveal(app.buttons["createAnimation"], in: app)
        app.buttons["createAnimation"].tap()
        XCTAssertTrue(app.buttons["shareAnimation"].waitForExistence(timeout: 90))
        capture("Loop-Completed", app: app)
        app.buttons["exportDetailDone"].tap()
        app.buttons["editorDone"].tap()
        app.tabBars.buttons["Library"].tap()
        app.segmentedControls.buttons["Exports"].tap()
        XCTAssertTrue(app.staticTexts["Coastal motion"].waitForExistence(timeout: 10))
        capture("Loop-Library", app: app)
    }

    @MainActor func testAppearanceAndPrivacySettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["project-Coastal motion"].waitForExistence(timeout: 40))
        app.tabBars.buttons["Settings"].tap()
        let dark = app.segmentedControls["appearancePicker"].buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 10))
        dark.tap()
        capture("Loop-Settings-Dark", app: app)
        app.tabBars.buttons["Create"].tap()
        capture("Loop-Home-Dark", app: app)
        app.tabBars.buttons["Settings"].tap()
        app.segmentedControls["appearancePicker"].buttons["Light"].tap()
        capture("Loop-Settings-Light", app: app)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.swipeDown()
        }
        for _ in 0..<12 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
