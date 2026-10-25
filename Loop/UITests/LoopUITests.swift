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
        reveal(app.otherElements["editorCanvas"], in: app)
        capture("Loop-Crop", app: app)
        reveal(app.buttons["tool-overlays"], in: app)
        app.buttons["tool-overlays"].tap()
        reveal(app.buttons["add-blur"], in: app)
        app.buttons["add-blur"].tap()
        XCTAssertTrue(app.buttons["trackOverlay"].exists)
        reveal(app.otherElements["editorCanvas"], in: app)
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

    @MainActor func testFilesPickerCanOpenAndCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        XCTAssertTrue(app.buttons["project-Coastal motion"].waitForExistence(timeout: 40))
        let files = app.buttons["importFiles"]
        reveal(files, in: app)
        XCTAssertTrue(files.isEnabled)
        files.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 20))
        capture("Loop-Files-Picker", app: app)
        cancel.tap()
        XCTAssertTrue(files.waitForExistence(timeout: 10))
        XCTAssertTrue(files.isEnabled)
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let editorScroll = app.scrollViews.containing(.other, identifier: "editorCanvas").firstMatch
        let scroll = editorScroll.exists ? editorScroll : app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        var previousY: CGFloat?
        var stationaryAttempts = 0
        var fallbackUp = true
        for _ in 0..<14 {
            guard element.exists else { XCTFail("The target disappeared while scrolling."); return }
            let viewport = scroll.frame.insetBy(dx: 0, dy: 12)
            let frame = element.frame
            let fits = frame.minY >= viewport.minY && frame.maxY <= viewport.maxY
            if element.isHittable && (fits || frame.height > viewport.height) { return }
            if let previousY, abs(frame.minY - previousY) < 2 { stationaryAttempts += 1 }
            else { stationaryAttempts = 0 }
            previousY = frame.minY
            if stationaryAttempts >= 2 && (frame.maxY > viewport.maxY || frame.minY < viewport.minY) {
                XCTFail("The scroll view stopped moving before revealing the target.")
                return
            }
            let up: Bool
            if frame.maxY > viewport.maxY { up = true }
            else if frame.minY < viewport.minY { up = false }
            else {
                // No visible offscreen geometry: try a small upward scroll first.
                // Change direction only after two gestures made no progress.
                if stationaryAttempts >= 2 { fallbackUp.toggle(); stationaryAttempts = 0 }
                up = fallbackUp
            }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: up ? 0.72 : 0.28))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: up ? 0.40 : 0.60))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
