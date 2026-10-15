import XCTest
import SwiftUI
import AVFoundation
@testable import Rift

final class VoiceAndEffectsTests: XCTestCase {
    func testNineDistinctStylesRemainAvailable() {
        XCTAssertEqual(Set(ReplyAnimationStyle.allCases.map(\.rawValue)).count, 9)
        XCTAssertEqual(ReplyAnimationStyle.resolved("bounce"), .bounce)
        XCTAssertEqual(ReplyAnimationStyle.resolved("bloom"), .bloom)
    }
    func testExpressiveStylesRespectAccessibilityAndPower() {
        for style in ReplyAnimationStyle.allCases where style.isExpressive {
            XCTAssertEqual(style.effective(reduceMotion: true, lowPower: false, voiceOver: false), .fade)
            XCTAssertEqual(style.effective(reduceMotion: false, lowPower: true, voiceOver: false), .fade)
            XCTAssertEqual(style.effective(reduceMotion: false, lowPower: false, voiceOver: true), .instant)
            XCTAssertEqual(ReplyGlyphFrame.at(age: style.duration + 0.001, style: style), .at(age: 1, style: .instant))
        }
    }
    func testAnimatedFramesAreFiniteAndBounded() {
        for style in ReplyAnimationStyle.allCases {
            for age in stride(from: -0.1, through: 1.0, by: 0.005) {
                let frame = ReplyGlyphFrame.at(age: age, style: style)
                XCTAssertTrue([frame.opacity, frame.scale, frame.blur, frame.rotation, frame.sparkle].allSatisfy(\.isFinite))
                XCTAssertTrue((0...1).contains(frame.opacity))
                XCTAssertTrue((0.4...1.5).contains(frame.scale))
            }
        }
    }
    func testVoiceCancellationInvalidatesOlderCallbacks() {
        var turn = VoiceTurnToken()
        let old = turn.id
        XCTAssertTrue(turn.accepts(old))
        let current = turn.renew()
        XCTAssertFalse(turn.accepts(old))
        XCTAssertTrue(turn.accepts(current))
    }
    func testSilenceNeverAutoSubmitsUnspokenTurn() {
        var gate = VoiceSilenceGate()
        for i in 0..<100 { gate.observe(decibels: -80, elapsed: Double(i) / 10) }
        XCTAssertFalse(gate.heardSpeech)
        XCTAssertFalse(gate.shouldFinish(elapsed: 12, handsFree: true))
        XCTAssertTrue(gate.shouldFinish(elapsed: 45, handsFree: false))
    }
    func testHandsFreeRequiresSpeechAndPause() {
        var gate = VoiceSilenceGate()
        for i in 1...5 { gate.observe(decibels: -20, elapsed: Double(i) / 10) }
        XCTAssertFalse(gate.shouldFinish(elapsed: 0.6, handsFree: true))
        XCTAssertTrue(gate.shouldFinish(elapsed: 2, handsFree: true))
        XCTAssertFalse(gate.shouldFinish(elapsed: 2, handsFree: false))
    }
    func testSpeechExcludesThinkingCodeAndLinkDestination() {
        let raw = "<think>Hidden reasoning</think>**Hello** [friend](https://private.example)\n```swift\nsecret()\n```"
        let spoken = VoiceText.spoken(raw)
        XCTAssertTrue(spoken.contains("Hello friend"))
        XCTAssertFalse(spoken.contains("Hidden reasoning"))
        XCTAssertFalse(spoken.contains("private.example"))
        XCTAssertFalse(spoken.contains("secret"))
        XCTAssertEqual(VoiceText.spoken("<think>still thinking"), "")
    }
    func testSpeechChunkingDoesNotBreakUnicodeOrLoop() {
        let original = String(repeating: "日本語🌸hello ", count: 40)
        let chunks = VoiceText.chunks(original, maximum: 64)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 64 })
        XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace }, original.filter { !$0.isWhitespace })
        XCTAssertEqual(VoiceText.chunks(""), [])
    }
    @MainActor func testVoiceModeStartsIdleWithoutMicrophoneAuthorization() {
        let prior = AVAudioApplication.shared.recordPermission
        let controller = VoiceController(model: AppModel())
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(controller.handsFree)
        XCTAssertEqual(prior, AVAudioApplication.shared.recordPermission)
        controller.pause(); controller.close()
        XCTAssertEqual(controller.phase, .idle)
    }
    func testUsageDescriptionsArePackaged() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"))
    }
    func testEmberDefaultPreservesAllSavedChoices() {
        XCTAssertEqual(ReplyAnimationStyle.defaultStyle, .ember)
        XCTAssertEqual(ReplyAnimationStyle.resolved(""), .ember)
        for style in ReplyAnimationStyle.allCases {
            XCTAssertEqual(ReplyAnimationStyle.resolved(style.rawValue), style)
        }
    }
    func testCipherChangesGlyphsWithoutScramblingEmojiWhitespaceOrPunctuation() {
        XCTAssertTrue(CipherGlyph.canScramble("A"))
        XCTAssertTrue(CipherGlyph.canScramble("7"))
        for character in Array(" 🌸é日.\n") {
            XCTAssertFalse(CipherGlyph.canScramble(character))
        }
        XCTAssertNotEqual(CipherGlyph.symbol(seed: 3, progress: 0.1), CipherGlyph.symbol(seed: 3, progress: 0.3))
        XCTAssertEqual(CipherGlyph.symbol(seed: 8, progress: 0.2), CipherGlyph.symbol(seed: 8, progress: 0.2))
    }
    func testBestInstalledVoicePrioritizesLanguageQualityAndNaturalSpeech() {
        let choices: [VoiceChoice] = [
            .init(id: "alphabetically-first", language: "en-US", quality: 1),
            .init(id: "enhanced", language: "en-US", quality: 2),
            .init(id: "premium-uk", language: "en-GB", quality: 3),
            .init(id: "premium-us", language: "en-US", quality: 3),
            .init(id: "novelty", language: "en-US", quality: 3, novelty: true),
            .init(id: "french", language: "fr-FR", quality: 3)
        ]
        XCTAssertEqual(VoiceChoice.preferred(in: choices, language: "en_US"), "premium-us")
        XCTAssertEqual(VoiceChoice.preferred(in: choices, language: "en_GB"), "premium-uk")
        XCTAssertEqual(VoiceChoice.preferred(in: Array(choices.prefix(3)), language: "en_US"), "premium-uk")
        XCTAssertEqual(VoiceChoice.preferred(in: choices, language: "fr_FR"), "french")
        XCTAssertNil(VoiceChoice.preferred(in: choices, language: "ja_JP"))
        XCTAssertNil(VoiceChoice.preferred(in: [], language: "en_US"))
    }
    func testIsolatedNoiseDoesNotCountAsSpeech() {
        var gate = VoiceSilenceGate()
        for i in 0..<30 { gate.observe(decibels: i % 3 == 0 ? -20 : -70, elapsed: Double(i) / 10) }
        XCTAssertFalse(gate.heardSpeech)
        XCTAssertFalse(gate.shouldFinish(elapsed: 4, handsFree: true))
    }
    func testChunkingPrefersSentenceBoundaryAndRetainsWords() {
        let text = "This sentence has enough words to finish. Here is another sentence with a few more words to say."
        let chunks = VoiceText.chunks(text, maximum: 64)
        XCTAssertEqual(chunks.first, "This sentence has enough words to finish.")
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertGreaterThan(VoiceText.pause(after: "Done."), VoiceText.pause(after: "continued"))
    }
    @MainActor func testClosingBeforeAutomaticStartupCannotRecord() async {
        let controller = VoiceController(model: AppModel())
        controller.close()
        await controller.open()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.level, 0)
        XCTAssertEqual(controller.handsFree, (UserDefaults.standard.object(forKey: "rift.voiceHandsFree") as? Bool) ?? true)
    }
    @MainActor func testPausingDuringSetupStillFinishesAssetCheckWithoutStartingMicrophone() async {
        let speech = SuspendedSpeechService()
        let controller = VoiceController(model: AppModel(), speech: speech)
        let opening = Task { await controller.open() }
        await speech.waitForCheck()
        controller.pause()
        await speech.finishCheck()
        await opening.value
        XCTAssertEqual(controller.assets, .ready)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.error, "Paused startup must not attempt a voice turn")
        controller.close()
    }
    @MainActor func testDismissalDuringSetupCannotRestartSession() async {
        let speech = SuspendedSpeechService()
        let controller = VoiceController(model: AppModel(), speech: speech)
        let opening = Task { await controller.open() }
        await speech.waitForCheck()
        controller.close()
        await speech.finishCheck()
        await opening.value
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.handsFree, (UserDefaults.standard.object(forKey: "rift.voiceHandsFree") as? Bool) ?? true)
    }
    @MainActor func testOpeningAutomaticallyAttemptsTurnOnceAssetsAreReady() async {
        let speech = SuspendedSpeechService()
        let controller = VoiceController(model: AppModel(), speech: speech)
        let opening = Task { await controller.open() }
        await speech.waitForCheck()
        await speech.finishCheck()
        await opening.value
        // This fresh model is not bootstrapped. The turn guard proves open() tried
        // to listen automatically without requesting permission before readiness.
        XCTAssertEqual(controller.assets, .ready)
        XCTAssertTrue(controller.error?.contains("Choose and download a chat model") == true)
        XCTAssertEqual(controller.phase, .idle)
        controller.close()
    }
}

private actor SuspendedSpeechService: VoiceSpeechService {
    private var check: CheckedContinuation<SpeechAssetState, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func languages() -> [String] { ["en_US"] }
    func state(language: String) async -> SpeechAssetState {
        await withCheckedContinuation { continuation in
            check = continuation
            waiter?.resume(); waiter = nil
        }
    }
    func waitForCheck() async {
        if check != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishCheck() { check?.resume(returning: .ready); check = nil }
    func install(language: String) async throws {}
    func cancel() async {}
    func transcribe(file: URL, language: String) async throws -> String { "" }
}
