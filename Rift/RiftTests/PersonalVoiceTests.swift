import XCTest
import AVFoundation
@testable import Rift

final class PersonalVoiceTests: XCTestCase {
    func testProfilesPersistAndDeleteWithoutUsingNamesAsPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = PersonalVoiceLibrary(root: root)
        let voice = try library.save(profile: Data(repeating: 0, count: 4096), name: "../../My voice")
        XCTAssertEqual(try PersonalVoiceLibrary(root: root).entries(), [voice])
        XCTAssertEqual(library.profileURL(voice.id).deletingLastPathComponent(), root)
        try library.delete(voice)
        XCTAssertEqual(try library.entries(), [])
        XCTAssertThrowsError(try library.save(profile: Data(repeating: 0, count: 13), name: "Bad"))
    }
    func testRecordingValidationAcceptsSpeechLengthAndRejectsSilenceAndLongClips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func wav(seconds: Double, amplitude: Float) throws -> URL {
            let url = root.appendingPathComponent(UUID().uuidString + ".wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
            let count = AVAudioFrameCount(seconds * 24_000)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            buffer.frameLength = count
            for i in 0..<Int(count) { buffer.floatChannelData![0][i] = amplitude * sin(Float(i) * 0.08) }
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            return url
        }
        XCTAssertNoThrow(try PersonalVoiceLibrary.validateRecording(wav(seconds: 3.5, amplitude: 0.15)))
        XCTAssertThrowsError(try PersonalVoiceLibrary.validateRecording(wav(seconds: 3.5, amplitude: 0)))
        XCTAssertThrowsError(try PersonalVoiceLibrary.validateRecording(wav(seconds: 11, amplitude: 0.15)))
    }
    @MainActor func testNeuralFailureReturnsQueuedTextForAppleFallback() async {
        let failed = expectation(description: "Apple receives pending phrases")
        let player = PocketReplyPlayer { _ in
            try await Task.sleep(for: .milliseconds(20))
            throw RiftFailure("Unavailable")
        }
        player.onFailure = { remaining, _ in
            XCTAssertEqual(remaining, ["First phrase.", "Second phrase."])
            XCTAssertFalse(player.active)
            failed.fulfill()
        }
        player.enqueue(["First phrase."], profile: nil)
        player.enqueue(["Second phrase."], profile: nil)
        player.finish()
        await fulfillment(of: [failed], timeout: 2)
        player.onFailure = nil
    }
    @MainActor func testCloseCancelsPendingNeuralStartupWithoutLateFallback() async {
        let player = PocketReplyPlayer { _ in
            try await Task.sleep(for: .milliseconds(100))
            throw RiftFailure("Should be cancelled")
        }
        player.onFailure = { _, _ in XCTFail("Closed playback must not restart Apple speech") }
        player.enqueue(["Hello."], profile: nil)
        player.stop()
        XCTAssertFalse(player.active)
        try? await Task.sleep(for: .milliseconds(150))
    }
}
