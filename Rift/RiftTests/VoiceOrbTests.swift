import XCTest
import SwiftUI
import AVFoundation
@testable import Rift

final class VoiceOrbTests: XCTestCase {
    func testGlassOutlineFlowsAndStaysInsideItsFrame() {
        let frame = CGRect(x: 0, y: 0, width: 152, height: 152)
        let first = LiquidOrbShape(time: 0, energy: 0).path(in: frame)
        XCTAssertNotEqual(first, LiquidOrbShape(time: 1.7, energy: 0).path(in: frame))
        XCTAssertNotEqual(first, LiquidOrbShape(time: 0, energy: 1).path(in: frame))
        for t in stride(from: 0.0, to: 12.0, by: 0.2) {
            let path = LiquidOrbShape(time: t, energy: 1).path(in: frame)
            XCTAssertTrue(frame.contains(path.boundingRect))
            XCTAssertTrue(path.contains(CGPoint(x: 76, y: 76)))
        }
    }
    func testLiquidEntranceSettlesAndRespectsReducedMotion() {
        for age in stride(from: -0.1, through: 2.0, by: 0.02) {
            let frame = LiquidOrbEntrance(age: age, reduced: false)
            XCTAssertTrue((0.04...1.16).contains(frame.scale))
            XCTAssertLessThanOrEqual(abs(frame.squash), 0.22)
        }
        XCTAssertEqual(LiquidOrbEntrance(age: 2, reduced: false).scale, 1, accuracy: 0.001)
        XCTAssertEqual(LiquidOrbEntrance(age: 0, reduced: true).scale, 1)
        XCTAssertEqual(LiquidOrbEntrance(age: 0.1, reduced: true).squash, 0)
    }
    func testActivationCueIsPlayableShortAndHasHeadroom() throws {
        let data = VoiceActivationTone.waveData()
        let player = try AVAudioPlayer(data: data)
        XCTAssertEqual(player.duration, 0.36, accuracy: 0.001)
        XCTAssertEqual(player.numberOfChannels, 1)
        let bytes = Array(data.dropFirst(44))
        let samples = stride(from: 0, to: bytes.count, by: 2).map {
            Int(Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8))
        }
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 1000)
        XCTAssertLessThan(samples.map { abs($0) }.max() ?? 32767, 16000)
        XCTAssertEqual(samples.first, 0)
        XCTAssertLessThan(abs(samples.last ?? 100), 2)
    }
    @MainActor func testClosingDuringCuePreventsSpeechSetupAndMicrophoneStart() async {
        let key = "rift.voiceActivationSound", old = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        UserDefaults.standard.set(true, forKey: key)
        let cue = SuspendedActivationCue()
        let speech = ReadyOrbSpeechService()
        let controller = VoiceController(model: AppModel(), speech: speech, activationSound: cue)
        let prior = AVAudioApplication.shared.recordPermission
        let opening = Task { await controller.open(playActivationSound: true) }
        await cue.waitForPlayback()
        controller.close(); controller.close()
        XCTAssertEqual(cue.stops, 1, "Closing is idempotent, including during an exit transition")
        cue.finish()
        await opening.value
        let calls = await speech.checks
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.error)
        XCTAssertEqual(prior, AVAudioApplication.shared.recordPermission)
    }
    @MainActor func testMutedCueStillOpensVoiceNormally() async {
        let key = "rift.voiceActivationSound", old = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        UserDefaults.standard.set(false, forKey: key)
        let cue = SuspendedActivationCue()
        let controller = VoiceController(model: AppModel(), speech: ReadyOrbSpeechService(), activationSound: cue)
        await controller.open(playActivationSound: true)
        XCTAssertFalse(cue.started)
        XCTAssertEqual(controller.assets, .ready)
        XCTAssertTrue(controller.error?.contains("Choose and download a chat model") == true)
        controller.close()
    }
    @MainActor func testClosingKeepsHandsFreePreference() {
        let key = "rift.voiceHandsFree", old = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }
        for preference in [false, true] {
            let controller = VoiceController(model: AppModel())
            controller.handsFree = preference
            controller.close()
            let reopened = VoiceController(model: AppModel())
            XCTAssertEqual(reopened.handsFree, preference)
            reopened.close()
        }
    }
    @MainActor func testSettingsLoadsVoicesWithoutStartingATurn() async {
        let permission = AVAudioApplication.shared.recordPermission
        let controller = VoiceController(model: AppModel(), speech: ReadyOrbSpeechService())
        await controller.load()
        controller.pause() // Returning from a Settings picker can load the same controller again.
        await controller.load()
        XCTAssertEqual(controller.assets, .ready)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.error)
        XCTAssertEqual(permission, AVAudioApplication.shared.recordPermission)
        controller.close()
    }
}

@MainActor private final class SuspendedActivationCue: VoiceActivationPlaying {
    var started = false
    var stops = 0
    private var playback: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func play() async {
        started = true
        await withCheckedContinuation { continuation in
            playback = continuation; waiter?.resume(); waiter = nil
        }
    }
    func waitForPlayback() async {
        if started { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finish() { playback?.resume(); playback = nil }
    func stop() { stops += 1 }
}
private actor ReadyOrbSpeechService: VoiceSpeechService {
    private(set) var checks = 0
    func languages() -> [String] { ["en_US"] }
    func state(language: String) -> SpeechAssetState { checks += 1; return .ready }
    func install(language: String) async throws {}
    func cancel() async {}
    func transcribe(file: URL, language: String) async throws -> String { "" }
}
