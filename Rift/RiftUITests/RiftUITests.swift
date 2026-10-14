import XCTest
final class RiftUITests: XCTestCase {
    func testWelcomeAndModelPicker() {
        let app=XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["A little space to think."].exists)
        attach("Rift-chat")
        app.buttons["modelPicker"].tap()
        XCTAssertTrue(app.staticTexts["Choose your AI"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["family-Qwen"].exists)
        attach("Rift-models")
        app.buttons["family-Qwen"].tap()
        XCTAssertTrue(app.buttons["family-Gemma"].exists)
        app.buttons["family-Gemma"].tap()
        attach("Rift-Gemma")
    }
    func testSettingsDoesNotNeedAnAccount() {
        let app=XCUIApplication(); app.launch()
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        XCTAssertTrue(app.switches["Offline mode"].exists)
        attach("Rift-settings")
    }
    func testNativeReplyRevealPreview() {
        let app=XCUIApplication(); app.launch()
        app.buttons["More options"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        let preview=app.buttons["previewReplyAnimation"]
        for _ in 0..<4 { if preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.isHittable)
        preview.tap()
        let sample=app.staticTexts["replyAnimationSample"]
        XCTAssertTrue(sample.waitForExistence(timeout:5))
        let finished=NSPredicate(format:"label CONTAINS %@","room to think")
        expectation(for:finished,evaluatedWith:sample)
        waitForExpectations(timeout:12)
        attach("Rift-reply-reveal")
    }
    private func attach(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIApplication().screenshot()); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
