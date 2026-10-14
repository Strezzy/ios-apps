import XCTest
import SwiftUI
import AVFoundation
@testable import Rift

final class VoiceAndEffectsTests: XCTestCase {
    func testSixDistinctStylesRemainAvailable() {
        XCTAssertEqual(Set(ReplyAnimationStyle.allCases.map(\.rawValue)).count, 6)
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
        XCTAssertFalse(controller.handsFree)
        XCTAssertEqual(prior, AVAudioApplication.shared.recordPermission)
        controller.pause(); controller.close()
        XCTAssertEqual(controller.phase, .idle)
    }
    func testUsageDescriptionsArePackaged() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription"))
    }
}
