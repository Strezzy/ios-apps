import XCTest
import AVFoundation
import UIKit
@testable import Velvet

final class CameraConfigurationTests: XCTestCase {
    private let highQuality = VideoMode(width: 3840, height: 2160, fps: 60, codec: "hevc")

    func testRearCameraDefaultsToSupported4K60() {
        let modes = [VideoMode.standard, VideoMode(width: 3840, height: 2160, fps: 30, codec: "hevc"), highQuality]
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: modes, retaining: nil, isFront: false), highQuality)
    }

    func testExplicitVideoChoiceSurvivesLensChangeWhenSupported() {
        let cinematic = VideoMode(width: 3840, height: 2160, fps: 24, codec: "hevc")
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: [cinematic, highQuality], retaining: cinematic, isFront: false), cinematic)
    }

    func testUnsupportedLensModeFallsBackToAnActualCapability() {
        let available = [VideoMode.standard, VideoMode(width: 1280, height: 720, fps: 60, codec: "h264")]
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: available, retaining: highQuality, isFront: false), .standard)
        XCTAssertNil(CameraConfigurationPolicy.videoMode(in: [], retaining: highQuality, isFront: false))
    }

    func testFrontCameraPreferenceDoesNotReplaceRememberedRearPreference() {
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: [.standard, highQuality], retaining: nil, isFront: true), .standard)
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: [.standard, highQuality], retaining: highQuality, isFront: false), highQuality)
    }

    func testLensLabelsDescribeRealNativeZoomAndDoNotRelabelFiveAsFour() {
        XCTAssertEqual(CameraConfigurationPolicy.zoomLabel(nativeFactor: 0.5), "0.5×")
        XCTAssertEqual(CameraConfigurationPolicy.zoomLabel(nativeFactor: 1), "1×")
        XCTAssertEqual(CameraConfigurationPolicy.zoomLabel(nativeFactor: 100.0 / 24.0), "4×")
        XCTAssertEqual(CameraConfigurationPolicy.zoomLabel(nativeFactor: 5), "5×")
        XCTAssertEqual(CameraConfigurationPolicy.zoomLabel(nativeFactor: .nan), "Tele")
    }

    func testPhysicalLandscapeDirectionsHaveDistinctCaptureAndGlyphAngles() throws {
        let left = try XCTUnwrap(CameraPhysicalOrientation.from(.landscapeLeft))
        let right = try XCTUnwrap(CameraPhysicalOrientation.from(.landscapeRight))
        XCTAssertEqual(left.captureDegrees, 0)
        XCTAssertEqual(left.controlDegrees, 90)
        XCTAssertEqual(right.captureDegrees, 180)
        XCTAssertEqual(right.controlDegrees, -90)
        XCTAssertEqual(CameraPhysicalOrientation.from(.portrait)?.captureDegrees, 90)
        XCTAssertEqual(CameraPhysicalOrientation.from(.portraitUpsideDown)?.captureDegrees, 270)
        for transient in [UIDeviceOrientation.unknown, .faceUp, .faceDown] {
            XCTAssertNil(CameraPhysicalOrientation.from(transient), "Transient readings must preserve the previous stable direction")
        }
    }

    func testHorizonAnglesUseMatchingQuarterTurnsForMoviePhotoAndThumbnail() {
        XCTAssertEqual(CameraPhysicalOrientation.quarterTurn(88), 90)
        XCTAssertEqual(CameraPhysicalOrientation.quarterTurn(181), 180)
        XCTAssertEqual(CameraPhysicalOrientation.quarterTurn(-89), 270)
        XCTAssertEqual(CameraPhysicalOrientation.quarterTurn(359), 0)
        XCTAssertEqual(CameraPhysicalOrientation.quarterTurn(.nan, fallback: 180), 180)
    }

    @MainActor
    func testLockedVaultCannotStartOrReconfigureCamera() async {
        let vault = VaultStore()
        let controller = CameraController(vault: vault)
        XCTAssertFalse(vault.isUnlocked)
        await controller.start()
        controller.setCaptureMode(video: true)
        controller.selectVideoMode(highQuality)
        await controller.startRecording()
        XCTAssertFalse(controller.isReady)
        XCTAssertFalse(controller.isConfiguring)
        XCTAssertFalse(controller.isVideoMode)
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.session.isRunning)
        controller.stop()
    }

    func testConfigurationCannotRunBeforeAuthorizedSessionStart() async {
        let engine = CaptureEngine()
        do {
            _ = try await engine.configure(video: true, preferredMode: highQuality)
            XCTFail("An inactive session accepted a mode change")
        } catch {
            XCTAssertFalse(engine.session.isRunning)
        }
    }

    /// The portrait shell must not force a portrait movie. The angle supplied at
    /// recording start is stored in the real encrypted movie's track metadata.
    func testEncryptedMoviePreservesPortraitAndLandscapeTransforms() async throws {
        for angle in [CGFloat(0), 90, 180] {
            let transform = try await recordedTransform(angle: angle)
            let radians = angle * .pi / 180
            XCTAssertEqual(transform.a, cos(radians), accuracy: 0.001)
            XCTAssertEqual(transform.b, sin(radians), accuracy: 0.001)
            XCTAssertEqual(transform.c, -sin(radians), accuracy: 0.001)
            XCTAssertEqual(transform.d, cos(radians), accuracy: 0.001)
        }
    }

    private func recordedTransform(angle: CGFloat) async throws -> CGAffineTransform {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ProtectedFiles.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let key = VaultCrypto.randomKey()
        let session = VaultSession()
        let writer = VaultVideoWriter(id: id, key: key, wrappedKey: Data(), directory: directory,
                                      session: session, fileExtension: "mp4", width: 320, height: 240)
        let recorder = try SegmentedVideoRecorder(vaultWriter: writer,
            mode: VideoMode(width: 320, height: 240, fps: 30, codec: "h264"), audio: false, rotationAngle: angle)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        if let address = CVPixelBufferGetBaseAddress(pixels) {
            memset(address, 0, CVPixelBufferGetBytesPerRow(pixels) * CVPixelBufferGetHeight(pixels))
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        var description: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixels, formatDescriptionOut: &description), noErr)
        let format = try XCTUnwrap(description)
        for frame in 0..<16 {
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(value: Int64(300 + frame), timescale: 30), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                imageBuffer: pixels, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample), noErr)
            try recorder.append(XCTUnwrap(sample), isVideo: true)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let _: Double = try await withCheckedThrowingContinuation { continuation in
            recorder.finish { continuation.resume(with: $0) }
        }
        let finished = try writer.prepareToCommit()
        let ciphertext = try ProtectedFiles.read(directory.appendingPathComponent(finished.manifest.filename), maximumBytes: 1_048_576)
        let manifest = try JSONDecoder().decode(VaultVideoManifest.self,
            from: VaultCrypto.open(ciphertext, key: key, domain: "video.manifest", assetID: id))
        let reader = try VaultVideoReader(manifest: manifest, directory: directory, key: key, session: session)
        let playback = SecureVideoPlayback(reader: reader)
        defer { playback.invalidate(); session.revoke() }
        let asset = try XCTUnwrap(playback.player.currentItem?.asset)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        return try await track.load(.preferredTransform)
    }
}
