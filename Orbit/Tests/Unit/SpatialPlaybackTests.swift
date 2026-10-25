import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore
import VideoToolbox
import XCTest
@testable import Orbit

final class SpatialPlaybackTests: XCTestCase {
    /// The fixture is Apple's real MV-HEVC recording, fetched and checksum-
    /// verified by CI. It is a test-bundle resource, never an app-bundle asset.
    @MainActor
    func testRealSpatialMovieDecodesBothEyesAndSeeks() async throws {
        executionTimeAllowance = 15
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "Spatial", withExtension: "mov") ??
            bundle.url(forResource: "Spatial", withExtension: "mov", subdirectory: "Fixtures"),
            "Build must fetch the checksum-verified Apple spatial fixture before XcodeGen."
        )
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaCharacteristic: .containsStereoMultiviewVideo)
        XCTAssertFalse(tracks.isEmpty, "The fixture must contain genuine stereo MV-HEVC metadata.")
        let track = try XCTUnwrap(tracks.first)
        let expectedTransform = try await track.load(.preferredTransform)

        #if targetEnvironment(simulator)
        try XCTSkipIf(!VTIsStereoMVHEVCDecodeSupported(),
                      "VideoToolbox explicitly reports MV-HEVC stereo decoding unavailable on this simulator. Physical-iPhone stereo playback remains unverified.")
        #else
        guard VTIsStereoMVHEVCDecodeSupported() else {
            XCTFail("The device does not support stereo MV-HEVC decoding.")
            return
        }
        #endif

        let controller = SpatialPlaybackController()
        defer { controller.close() }
        controller.isMuted = true
        controller.isLooping = false
        let deadline = CACurrentMediaTime() + 12
        await controller.load(url: url)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(controller.isSpatial)
        controller.play()

        let first = try await waitForFrame(controller, before: min(deadline, CACurrentMediaTime() + 7)) {
            $0.isSpatial && $0.right != nil
        }
        let right = try XCTUnwrap(first.right)
        XCTAssertGreaterThan(CVPixelBufferGetWidth(first.left), 0)
        XCTAssertEqual(CVPixelBufferGetWidth(first.left), CVPixelBufferGetWidth(right))
        XCTAssertEqual(CVPixelBufferGetHeight(first.left), CVPixelBufferGetHeight(right))
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(first.left), kCVPixelFormatType_32BGRA)
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(right), kCVPixelFormatType_32BGRA)
        XCTAssertNotEqual(Unmanaged.passUnretained(first.left).toOpaque(),
                          Unmanaged.passUnretained(right).toOpaque(),
                          "Both eye tags must resolve to independent decoded views.")
        XCTAssertTrue(first.presentationTime.isValid)
        XCTAssertTrue(first.presentationTime.seconds.isFinite)
        XCTAssertEqual(first.transform.a, expectedTransform.a, accuracy: 0.0001)
        XCTAssertEqual(first.transform.b, expectedTransform.b, accuracy: 0.0001)
        XCTAssertEqual(first.transform.c, expectedTransform.c, accuracy: 0.0001)
        XCTAssertEqual(first.transform.d, expectedTransform.d, accuracy: 0.0001)
        XCTAssertEqual(first.transform.tx, expectedTransform.tx, accuracy: 0.0001)
        XCTAssertEqual(first.transform.ty, expectedTransform.ty, accuracy: 0.0001)
        XCTAssertGreaterThan(abs(first.transform.a * first.transform.d - first.transform.b * first.transform.c), 0.1)

        // Both views above came from one AVPlayer tagged-buffer presentation,
        // rather than independently advancing decoder readers. A paused seek
        // must deliver a new synchronized pair at the selected movie time.
        controller.pause()
        let target = controller.duration * 0.6
        controller.seek(to: target)
        let afterSeek = try await waitForFrame(controller, before: deadline) {
            $0.isSpatial && abs($0.presentationTime.seconds - target) < 0.2
        }
        XCTAssertNotNil(afterSeek.right)
        XCTAssertEqual(afterSeek.presentationTime.seconds, target, accuracy: 0.2)
        XCTAssertEqual(controller.currentTime, target, accuracy: 0.2)
        XCTAssertFalse(controller.isPlaying)

        controller.close()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertFalse(controller.isSpatial)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertEqual(controller.currentTime, 0)
        XCTAssertNil(controller.frame(atHostTime: CACurrentMediaTime()))
    }

    /// Ordinary H.264 must stay flat even on a simulator without stereo decode.
    /// A tiny generated video avoids shipping a second media fixture.
    @MainActor
    func testMonoMovieStaysFlatAndCloses() async throws {
        executionTimeAllowance = 10
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orbit-Mono-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try await makeMonoFixture(at: url)
        let controller = SpatialPlaybackController()
        defer { controller.close() }
        controller.isMuted = true
        await controller.load(url: url)
        XCTAssertNil(controller.errorMessage)
        XCTAssertFalse(controller.isSpatial)
        controller.play()
        let frame = try await waitForFrame(controller, before: CACurrentMediaTime() + 4) { _ in true }
        XCTAssertFalse(frame.isSpatial)
        XCTAssertNil(frame.right, "A normal video must never be advertised as recorded stereo.")
        XCTAssertEqual(CVPixelBufferGetWidth(frame.left), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(frame.left), 64)
        controller.close()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.duration, 0)
        XCTAssertNil(controller.frame(atHostTime: CACurrentMediaTime()))
    }

    @MainActor
    private func waitForFrame(_ controller: SpatialPlaybackController, before deadline: CFTimeInterval,
                              matching predicate: (StereoVideoFrame) -> Bool) async throws -> StereoVideoFrame {
        while CACurrentMediaTime() < deadline {
            if let message = controller.errorMessage {
                XCTFail("Playback failed: \(message)")
                throw FixtureError.playbackFailed
            }
            if let frame = controller.frame(atHostTime: CACurrentMediaTime()), predicate(frame) { return frame }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("No matching video frame before the bounded deadline. Status: \(controller.depthStatus).")
        throw FixtureError.noFrame
    }

    @MainActor
    private func makeMonoFixture(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                          sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 64
        ])
        guard writer.canAdd(input) else { throw FixtureError.cannotEncode }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.cannotEncode }
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA,
                                        nil, &buffer)
        guard result == kCVReturnSuccess, let buffer else { throw FixtureError.cannotEncode }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let address = CVPixelBufferGetBaseAddress(buffer) {
            address.initializeMemory(as: UInt8.self, repeating: 128,
                                     count: CVPixelBufferGetBytesPerRow(buffer) * 64)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let deadline = CACurrentMediaTime() + 2
        for frame in 0..<12 {
            while !input.isReadyForMoreMediaData {
                guard CACurrentMediaTime() < deadline else {
                    writer.cancelWriting()
                    throw FixtureError.cannotEncode
                }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 12)) else {
                throw writer.error ?? FixtureError.cannotEncode
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.cannotEncode }
    }
}

private enum FixtureError: Error {
    case playbackFailed, noFrame, cannotEncode
}
