#if DEBUG
import Foundation
import UIKit

/// UI-test content only; not compiled into the distributed app. Uses a separate
/// temporary data directory and is never substituted for model inference.
@MainActor enum DebugChatFixture {
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let lastID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
    static func reply(in model: AppModel, index: Int) {
        model.generating = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            model.conversations[index].messages.append(.init(role: "assistant", content: "Finished test reply."))
            model.generating = false
        }
    }
    static func install(in model: AppModel) {
        if ProcessInfo.processInfo.arguments.contains("--rift-ui-navigation") {
            model.installed = ["A", "B"].map { name in
                InstalledModel(id: "fixture-" + name, name: "Navigation sample " + name,
                    filename: "fixture-" + name + ".gguf", bytes: 1, sha256: "", architecture: "test", importedAt: Date())
            }
            model.selectedModelID = model.installed[0].id
            model.conversations = [Conversation(title: "Drawer sample", messages: [.init(role: "user", content: "Saved conversation")])]
            model.activeChatID = nil
            if ProcessInfo.processInfo.arguments.contains("--rift-ui-attachment"), let storage = model.storage {
                try? "A local attachment for the composer check.".write(to: storage.root.appendingPathComponent("Attachment sample.txt"), atomically: true, encoding: .utf8)
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--rift-ui-short-stream") {
            let chat = Conversation(title: "Short layout test", messages: [
                .init(id: firstID, role: "user", content: "Hey"),
                .init(id: lastID, role: "assistant", content: "", modelName: "Layout sample")
            ])
            model.conversations = [chat]; model.activeChatID = chat.id; model.generating = true
            model.status = "Reading conversation"
            Task { @MainActor in
                // The UI check inspects the pending bubble before tapping the
                // composer. Waiting for that real event avoids launch-time races.
                for await _ in NotificationCenter.default.notifications(named: UIResponder.keyboardDidShowNotification) { break }
                guard model.generating else { return }
                model.status = "Writing reply"
                for word in "Hey! I am here. This short reply grows a few words at a time while the conversation stays anchored in place. There is room to breathe, even as the last words arrive.".split(separator: " ") {
                    guard model.generating else { return }
                    model.conversations[0].messages[1].content += (model.conversations[0].messages[1].content.isEmpty ? "" : " ") + word
                    try? await Task.sleep(for: .milliseconds(250))
                }
                model.generating = false
            }
            return
        }
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
