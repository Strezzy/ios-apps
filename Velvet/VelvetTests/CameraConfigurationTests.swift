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

    func testHighFrameRateRequiresExplicitSelectionAndDoesNotDisplace4K60() {
        let fast = VideoMode(width: 3840, height: 2160, fps: 120, codec: "hevc")
        let modes = [fast, highQuality, VideoMode.standard]
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: modes, retaining: nil, isFront: false), highQuality)
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: modes, retaining: fast, isFront: false), fast)
        XCTAssertEqual(CameraConfigurationPolicy.videoMode(in: [fast, .standard], retaining: nil, isFront: false), .standard)
        XCTAssertNil(CameraConfigurationPolicy.videoMode(in: [fast], retaining: nil, isFront: false))
        XCTAssertEqual(CameraConfigurationPolicy.captureCodecs(width: 3840, height: 2160, fps: 120), ["hevc"])
    }

    func testProcessedVideoPathDoesNotAcceptBayerOrUnrelatedPixelFormats() {
        XCTAssertTrue(CameraConfigurationPolicy.isProcessedVideoSource(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange))
        XCTAssertTrue(CameraConfigurationPolicy.isProcessedVideoSource(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange))
        XCTAssertFalse(CameraConfigurationPolicy.isProcessedVideoSource(kCVPixelFormatType_32BGRA))
        XCTAssertFalse(CameraConfigurationPolicy.isProcessedVideoSource(kCVPixelFormatType_14Bayer_RGGB))
        XCTAssertFalse(CameraConfigurationPolicy.isProcessedVideoSource(0))
    }

    func testVirtualPresetMappingUsesActualNativeSwitchFactors() {
        XCTAssertEqual(CameraConfigurationPolicy.nativeZoomFactors(constituentIDs: ["ultra", "wide", "tele"], switchFactors: [2, 8]),
                       ["ultra": 1, "wide": 2, "tele": 8])
        XCTAssertEqual(CameraConfigurationPolicy.nativeZoomFactors(constituentIDs: ["wide", "tele"], switchFactors: [5]),
                       ["wide": 1, "tele": 5])
        for invalid in [[2.0], [2.0, .nan], [4.0, 2.0]] {
            XCTAssertTrue(CameraConfigurationPolicy.nativeZoomFactors(constituentIDs: ["ultra", "wide", "tele"], switchFactors: invalid).isEmpty)
        }
    }

    func testFocusCoordinatesRejectInvalidValuesAndClampPreviewEdges() {
        XCTAssertEqual(CameraConfigurationPolicy.clampedFocusPoint(CGPoint(x: -0.1, y: 1.2)), CGPoint(x: 0, y: 1))
        XCTAssertEqual(CameraConfigurationPolicy.clampedFocusPoint(CGPoint(x: 0.3, y: 0.7)), CGPoint(x: 0.3, y: 0.7))
        XCTAssertNil(CameraConfigurationPolicy.clampedFocusPoint(CGPoint(x: CGFloat.nan, y: 0)))
        XCTAssertNil(CameraConfigurationPolicy.clampedFocusPoint(CGPoint(x: 0, y: CGFloat.infinity)))
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
        controller.focus(at: CGPoint(x: 0.5, y: 0.5))
        XCTAssertFalse(controller.isReady)
        XCTAssertFalse(controller.isConfiguring)
        XCTAssertFalse(controller.isVideoMode)
        XCTAssertFalse(controller.isRecording)
        XCTAssertFalse(controller.session.isRunning)
        XCTAssertFalse(controller.isLensTransitioning)
        XCTAssertEqual(controller.focusState, .idle)
        XCTAssertNil(controller.focusPoint)
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
            let transform = try await recordedTrackProperties(angle: angle).transform
            let radians = angle * .pi / 180
            XCTAssertEqual(transform.a, cos(radians), accuracy: 0.001)
            XCTAssertEqual(transform.b, sin(radians), accuracy: 0.001)
            XCTAssertEqual(transform.c, -sin(radians), accuracy: 0.001)
            XCTAssertEqual(transform.d, cos(radians), accuracy: 0.001)
        }
    }

    func testEncryptedMoviePreserves120FrameTimeline() async throws {
        let properties = try await recordedTrackProperties(angle: 0, fps: 120)
        XCTAssertEqual(properties.frameRate, 120, accuracy: 1)
    }

    private func recordedTrackProperties(angle: CGFloat, fps: Int = 30) async throws -> (transform: CGAffineTransform, frameRate: Float) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ProtectedFiles.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let key = VaultCrypto.randomKey()
        let session = VaultSession()
        let writer = VaultVideoWriter(id: id, key: key, wrappedKey: Data(), directory: directory,
                                      session: session, fileExtension: "mp4", width: 320, height: 240)
        let recorder = try SegmentedVideoRecorder(vaultWriter: writer,
            mode: VideoMode(width: 320, height: 240, fps: fps, codec: "h264"), audio: false, rotationAngle: angle)
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
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                presentationTimeStamp: CMTime(value: Int64(10 * fps + frame), timescale: CMTimeScale(fps)), decodeTimeStamp: .invalid)
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
        let transform = try await track.load(.preferredTransform)
        let frameRate = try await track.load(.nominalFrameRate)
        return (transform, frameRate)
    }
}
