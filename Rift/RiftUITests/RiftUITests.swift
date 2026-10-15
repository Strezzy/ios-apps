import XCTest

final class RiftUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }
    func testDrawerRevealSelectionAndSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--rift-ui-fixture", "--rift-ui-navigation"]
        app.launch()
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["More options"].exists)
        app.buttons["Chat history"].tap()
        XCTAssertTrue(app.navigationBars["Conversations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["drawerSettings"].isHittable)
        attach("Rift-left-underlay")
        app.buttons.containing(.staticText, identifier: "Drawer sample").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Saved conversation"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["drawerSettings"].waitForExistence(timeout: 5))
        app.buttons["Close conversations"].tap()
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 5))
        app.buttons["Chat history"].tap()
        app.buttons["drawerSettings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Manage Models"].exists)
        attach("Rift-drawer-settings")
    }
    func testDownloadedPickerAndMorphingComposer() {
        let app = XCUIApplication()
        app.launchArguments = ["--rift-ui-fixture", "--rift-ui-navigation"]
        app.launch()
        let picker = app.buttons["modelPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["openVoiceMode"].exists)
        let composer = app.descendants(matching: .any)["composerBar"].firstMatch
        XCTAssertEqual(composer.frame.width, (app.frame.width - 24) * 0.8, accuracy: 4)
        XCTAssertGreaterThanOrEqual(composer.frame.height, 55)
        XCTAssertEqual(composer.frame.midX, app.frame.midX, accuracy: 3)
        let field = app.descendants(matching: .any)["messageInput"].firstMatch
        field.tap(); field.typeText("Hey")
        XCTAssertTrue(app.buttons["sendMessage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["openVoiceMode"].exists)
        attach("Rift-compact-send-composer")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        XCTAssertTrue(app.buttons["openVoiceMode"].waitForExistence(timeout: 5))
        picker.tap()
        XCTAssertTrue(app.buttons["Navigation sample B"].waitForExistence(timeout: 5))
        attach("Rift-downloaded-model-menu")
        app.buttons["Navigation sample B"].tap()
        XCTAssertTrue(picker.label.contains("Navigation sample B"))
        picker.tap(); app.buttons["Manage Models"].tap()
        XCTAssertTrue(app.staticTexts["Choose your AI"].waitForExistence(timeout: 5))
    }
    func testWelcomeAndModelPicker() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["modelPicker"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["emptyChatMark"].firstMatch.exists)
        attach("Rift-chat")
        app.buttons["modelPicker"].tap(); app.buttons["Manage Models"].tap()
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
    func testEmptyChatShowsOnlyCenteredMarkAndNewFooter() {
        let app = XCUIApplication(); app.launch()
        let mark = app.descendants(matching: .any)["emptyChatMark"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["A little space to think."].exists)
        XCTAssertFalse(app.staticTexts["Your conversation. Your phone."].exists)
        XCTAssertEqual(app.staticTexts["chatFooter"].label, "Unrestricted On-device AI")
        let composer = app.descendants(matching: .any)["composerBar"].firstMatch
        let top = app.navigationBars.firstMatch.frame.maxY
        XCTAssertEqual(mark.frame.midX, app.frame.midX, accuracy: 3)
        XCTAssertEqual(mark.frame.midY, (top + composer.frame.minY) / 2, accuracy: 16)
        attach("Rift-quiet-empty-chat")
        app.buttons["New chat"].tap()
        XCTAssertTrue(mark.exists)
        XCTAssertEqual(app.staticTexts["chatFooter"].label, "Unrestricted On-device AI")
    }
    func testShortBubbleTypingDotsAndStreamingStayAnchored() {
        let app = XCUIApplication()
        app.launchArguments = ["--rift-ui-fixture", "--rift-ui-short-stream"]
        app.launch()
        let scroll = app.scrollViews["chatScrollView"]
        let sent = app.descendants(matching: .any)["sentMessageBubble-00000000-0000-0000-0000-000000000001"].firstMatch
        let last = app.descendants(matching: .any)["chatMessage-00000000-0000-0000-0000-000000000099"].firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        XCTAssertLessThan(sent.frame.width, 110, "Hey should fit a small bubble")
        XCTAssertEqual(sent.frame.maxX, scroll.frame.maxX - 20, accuracy: 3)
        // SwiftUI propagates the message container's identifier to this child.
        let dots = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Replying")).firstMatch
        attach("Rift-short-message-and-dots")
        if !dots.exists {
            let diagnostic = XCTAttachment(string: app.debugDescription)
            diagnostic.name = "Rift-pending-reply-accessibility"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertTrue(dots.exists)
        XCTAssertFalse(app.staticTexts["Reading conversation"].exists)
        let input = app.descendants(matching: .any)["messageInput"].firstMatch
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let initialY = sent.frame.minY
        var minimumY = initialY, maximumY = initialY
        let initialHeight = last.frame.height
        for _ in 0..<24 {
            Thread.sleep(forTimeInterval: 0.15)
            let y = sent.frame.minY
            minimumY = min(minimumY, y); maximumY = max(maximumY, y)
        }
        XCTAssertLessThanOrEqual(maximumY - minimumY, 2, "Short conversations must not bounce between top and bottom")
        XCTAssertGreaterThan(last.frame.height, initialHeight, "The fixture must actually grow while measured")
        XCTAssertFalse(app.staticTexts["Writing reply"].exists)
        XCTAssertEqual(app.staticTexts["chatFooter"].label, "Unrestricted On-device AI")
        attach("Rift-short-stream-stable")
    }
    func testSettingsDoesNotNeedAnAccount() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 10))
        app.buttons["Chat history"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Offline mode"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["privacyAlwaysLocal"].firstMatch.exists)
        attach("Rift-settings")
    }
    func testReplyStylesSwitchAndReplayWithoutAModel() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 10))
        app.buttons["Chat history"].tap(); app.buttons["Settings"].tap()
        let larger = app.buttons["Larger preview"]
        for _ in 0..<5 { if larger.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(larger.isHittable); larger.tap()
        XCTAssertTrue(app.navigationBars["Reply animation"].waitForExistence(timeout: 5))
        for style in ["bloom", "fade", "instant", "starlight", "wave", "bounce", "ember", "portal", "cipher"] {
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
            // One snapshot keeps this check atomic and avoids four separate
            // accessibility round trips while the simulator is rendering.
            guard let snapshot = try? sample.snapshot() else { return false }
            return !snapshot.frame.isEmpty &&
                snapshot.label.contains("Just a little room to think.") &&
                (snapshot.value as? String) == "Preview complete"
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: completed, object: app)], timeout: 20)
        XCTAssertEqual(result, .completed, "Visible selected-style preview must actually finish")
        XCTAssertTrue(app.descendants(matching: .any)["animationPreview-expanded"].firstMatch.isHittable)
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
        app.buttons["modelPicker"].tap(); app.buttons["Manage Models"].tap()
        XCTAssertTrue(app.buttons["family-Heretic"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Qwen3 14B · Compact"].exists)
        let more = app.buttons["sizes-Heretic"]
        if !more.isHittable { app.swipeUp() }
        more.tap()
        XCTAssertTrue(app.staticTexts["Qwen3 14B · Precision"].exists)
        attach("Rift-Heretic-sizes")
    }
    func testVoiceOrbStaysInsideChatAndCanCloseAndReopen() {
        let app = XCUIApplication(); app.launch()
        let entry = app.buttons["openVoiceMode"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        let close = app.buttons["closeVoiceMode"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let composer = app.descendants(matching: .any)["composerBar"].firstMatch
        XCTAssertTrue(composer.buttons["closeVoiceMode"].isHittable)
        XCTAssertTrue(app.buttons["voiceOrb"].exists)
        XCTAssertTrue(app.navigationBars["Rift"].exists)
        XCTAssertFalse(app.staticTexts["Preparing voice"].exists)
        XCTAssertFalse(app.buttons["voiceOptions"].exists)
        XCTAssertFalse(app.staticTexts["voiceStatus"].exists)
        XCTAssertFalse(app.switches["Hands-free turns"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach("Rift-clear-glass-orb")
        XCUIDevice.shared.orientation = .landscapeLeft
        let reachable = NSPredicate { _, _ in
            app.frame.width > app.frame.height && close.isHittable && app.buttons["voiceOrb"].exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: reachable, object: app)], timeout: 10), .completed)
        attach("Rift-glass-orb-landscape")
        close.tap()
        XCTAssertTrue(app.buttons["voiceOrb"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.buttons["voiceOrb"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["messageInput"].firstMatch.isHittable)
    }
    func testVoicePreferencesLiveInSettingsAndPersist() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["Chat history"].waitForExistence(timeout: 10))
        app.buttons["Chat history"].tap(); app.buttons["Settings"].tap()
        let link = app.buttons["voiceSettingsLink"]
        for _ in 0..<3 { if link.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
        XCTAssertTrue(app.navigationBars["Voice & sound"].waitForExistence(timeout: 5))
        let sound = app.switches["voiceActivationSound"]
        let haptics = app.switches["voiceHaptics"]
        let handsFree = app.switches["voiceHandsFree"]
        XCTAssertTrue(sound.isHittable && haptics.isHittable && handsFree.isHittable)
        let original = [sound.value as? String, haptics.value as? String, handsFree.value as? String]
        for control in [sound, haptics, handsFree] {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let changed = [sound.value as? String, haptics.value as? String, handsFree.value as? String]
        for (before, after) in zip(original, changed) { XCTAssertNotEqual(before, after) }
        XCTAssertEqual(app.alerts.count, 0)
        attach("Rift-voice-settings")
        app.navigationBars["Voice & sound"].buttons.firstMatch.tap()
        XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap()
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual([sound.value as? String, haptics.value as? String, handsFree.value as? String], changed)
        // Restore user-facing defaults after exercising persistence.
        for control in [sound, haptics, handsFree] {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIApplication().screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
