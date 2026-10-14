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
    private func attach(_ name:String) {
        let attachment=XCTAttachment(screenshot:XCUIApplication().screenshot()); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
