#if DEBUG
import Foundation

/// UI-test content only; not compiled into the distributed app. Uses a separate
/// temporary data directory and is never substituted for model inference.
@MainActor enum DebugChatFixture {
    static let lastID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    static func install(in model: AppModel) {
        var messages: [ChatMessage] = []
        for index in 0..<14 {
            messages.append(.init(role: index.isMultiple(of: 2) ? "user" : "assistant",
                content: "Layout sample \(index + 1). " + String(repeating: "This is local test content used to make a scrollable conversation. ", count: 4), modelName: "Layout sample"))
        }
        messages.append(.init(id: lastID, role: "assistant", content: "Latest reply stays above the keyboard.", modelName: "Layout sample"))
        let chat = Conversation(title: "Keyboard layout test", messages: messages)
        model.conversations = [chat]; model.activeChatID = chat.id
        guard ProcessInfo.processInfo.arguments.contains("--rift-ui-stream") else { return }
        model.generating = true
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
                for word in " New letters remain visible while the keyboard is open. The reply follows the smaller viewport, including the very last line.".split(separator: " ") {
                    guard model.generating else { return }
                    let index = model.conversations[0].messages.count - 1
                    model.conversations[0].messages[index].content += " " + word
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch { }
            model.generating = false
        }
    }
}
#endif
