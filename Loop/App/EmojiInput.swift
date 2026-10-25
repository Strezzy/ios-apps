import SwiftUI
import UIKit

/// A normal, editable Unicode field backed by the real iOS keyboard. Prefer the
/// enabled Emoji input mode; if unavailable, keep the system keyboard and globe.
/// No filtering or scalar slicing: skin tones, flags and joined emoji stay intact.
struct EmojiInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField(frame: .zero)
        field.text = text
        field.placeholder = "Choose any emoji"
        field.font = .systemFont(ofSize: 32)
        field.textAlignment = .center
        field.textColor = .label
        field.backgroundColor = .secondarySystemGroupedBackground
        field.layer.cornerRadius = 13
        field.clipsToBounds = true
        field.tintColor = .systemTeal
        field.keyboardType = .default
        field.returnKeyType = .done
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.accessibilityLabel = "Emoji"
        field.accessibilityHint = "Enter any emoji. The globe key switches keyboards."
        field.accessibilityIdentifier = "overlayContent"

        let accessory = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        accessory.autoresizingMask = [.flexibleWidth]
        let done = UIBarButtonItem(title: "Done", style: .done, target: context.coordinator,
                                   action: #selector(Coordinator.done))
        done.accessibilityLabel = "Done choosing emoji"
        done.accessibilityIdentifier = "emojiKeyboardDone"
        accessory.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        field.inputAccessoryView = accessory
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        // User typing already matches the binding. Avoid resetting selection or
        // interrupting a composed-character input session during other edits.
        if field.text != text, field.markedTextRange == nil { field.text = text }
        context.coordinator.synchronizeFocus()
    }

    static func dismantleUIView(_ field: EmojiTextField, coordinator: Coordinator) {
        coordinator.field = nil
        field.delegate = nil
        field.resignFirstResponder()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiInput
        weak var field: UITextField?
        private var focusUpdateScheduled = false

        init(_ parent: EmojiInput) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            done()
            return false
        }

        @objc func done() {
            parent.isFocused = false
            field?.resignFirstResponder()
        }

        func synchronizeFocus() {
            guard let field, field.isFirstResponder != parent.isFocused, !focusUpdateScheduled else { return }
            focusUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.focusUpdateScheduled = false
                guard let field = self.field else { return }
                if self.parent.isFocused {
                    if !field.isFirstResponder { field.becomeFirstResponder() }
                } else if field.isFirstResponder {
                    field.resignFirstResponder()
                }
            }
        }
    }
}

final class EmojiTextField: UITextField {
    override var textInputContextIdentifier: String? { "Loop.emoji" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
