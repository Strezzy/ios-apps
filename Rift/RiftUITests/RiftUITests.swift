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
        XCTAssertTrue(app.switches["Offline mode"].exists)
        attach("Rift-settings")
    }
    func testReplyAnimationHandlesUnevenBurstsAndReplay() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["More options"].waitForExistence(timeout: 10))
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        let preview = app.buttons["Preview animation"]
        for _ in 0..<4 { if preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable); preview.tap()
        XCTAssertTrue(app.navigationBars["Reply animation"].waitForExistence(timeout: 5))
        attach("Rift-Bloom-arriving")
        let rendered = app.descendants(matching: .any)["animationPreviewText"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS %@", "Just a little room to think.")
        wait(for: [expectation(for: predicate, evaluatedWith: rendered)], timeout: 10)
        XCTAssertTrue(rendered.label.contains("🌸"))
        attach("Rift-Bloom-complete")
        let replay = app.buttons["replayAnimation"]
        XCTAssertTrue(replay.isHittable); replay.tap()
        attach("Rift-Bloom-replay")
        wait(for: [expectation(for: predicate, evaluatedWith: rendered)], timeout: 10)
        XCTAssertTrue(app.staticTexts["Sample text, not an AI response. The preview deliberately feeds uneven chunks to the same renderer used in chat."].exists)
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
