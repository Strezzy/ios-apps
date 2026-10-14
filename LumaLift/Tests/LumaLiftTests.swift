import XCTest
import AVFoundation
import AudioToolbox
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
        let pixels = bytes(result)
        XCTAssertTrue(stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 },
                      "Resizing restored tiles must not introduce transparent edges.")
    }
    func testZeroStrengthPreservesTileLayout() throws {
        let input = try makePixelBuffer(width: 358, height: 190)
        let base = CIImage(color: CIColor(red: 0.16, green: 0.30, blue: 0.50))
            .cropped(to: CGRect(x: 0, y: 0, width: 358, height: 190))
        let left = CIImage(color: CIColor(red: 0.85, green: 0.20, blue: 0.35))
            .cropped(to: CGRect(x: 0, y: 0, width: 110, height: 95))
        let right = CIImage(color: CIColor(red: 0.25, green: 0.80, blue: 0.15))
            .cropped(to: CGRect(x: 220, y: 115, width: 138, height: 75))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        context.render(right.composited(over: left.composited(over: base)), to: input,
                       bounds: CGRect(x: 0, y: 0, width: 358, height: 190),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        var settings = EnhanceSettings(); settings.strength = 0
        let output = try FrameProcessor().restore(input, settings: settings, control: WorkControl())
        let before = bytes(input), after = bytes(output)
        XCTAssertEqual(before.count, after.count)
        let maximumDifference = zip(before, after).map { abs(Int($0.0) - Int($0.1)) }.max() ?? 256
        XCTAssertLessThanOrEqual(maximumDifference, 3, "Tile composition must preserve orientation and color at zero strength.")
    }
    private func requirePhysicalMotion() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device test pending: hosted simulator MPSGraph GPU initialization is unsupported. This skip is recorded in the beta build report, never reported as an inference pass.")
        #else
        try FrameProcessor.requireMotionSupport()
        #endif
    }
    func testBundledRIFERunsOnAppleRuntime() throws {
        try requirePhysicalMotion()
        let processor = try FrameProcessor()
        let a = try sampleFrame(index: 0), b = try sampleFrame(index: 2)
        let result = try processor.interpolate(a, b, fraction: 0.5)
        XCTAssertEqual(CVPixelBufferGetWidth(result), 64)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 48)
        XCTAssertNotEqual(bytes(result), bytes(a), "Interpolation must not just duplicate the first input.")
        XCTAssertNotEqual(bytes(result), bytes(b), "Interpolation must not just duplicate the second input.")
    }
    func testFullEnhancementAnd60FPSExport() async throws {
        try requirePhysicalMotion()
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
    func testFullEnhancementAtOriginalFPS() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let clip = try await ClipInfo.inspect(source)
        var settings = EnhanceSettings(); settings.scale = 2
        let output = root.appendingPathComponent("restored.mov")
        let result = try await VideoEngine().export(clip: clip, settings: settings, output: output,
                                                     control: WorkControl(), progress: { _ in })
        XCTAssertEqual(result.frames, 4)
        XCTAssertEqual(result.sha256.count, 64)
        XCTAssertGreaterThan(result.bytes, 0)
        let exported = try await ClipInfo.inspect(output)
        XCTAssertEqual(exported.width, 128); XCTAssertEqual(exported.height, 96)
        XCTAssertEqual(exported.fps, clip.fps, accuracy: 0.1)
        XCTAssertEqual(exported.duration, clip.duration, accuracy: 0.04)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testMotionUnavailableFailsWithoutPartialExport() async throws {
        #if targetEnvironment(simulator)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await makeVideo(at: root.appendingPathComponent("source.mov"))
        let clip = try await ClipInfo.inspect(source)
        var settings = EnhanceSettings(); settings.fps = 60
        let output = root.appendingPathComponent("unavailable.mov")
        do {
            _ = try await VideoEngine().export(clip: clip, settings: settings, output: output,
                                                control: WorkControl(), progress: { _ in })
            XCTFail("An unavailable GPU must not produce a fake success or duplicate-frame output.")
        } catch let error as LiftError {
            XCTAssertTrue(error.localizedDescription.contains("simulator"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        #else
        XCTAssertNil(FrameProcessor.motionUnavailableReason)
        #endif
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
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        // A track's range can include its leading empty edit. Check the signal
        // itself instead of incorrectly equating track start with audible onset.
        let originalSignal = try await audibleRange(in: source)
        let exportedSignal = try await audibleRange(in: output)
        XCTAssertEqual(originalSignal.start, 0.02, accuracy: 0.002)
        XCTAssertEqual(originalSignal.end, 0.06, accuracy: 0.002)
        XCTAssertEqual(exportedSignal.start, originalSignal.start, accuracy: 0.0005)
        XCTAssertEqual(exportedSignal.end, originalSignal.end, accuracy: 0.0005)
        XCTAssertEqual(result.duration, clip.duration, accuracy: 0.0005)
    }
    private func audibleRange(in url: URL) async throws -> (start: Double, end: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 8000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { throw LiftError.message("Audio test decoder could not start.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? LiftError.message("Audio test could not read the file.") }
        defer { reader.cancelReading() }
        var first: Double?, last: Double?
        while let sample = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(sample)
            guard count > 0 else { continue }
            let buffer = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
            let length = CMBlockBufferGetDataLength(buffer)
            guard length >= count * 2 else { throw LiftError.message("Audio test returned an incomplete PCM buffer.") }
            var pcm = Data(count: length)
            let status = pcm.withUnsafeMutableBytes { (storage: UnsafeMutableRawBufferPointer) in
                CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: storage.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw LiftError.message("Audio test could not decode PCM bytes.") }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard time.isFinite else { throw LiftError.message("Audio test received invalid timing.") }
            for index in 0..<count {
                let bits = UInt16(pcm[index * 2]) | (UInt16(pcm[index * 2 + 1]) << 8)
                let amplitude = abs(Int(Int16(bitPattern: bits)))
                if amplitude > 1000 {
                    if first == nil { first = time + Double(index) / 8000 }
                    last = time + Double(index + 1) / 8000
                }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? LiftError.message("Audio test did not finish decoding.") }
        return (try XCTUnwrap(first), try XCTUnwrap(last))
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
