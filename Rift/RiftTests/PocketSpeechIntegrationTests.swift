import XCTest
import AVFoundation
import FluidAudio
@testable import Rift

/// One real voice-engine round trip; no chat model downloads or inference.
final class PocketSpeechIntegrationTests: XCTestCase {
    func testStreamsBeforeTextFinishesAndReloadsClonedVoiceOffline() async throws {
        executionTimeAllowance = 900
        let engine = PocketSpeechEngine.shared
        try await engine.install()
        XCTAssertTrue(ModelHub.offlineMode)
        let session = try await engine.session(profile: nil)
        session.enqueue("Hello. This is a recording of a calm and friendly voice, speaking clearly on this device.")
        var samples: [Float] = []
        var addedSecond = false
        var secondHeard = false
        for try await frame in session.frames {
            XCTAssertTrue(frame.samples.allSatisfy { $0.isFinite })
            samples += frame.samples
            if !addedSecond {
                // We have audible output before delivering the rest of the text.
                addedSecond = true
                session.enqueue("The next sentence arrives while the first is being spoken.")
                session.finish()
            }
            secondHeard = secondHeard || frame.utteranceIndex == 1
        }
        XCTAssertTrue(addedSecond); XCTAssertTrue(secondHeard)
        XCTAssertGreaterThan(samples.count, 72_000)
        XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.001)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = root.appendingPathComponent("reference.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        let count = min(samples.count, 120_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        for i in 0..<count { buffer.floatChannelData![0][i] = samples[i] }
        do { let file = try AVAudioFile(forWriting: recording, settings: format.settings); try file.write(from: buffer) }
        let library = PersonalVoiceLibrary(root: root.appendingPathComponent("voices"))
        let saved = try await engine.clone(recording: recording, name: "Round trip", library: library)
        XCTAssertEqual(try library.entries(), [saved])
        await engine.unload()
        let cloned = try await engine.session(profile: library.profileURL(saved.id))
        cloned.enqueue("My personal voice is saved locally."); cloned.finish()
        var clonedSamples = 0
        for try await frame in cloned.frames {
            XCTAssertTrue(frame.samples.allSatisfy { $0.isFinite })
            clonedSamples += frame.samples.count
        }
        XCTAssertGreaterThan(clonedSamples, 24_000)
        XCTAssertTrue(ModelHub.offlineMode)
        await engine.unload()
    }
}
