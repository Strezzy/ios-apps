import XCTest
import AVFoundation
@testable import Rift

private actor VoiceInventoryGate {
    private var continuation: CheckedContinuation<[AVSpeechSynthesisVoice], Never>?
    private var started: CheckedContinuation<Void, Never>?
    func load() async -> [AVSpeechSynthesisVoice] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(_ voices: [AVSpeechSynthesisVoice]) { continuation?.resume(returning: voices); continuation = nil }
}
private actor PatchSpeech: VoiceSpeechService {
    func languages() async -> [String] { ["en_US"] }
    func state(language: String) async -> SpeechAssetState { .ready }
    func install(language: String) async throws {}
    func cancel() async {}
    func transcribe(file: URL, language: String) async throws -> String { "" }
}
final class VoicePatchTests: XCTestCase {
    @MainActor func testStartupWaitsForInstalledVoiceAndHonorsSelection() async throws {
        let gate = VoiceInventoryGate()
        let installed = try XCTUnwrap(AVSpeechSynthesisVoice(language: "en-US"))
        let oldID = UserDefaults.standard.object(forKey: "rift.voiceID")
        defer { UserDefaults.standard.set(oldID, forKey: "rift.voiceID") }
        let controller = VoiceController(model: AppModel(), speech: PatchSpeech(), voiceInventory: { await gate.load() })
        controller.voiceID = installed.identifier
        var completed = false
        let loading = Task { await controller.load(); completed = true }
        await gate.waitUntilStarted()
        XCTAssertFalse(completed)
        XCTAssertNil(controller.error)
        XCTAssertTrue(controller.voices.isEmpty)
        await gate.finish([installed])
        await loading.value
        XCTAssertEqual(controller.chosenVoice?.identifier, installed.identifier)
        XCTAssertEqual(controller.assets, .ready)
        controller.close()
    }
    @MainActor func testCloseDuringVoiceLookupIgnoresLateResult() async {
        let gate = VoiceInventoryGate()
        let controller = VoiceController(model: AppModel(), speech: PatchSpeech(), voiceInventory: { await gate.load() })
        let opening = Task { await controller.open() }
        await gate.waitUntilStarted()
        controller.close()
        await gate.finish([])
        await opening.value
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.voices.isEmpty)
        XCTAssertNil(controller.error)
    }
    func testPersonalityMigrationPreservesCustomInstructions() throws {
        let name = "Rift-personality-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(RiftPersonality.legacyPrompt, forKey: "rift.systemPrompt")
        RiftPersonality.migrate(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "rift.systemPrompt"), RiftPersonality.defaultPrompt)
        defaults.set("My custom instructions", forKey: "rift.systemPrompt")
        RiftPersonality.migrate(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: "rift.systemPrompt"), "My custom instructions")
    }
}
