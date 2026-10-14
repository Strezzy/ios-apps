import XCTest

final class RiftUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }
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
        for style in ["bloom", "fade", "instant", "starlight", "wave", "bounce"] {
            let button = app.buttons["replyStyle-expanded-" + style]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            if !button.isHittable { app.swipeDown() }
            button.tap()
            XCTAssertTrue(button.isSelected)
            waitForVisiblePreview(in: app)
            attach("Rift-style-" + style)
        }
        let replay = app.buttons["replayAnimation-expanded"]
        XCTAssertTrue(replay.isHittable); replay.tap()
        waitForVisiblePreview(in: app)
        XCTAssertTrue(app.staticTexts["Sample text, not an AI response."].firstMatch.exists)
    }
    private func waitForVisiblePreview(in app: XCUIApplication) {
        let completed = NSPredicate { _, _ in
            // Re-query the stable expanded surface, not a Text branch which was
            // replaced during streaming or the covered inline Settings sample.
            let sample = app.descendants(matching: .any)["animationPreview-expanded"].firstMatch
            return sample.exists && sample.isHittable &&
                sample.label.contains("Just a little room to think.") &&
                (sample.value as? String) == "Preview complete"
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: completed, object: app)], timeout: 12)
        XCTAssertEqual(result, .completed, "Visible selected-style preview must actually finish")
    }
    func testLatestReplyMovesAboveKeyboardWhileStreamingAndRotating() {
        let app = XCUIApplication()
        app.launchArguments = ["--rift-ui-fixture", "--rift-ui-stream"]
        app.launch()
        let field = app.descendants(matching: .any)["messageInput"].firstMatch
        let last = app.descendants(matching: .any)["chatMessage-00000000-0000-0000-0000-000000000099"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(last.waitForExistence(timeout: 10))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("A reply while reading")
        assertTailIsVisible(in: app)
        attach("Rift-latest-above-keyboard")
        XCUIDevice.shared.orientation = .landscapeLeft
        assertTailIsVisible(in: app)
        attach("Rift-latest-landscape")
        XCUIDevice.shared.orientation = .portrait
        assertTailIsVisible(in: app)
    }
    private func assertTailIsVisible(in app: XCUIApplication) {
        var geometry = "No complete accessibility geometry"
        let visible = NSPredicate { _, _ in
            let last = app.descendants(matching: .any)["chatMessage-00000000-0000-0000-0000-000000000099"].firstMatch
            let field = app.descendants(matching: .any)["messageInput"].firstMatch
            let scroll = app.scrollViews["chatScrollView"]
            let keyboard = app.keyboards.firstMatch
            guard last.exists, field.exists, scroll.exists, keyboard.exists else { return false }
            let reply = last.frame, composer = field.frame, viewport = scroll.frame, keys = keyboard.frame
            geometry = "reply=\(reply), composer=\(composer), viewport=\(viewport), keyboard=\(keys), orientation=\(XCUIDevice.shared.orientation.rawValue)"
            guard !reply.isEmpty, !composer.isEmpty, !viewport.isEmpty, !keys.isEmpty else { return false }
            // XCTest can retain portrait screen coordinates during rotation.
            // Project onto the keyboard-facing axis instead of assuming that
            // screen-coordinate +Y is always visually down. In either space,
            // the reply tail must be inside the viewport and before the composer,
            // and the entire text field must remain before the keyboard.
            if keys.width >= keys.height {
                if keys.midY >= viewport.midY {
                    return reply.maxY > viewport.minY && reply.maxY <= min(viewport.maxY + 2, composer.minY + 2) && composer.maxY <= keys.minY + 2
                }
                return reply.minY < viewport.maxY && reply.minY >= max(viewport.minY - 2, composer.maxY - 2) && composer.minY >= keys.maxY - 2
            }
            if keys.midX >= viewport.midX {
                return reply.maxX > viewport.minX && reply.maxX <= min(viewport.maxX + 2, composer.minX + 2) && composer.maxX <= keys.minX + 2
            }
            return reply.minX < viewport.maxX && reply.minX >= max(viewport.minX - 2, composer.maxX - 2) && composer.minX >= keys.maxX - 2
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: app)], timeout: 12)
        if result != .completed {
            let diagnostic = XCTAttachment(string: geometry + "\n\n" + app.debugDescription)
            diagnostic.name = "Rift-keyboard-geometry"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertEqual(result, .completed, "Latest reply tail must remain visible, not only the input field. " + geometry)
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
    func testVoiceModeOpensWithoutStartingMicrophone() {
        let app = XCUIApplication(); app.launch()
        let entry = app.buttons["openVoiceMode"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.navigationBars["Voice mode"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ready when you are"].exists)
        XCTAssertTrue(app.switches["Hands-free turns"].exists)
        XCTAssertEqual(app.alerts.count, 0, "Opening voice mode must not request microphone access")
        attach("Rift-voice-mode")
        app.navigationBars["Voice mode"].buttons["Done"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
