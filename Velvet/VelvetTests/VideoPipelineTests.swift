import XCTest
import AVFoundation
import CryptoKit
@testable import Velvet

final class VideoPipelineTests: XCTestCase {
    /// Exercises real H.264 encoding, AVAssetWriter segment callbacks, authenticated
    /// storage, bounded random access and AVFoundation's custom URL reader without
    /// a camera, a microphone, or a plaintext movie on disk.
    func testSyntheticMovieRoundTripThroughEncryptedResourceLoader() async throws {
        executionTimeAllowance = 45
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ProtectedFiles.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let itemID = UUID()
        let key = VaultCrypto.randomKey()
        let session = VaultSession()
        let writer = VaultVideoWriter(id: itemID, key: key, wrappedKey: Data(), directory: directory,
            session: session, fileExtension: "mp4", width: 320, height: 240)
        let recorder = try SegmentedVideoRecorder(vaultWriter: writer,
            mode: VideoMode(width: 320, height: 240, fps: 30, codec: "h264"), audio: false, rotationAngle: 0)
        let pixelBuffer = try makePixelBuffer()
        var formatDescription: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription), noErr)
        let format = try XCTUnwrap(formatDescription)
        for frame in 0..<90 {
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(value: Int64(300 + frame), timescale: 30), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            XCTAssertEqual(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing,
                sampleBufferOut: &sample), noErr)
            try recorder.append(XCTUnwrap(sample), isVideo: true)
            // Give the real-time encoder bounded opportunity to consume input.
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let duration: Double = try await withCheckedThrowingContinuation { continuation in
            recorder.finish { continuation.resume(with: $0) }
        }
        XCTAssertGreaterThan(duration, 2)
        let finished = try writer.prepareToCommit()
        let encryptedManifest = try ProtectedFiles.read(directory.appendingPathComponent(finished.manifest.filename), maximumBytes: 1_048_576)
        let manifestData = try VaultCrypto.open(encryptedManifest, key: key, domain: "video.manifest", assetID: itemID)
        let manifest = try JSONDecoder().decode(VaultVideoManifest.self, from: manifestData)
        XCTAssertGreaterThanOrEqual(manifest.segments.count, 2)
        let reader = try VaultVideoReader(manifest: manifest, directory: directory, key: key, session: session)
        let header = try reader.read(offset: 0, length: 12)
        XCTAssertEqual(String(data: header.subdata(in: 4..<8), encoding: .ascii), "ftyp")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.allSatisfy { $0.pathExtension == "vlt" })
        for segment in manifest.segments {
            let ciphertext = try ProtectedFiles.read(VaultVideoWriter.segmentURL(directory: directory, index: segment.sequence),
                maximumBytes: VaultVideoWriter.maximumSegmentBytes + 64)
            XCTAssertNotEqual(ciphertext.prefix(12), header.prefix(12))
        }
        let playback = SecureVideoPlayback(reader: reader)
        defer { playback.invalidate() }
        let asset = try XCTUnwrap(playback.player.currentItem?.asset)
        let playable = try await asset.load(.isPlayable)
        XCTAssertTrue(playable)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
        let movieDuration = try await asset.load(.duration)
        XCTAssertGreaterThan(movieDuration.seconds, 2)
        session.revoke()
        XCTAssertThrowsError(try reader.read(offset: 0, length: 12))
    }

    func testEmptyRecordingNeverCommits() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ProtectedFiles.createDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = VaultVideoWriter(id: UUID(), key: VaultCrypto.randomKey(), wrappedKey: Data(), directory: directory,
            session: VaultSession(), fileExtension: "mp4", width: 320, height: 240)
        let recorder = try SegmentedVideoRecorder(vaultWriter: writer,
            mode: VideoMode(width: 320, height: 240, fps: 30, codec: "h264"), audio: false, rotationAngle: 0)
        let outcome: Result<Double, Error> = await withCheckedContinuation { continuation in
            recorder.finish { continuation.resume(returning: $0) }
        }
        guard case .failure = outcome else { return XCTFail("Empty recording was accepted") }
        XCTAssertThrowsError(try writer.prepareToCommit())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer), kCVReturnSuccess)
        let pixelBuffer = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        if let address = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(address, 48, CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer))
        }
        return pixelBuffer
    }
}
