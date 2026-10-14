import XCTest
import AVFoundation
import CoreImage
@testable import LumaLift

final class LumaLiftTests: XCTestCase {
    func testSettingsAreIndependent() throws {
        var settings = EnhanceSettings()
        settings.fps = 60
        try settings.validate(width: 1920, height: 1080, sourceFPS: 30)
        XCTAssertEqual(settings.scale, 1)
        XCTAssertTrue(settings.enhance)
        settings.enhance = false
        XCTAssertFalse(settings.usesRestoration)
        settings.scale = 2
        XCTAssertTrue(settings.usesRestoration)
        try settings.validate(width: 1920, height: 1080, sourceFPS: 30)
    }
    func testOutputAndMotionLimits() throws {
        var settings = EnhanceSettings()
        settings.scale = 4
        XCTAssertThrowsError(try settings.validate(width: 1920, height: 1080, sourceFPS: 30))
        settings.scale = 1; settings.fps = 60
        XCTAssertThrowsError(try settings.validate(width: 3840, height: 2160, sourceFPS: 30))
        XCTAssertNoThrow(try settings.validate(width: 1080, height: 1920, sourceFPS: 30))
        settings.strength = .nan
        XCTAssertThrowsError(try settings.validate(width: 640, height: 480, sourceFPS: 30))
    }
    func testFrameClockAndArbitraryTimesteps() {
        var clock = FrameClock(fps: 60)
        let a = CMTime.zero, b = CMTime(value: 1, timescale: 24)
        clock.advance()
        XCTAssertEqual(FrameClock.fraction(at: clock.time, between: a, and: b), 0.4, accuracy: 0.00001)
        for _ in 1..<60 { clock.advance() }
        XCTAssertEqual(clock.time, CMTime(seconds: 1, preferredTimescale: 60))
    }
    func testTilesCoverEveryPixelExactlyOnce() {
        let width = 361, height = 183
        var visits = [UInt8](repeating: 0, count: width * height)
        for tile in TileRegion.regions(width: width, height: height) {
            for y in tile.y..<(tile.y + tile.height) {
                for x in tile.x..<(tile.x + tile.width) { visits[y * width + x] += 1 }
            }
        }
        XCTAssertTrue(visits.allSatisfy { $0 == 1 })
        XCTAssertGreaterThanOrEqual(TileRegion.padding, 34)
    }
    func testBundledCoreMLRestorationExecutes() throws {
        let processor = try FrameProcessor()
        let input = try sampleFrame(index: 0)
        var settings = EnhanceSettings()
        settings.scale = 2; settings.strength = 1
        let result = try processor.restore(input, settings: settings, control: WorkControl())
        XCTAssertEqual(CVPixelBufferGetWidth(result), 128)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 96)
    }
    func testBundledRIFERunsOnAppleRuntime() throws {
        let processor = try FrameProcessor()
        let a = try sampleFrame(index: 0), b = try sampleFrame(index: 2)
        let result = try processor.interpolate(a, b, fraction: 0.5)
        XCTAssertEqual(CVPixelBufferGetWidth(result), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 48)
        XCTAssertNotEqual(bytes(result), bytes(a), "Interpolation must not just duplicate the first input.")
        XCTAssertNotEqual(bytes(result), bytes(b), "Interpolation must not just duplicate the second input.")
    }
    func testFullEnhancementAnd60FPSExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let clip = try await ClipInfo.inspect(source)
        var settings = EnhanceSettings()
        settings.fps = 60; settings.scale = 2; settings.preserveAudio = false
        let output = root.appendingPathComponent("result.mov")
        let result = try await VideoEngine().export(clip: clip, settings: settings, output: output,
                                                     control: WorkControl(), progress: { _ in })
        XCTAssertEqual(result.frames, 8)
        XCTAssertEqual(result.sha256.count, 64)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let exported = try await ClipInfo.inspect(output)
        XCTAssertEqual(exported.width, 128)
        XCTAssertEqual(exported.height, 96)
        XCTAssertEqual(exported.fps, 60, accuracy: 0.1)
        XCTAssertEqual(exported.duration, clip.duration, accuracy: 0.04)
    }
    func testOriginalTimingAndCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let clip = try await ClipInfo.inspect(source)
        let settings = EnhanceSettings(enhance: false)
        let result = try await VideoEngine().export(clip: clip, settings: settings,
            output: root.appendingPathComponent("original.mov"), control: WorkControl(), progress: { _ in })
        XCTAssertEqual(result.frames, 4)
        let stopped = WorkControl(); stopped.cancel()
        let cancelledURL = root.appendingPathComponent("cancelled.mov")
        do {
            _ = try await VideoEngine().export(clip: clip, settings: settings, output: cancelledURL,
                                                control: stopped, progress: { _ in })
            XCTFail("Cancellation must not report success.")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledURL.path))
    }
    func testPortraitOrientationIsPreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let turn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 48, ty: 0)
        let source = try await makeVideo(at: root.appendingPathComponent("portrait.mov"), transform: turn)
        let clip = try await ClipInfo.inspect(source)
        let output = root.appendingPathComponent("result.mov")
        _ = try await VideoEngine().export(clip: clip, settings: EnhanceSettings(enhance: false),
            output: output, control: WorkControl(), progress: { _ in })
        let result = try await ClipInfo.inspect(output)
        XCTAssertEqual(result.displaySize.width, 48, accuracy: 0.01)
        XCTAssertEqual(result.displaySize.height, 64, accuracy: 0.01)
    }
    func testShortAudioDoesNotTruncateVideo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let silent = try await makeVideo(at: root.appendingPathComponent("silent.mov"))
        let wav = root.appendingPathComponent("audio.wav")
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        let samples = 320
        append(UInt32(36 + samples * 2)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(8000))
        append(UInt32(16000)); append(UInt16(2)); append(UInt16(16)); data.append(Data("data".utf8))
        append(UInt32(samples * 2))
        for i in 0..<samples { append(Int16(sin(Double(i) * 2 * .pi * 440 / 8000) * 10000)) }
        try data.write(to: wav)
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: wav)
        let composition = AVMutableComposition()
        let video = try await videoAsset.loadTracks(withMediaType: .video)[0]
        let audio = try await audioAsset.loadTracks(withMediaType: .audio)[0]
        let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try v.insertTimeRange(try await video.load(.timeRange), of: video, at: .zero)
        try a.insertTimeRange(try await audio.load(.timeRange), of: audio, at: CMTime(seconds: 0.02, preferredTimescale: 8000))
        let source = root.appendingPathComponent("source.mov")
        let mux = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await mux.export(to: source, as: .mov)
        let clip = try await ClipInfo.inspect(source)
        let output = root.appendingPathComponent("result.mov")
        let result = try await VideoEngine().export(clip: clip, settings: EnhanceSettings(enhance: false),
            output: output, control: WorkControl(), progress: { _ in })
        XCTAssertEqual(result.frames, 4)
        let exported = AVURLAsset(url: output)
        let tracks = try await exported.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let range = try await XCTUnwrap(tracks.first).load(.timeRange)
        XCTAssertEqual(range.start.seconds, 0.02, accuracy: 0.002)
        XCTAssertEqual(range.duration.seconds, 0.04, accuracy: 0.002)
    }
    private func bytes(_ buffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        var data = Data()
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            data.append(Data(bytes: CVPixelBufferGetBaseAddress(buffer)!.advanced(by: row * CVPixelBufferGetBytesPerRow(buffer)),
                             count: CVPixelBufferGetWidth(buffer) * 4))
        }
        return data
    }
    private func sampleFrame(index: Int) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(width: 64, height: 48)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let background = CIImage(color: CIColor(red: 0.18, green: 0.22, blue: 0.32)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
        let marker = CIImage(color: CIColor(red: 0.85, green: 0.48, blue: 0.71))
            .cropped(to: CGRect(x: 8 + index * 6, y: 12, width: 20, height: 20))
        context.render(marker.composited(over: background), to: buffer)
        return buffer
    }
    private func makeVideo(at url: URL, transform: CGAffineTransform = .identity) async throws -> URL {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 48,
            AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: 30, AVVideoAllowFrameReorderingKey: false]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        input.transform = transform
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for i in 0..<4 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertTrue(adaptor.append(try sampleFrame(index: i), withPresentationTime: CMTime(value: Int64(i), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 4, timescale: 30))
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
