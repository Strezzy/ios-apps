import XCTest

final class RiftUITests: XCTestCase {
    func testWelcomeAndModelPicker() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["A little space to think."].exists)
        attach("Rift-chat")
        app.buttons["modelPicker"].tap()
        XCTAssertTrue(app.staticTexts["Choose your AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["family-Qwen"].exists)
        attach("Rift-models")
        for _ in 0..<5 { if app.buttons["family-Qwen"].isHittable { break }; app.swipeUp() }
        app.buttons["family-Qwen"].tap()
        XCTAssertTrue(app.buttons["family-Gemma"].exists)
        for _ in 0..<5 { if app.buttons["family-Gemma"].isHittable { break }; app.swipeUp() }
        app.buttons["family-Gemma"].tap()
        attach("Rift-Gemma")
    }
    func testSettingsDoesNotNeedAnAccount() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 10))
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Offline mode"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacyAlwaysLocal"].firstMatch.exists)
        attach("Rift-settings")
    }
    func testReplyStylesSwitchAndReplayWithoutAModel() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 10))
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        let larger = app.buttons["Larger preview"]
        for _ in 0..<5 { if larger.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(larger.isHittable); larger.tap()
        XCTAssertTrue(app.navigationBars["Reply animation"].waitForExistence(timeout: 5))
        let picker = app.segmentedControls["replyStylePicker"]
        let rendered = app.descendants(matching: .any)["animationPreviewText"].firstMatch
        for style in ["Bloom", "Soft fade", "Instant", "Bloom"] {
            picker.buttons[style].tap()
            XCTAssertTrue(picker.buttons[style].isSelected)
            let complete = NSPredicate(format: "label CONTAINS %@", "Just a little room to think.")
            let done = XCTNSPredicateExpectation(predicate: complete, object: rendered)
            XCTAssertEqual(XCTWaiter.wait(for: [done], timeout: 10), .completed)
            attach("Rift-style-" + style)
        }
        // Both the inline and expanded previews deliberately reuse this
        // component. Interact with the visible sheet, not its covered parent.
        let replayButton = try XCTUnwrap(app.buttons.matching(identifier: "replayAnimation")
            .allElementsBoundByIndex.first { $0.isHittable })
        replayButton.tap()
        let replayed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Just a little room to think."), object: rendered)
        XCTAssertEqual(XCTWaiter.wait(for: [replayed], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Sample text, not an AI response."].firstMatch.exists)
    }
    func testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating() {
        let app = XCUIApplication()
        app.launchArguments = ["--rift-ui-fixture", "--rift-ui-stream"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let field = app.descendants(matching: .any)["messageInput"].firstMatch
        let last = app.descendants(matching: .any)["chatMessage-00000000-0000-0000-0000-000000000099"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("A reply while reading")
        assertTailIsVisible(last, above: field, in: app)
        attach("Rift-latest-above-keyboard")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertTailIsVisible(last, above: field, in: app)
        attach("Rift-latest-landscape")
        XCUIDevice.shared.orientation = .portrait
        assertTailIsVisible(last, above: field, in: app)
    }
    private func assertTailIsVisible(_ last: XCUIElement, above field: XCUIElement, in app: XCUIApplication) {
        let visible = NSPredicate { _, _ in
            last.exists && last.frame.maxY <= field.frame.minY + 2 &&
            last.frame.maxY > app.navigationBars.firstMatch.frame.maxY &&
            field.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2
        }
        let check = XCTNSPredicateExpectation(predicate: visible, object: last)
        XCTAssertEqual(XCTWaiter.wait(for: [check], timeout: 10), .completed,
            "Latest reply tail must remain visible, not only the input field")
    }
    func testComposerStaysAboveKeyboardInPortraitAndLandscape() {
        let app = XCUIApplication(); app.launch()
        let field = app.descendants(matching: .any)["messageInput"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("A keyboard layout test")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 2)
        attach("Rift-keyboard-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        let visible = NSPredicate { _, _ in field.frame.maxY <= app.keyboards.firstMatch.frame.minY + 2 }
        expectation(for: visible, evaluatedWith: field)
        waitForExpectations(timeout: 8)
        attach("Rift-keyboard-landscape")
        XCUIDevice.shared.orientation = .portrait
    }
    func testHereticHasMoreSizesAnd14BChoices() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 10))
        app.buttons["modelPicker"].tap()
        XCTAssertTrue(app.buttons["family-Heretic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Qwen3 14B · Compact"].exists)
        let more = app.buttons["sizes-Heretic"]
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.staticTexts["Qwen3 14B · Precision"].exists)
        attach("Rift-Heretic-sizes")
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
