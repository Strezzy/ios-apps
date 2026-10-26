import XCTest

final class CreativeUITests: XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable{return}
            let scroll=app.scrollViews.firstMatch
            let start=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.88))
            let end=scroll.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.28))
            start.press(forDuration:0.04,thenDragTo:end)
        }
    }
    @MainActor private func capture(_ name:String,_ app:XCUIApplication) {
        let file=XCTAttachment(screenshot:app.screenshot());file.name=name;file.lifetime = .keepAlways;add(file)
    }
    @MainActor func testSimpleLooksSubjectAndSaveControls() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        let project=app.buttons["project-Coastal motion"]
        XCTAssertTrue(project.waitForExistence(timeout:40));reveal(project,in:app);project.tap()
        XCTAssertTrue(app.otherElements["editorCanvas"].waitForExistence(timeout:20))
        app.buttons["tool-effects"].tap()
        let look=app.buttons["world-winter"];XCTAssertTrue(look.waitForExistence(timeout:10));reveal(look,in:app)
        XCTAssertTrue(look.isHittable);capture("Loop2-Simple-Looks",app)
        XCTAssertFalse(app.switches["Use scene depth"].isHittable,"Advanced depth controls must start collapsed.")
        let choose=app.buttons["Choose a subject"];reveal(choose,in:app);choose.tap()
        XCTAssertTrue(app.otherElements["subjectPickerCanvas"].waitForExistence(timeout:10))
        XCTAssertTrue(app.segmentedControls.buttons["Keep"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Remove"].exists)
        capture("Loop2-Choose-Subject",app);app.navigationBars.buttons["Cancel"].tap()
        let save=app.buttons["tool-export"];reveal(save,in:app);save.tap()
        XCTAssertTrue(app.staticTexts["Ready to save"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["fps-24"].isHittable,"Advanced export controls must start collapsed.")
        capture("Loop2-Simple-Save",app)
        let advanced=app.buttons["exportAdvanced"]
        if advanced.exists {reveal(advanced,in:app);advanced.tap()} else {
            let label=app.staticTexts["Size, smoothness & advanced options"];reveal(label,in:app);label.tap()
        }
        let rate=app.buttons["fps-24"];reveal(rate,in:app);XCTAssertTrue(rate.isHittable)
        capture("Loop2-Optional-Details",app)
    }
}
