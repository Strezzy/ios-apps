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
        XCTAssertTrue(app.sliders["overlayStrength"].waitForExistence(timeout: 5))
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

    @MainActor func testLiveOverlayControlsPrecisionZoomAndQuickDelete() throws {
        let app = openEditor()
        app.buttons["tool-overlays"].tap()
        XCTAssertTrue(app.buttons["add-blur"].waitForExistence(timeout: 5))
        app.buttons["add-blur"].tap()
        let strength = app.sliders["overlayStrength"]
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["add-blur"].exists)
        XCTAssertTrue(strength.isHittable, "Effect controls should appear immediately below the pinned video.")
        strength.adjust(toNormalizedSliderPosition: 0.9)
        capture("Loop-Live-Effects", app: app)

        let overlay = app.buttons["overlay-blur"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let original = overlayValues(overlay)
        app.buttons["canvasZoomIn"].tap()
        app.buttons["canvasZoomIn"].tap()
        let zoomed = overlayValues(overlay)
        for key in ["x", "y", "width", "height"] {
            XCTAssertEqual(zoomed[key] ?? -1, original[key] ?? -2, accuracy: 0.00001, "View zoom must not edit the saved overlay.")
        }
        XCTAssertGreaterThan(zoomed["zoom"] ?? 0, original["zoom"] ?? 1)
        let center = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 28, dy: 12)))
        let placed = overlayValues(overlay)
        XCTAssertGreaterThan(abs((placed["x"] ?? 0) - (original["x"] ?? 0)), 0.001)
        capture("Loop-Precision-Zoom", app: app)
        app.buttons["canvasZoomReset"].tap()
        let unzoomed = overlayValues(overlay)
        for key in ["x", "y", "width", "height"] {
            XCTAssertEqual(unzoomed[key] ?? -1, placed[key] ?? -2, accuracy: 0.00001, "Zooming out must keep the exact placed source position.")
        }

        app.buttons["overlayDelete"].tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-blur"].waitForExistence(timeout: 5))
        app.buttons["undoEdit"].tap()
        XCTAssertTrue(overlay.waitForExistence(timeout: 5), "Quick deletion must be undoable.")
        overlay.tap()
        XCTAssertTrue(strength.waitForExistence(timeout: 5))
        let canvas = app.otherElements["canvasViewport"]
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.72)).tap()
        XCTAssertTrue(app.buttons["add-pixelate"].waitForExistence(timeout: 5), "Tapping empty video should restore the Add menu.")
        app.buttons["add-pixelate"].tap()
        XCTAssertTrue(app.sliders["overlayStrength"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Block size"].exists)
        capture("Loop-Live-Pixelation", app: app)
    }

    @MainActor func testEmojiUsesSystemKeyboardAndReturnsToAddMenu() throws {
        let app = openEditor()
        app.buttons["tool-overlays"].tap()
        app.buttons["add-emoji"].tap()
        let input = app.textFields["overlayContent"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            reveal(app.buttons["chooseEmoji"], in: app)
            app.buttons["chooseEmoji"].tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "Emoji entry must open the real system keyboard.")
        XCTAssertTrue(input.isEnabled)
        XCTAssertTrue(app.otherElements["canvasViewport"].isHittable, "The preview stays visible while entering emoji.")
        capture("Loop-Emoji-Keyboard", app: app)
        XCTAssertTrue(app.buttons["emojiKeyboardDone"].waitForExistence(timeout: 5))
        app.buttons["emojiKeyboardDone"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        reveal(app.buttons["overlayDone"], in: app)
        app.buttons["overlayDone"].tap()
        XCTAssertTrue(app.buttons["add-emoji"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["overlay-emoji"].exists)
    }

    @MainActor private func openEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
        let project = app.buttons["project-Coastal motion"]
        XCTAssertTrue(project.waitForExistence(timeout: 40))
        reveal(project, in: app)
        project.tap()
        XCTAssertTrue(app.otherElements["editorCanvas"].waitForExistence(timeout: 20))
        return app
    }

    @MainActor private func overlayValues(_ element: XCUIElement) -> [String: Double] {
        guard let value = element.value as? String else { XCTFail("Overlay source geometry is unavailable."); return [:] }
        return Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, let number = Double(parts[1]) else { return nil }
            return (String(parts[0]), number)
        })
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let editorScroll = app.scrollViews["editorControlsScroll"]
        let scroll = editorScroll.exists ? editorScroll : app.scrollViews.firstMatch
        // The preview and tool strip stay outside the scrolling controls.
        if element.isHittable && (!scroll.exists || element.frame.maxY <= scroll.frame.minY) { return }
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
