import XCTest
import SwiftUI
import UIKit
@testable import Loop

final class EmojiInputTests: XCTestCase {
    @MainActor func testKeyboardEditsPreserveComposedEmojiThroughBinding() {
        var content = ""
        var focused = false
        let input = EmojiInput(text: Binding(get: { content }, set: { content = $0 }),
                               isFocused: Binding(get: { focused }, set: { focused = $0 }))
        let coordinator = input.makeCoordinator()
        let field = EmojiTextField(frame: CGRect(x: 0, y: 0, width: 280, height: 54))
        field.text = ""
        coordinator.field = field
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(EmojiInput.Coordinator.textChanged(_:)), for: .editingChanged)

        // Exercise the native text-input path and the app's editingChanged bridge.
        // Each value contains extended graphemes that scalar slicing would damage.
        let entries = ["👩🏽‍🚀", "🇺🇳", "❤️", "👨‍👩‍👧‍👦"]
        for entry in entries {
            field.insertText(entry)
            field.sendActions(for: .editingChanged)
        }
        XCTAssertEqual(content, entries.joined())
        XCTAssertEqual(content.count, entries.count)
    }

    @MainActor func testCoordinatorWritesToCurrentOverlayBinding() {
        var firstOverlay = "😎"
        var secondOverlay = "✨"
        var focused = false
        let focus = Binding(get: { focused }, set: { focused = $0 })
        let input = EmojiInput(text: Binding(get: { firstOverlay }, set: { firstOverlay = $0 }), isFocused: focus)
        let coordinator = input.makeCoordinator()
        let field = EmojiTextField(frame: CGRect(x: 0, y: 0, width: 280, height: 54))
        coordinator.field = field
        field.addTarget(coordinator, action: #selector(EmojiInput.Coordinator.textChanged(_:)), for: .editingChanged)

        // updateUIView refreshes this parent binding without rebuilding the field.
        coordinator.parent = EmojiInput(text: Binding(get: { secondOverlay }, set: { secondOverlay = $0 }), isFocused: focus)
        field.text = secondOverlay
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.insertText("👍🏾")
        field.sendActions(for: .editingChanged)

        XCTAssertEqual(firstOverlay, "😎", "Typing into another layer must not mutate the previous layer.")
        XCTAssertEqual(secondOverlay, "✨👍🏾")
        XCTAssertEqual(secondOverlay.count, 2)
    }
}
