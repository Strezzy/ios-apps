import XCTest
import AVFoundation
import AudioToolbox
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import Metal
import UniformTypeIdentifiers
@testable import DepthCheck

final class MediaExportTests: XCTestCase {
    func testRationalTimestampLedgerPreserves5994AndVFR() throws {
        var original = FrameTimingLedger()
        var equivalent = FrameTimingLedger()
        let values: [Int64] = [0, 1_001, 2_002, 4_004, 4_504, 5_505]
        for value in values {
            try original.record(pts: CMTime(value: value, timescale: 60_000), duration: CMTime(value: 1_001, timescale: 60_000))
            try equivalent.record(pts: CMTime(value: value * 2, timescale: 120_000), duration: CMTime(value: 2_002, timescale: 120_000))
        }
        XCTAssertEqual(original.count, values.count)
        XCTAssertEqual(original.signature, equivalent.signature)
        XCTAssertEqual(CMTimeCompare(original.endTime, CMTime(value: 6_506, timescale: 60_000)), 0)
        var changed = FrameTimingLedger()
        for index in values.indices {
            try changed.record(pts: CMTime(value: Int64(index), timescale: 24), duration: CMTime(value: 1, timescale: 24))
        }
        XCTAssertNotEqual(original.signature, changed.signature, "A 24 fps retime must be detectable.")
        XCTAssertThrowsError(try original.record(pts: CMTime(value: 5_505, timescale: 60_000), duration: .zero))
    }

    func testSpatialConvergenceIsAppliedOnlyOnce() {
        var options = ConversionOptions()
        options.depthAmount = 0.02
        options.convergence = 0.7
        let metadata = VirtualStereoMetadata(options: options)
        XCTAssertEqual(metadata.disparityAdjustment, 0.014, accuracy: 0.000_001)
        XCTAssertEqual(metadata.unshiftedOptions.convergence, 0)
        XCTAssertFalse(metadata.unshiftedOptions.swapEyes)
        for inverseDepth in [0.0, 0.25, 0.5, 1.0] {
            let displayed = options.depthAmount * inverseDepth - metadata.disparityAdjustment
            let packed = options.depthAmount * (inverseDepth - options.convergence)
            XCTAssertEqual(displayed, packed, accuracy: 0.000_001)
        }
        options.swapEyes = true
        let swapped = VirtualStereoMetadata(options: options)
        let reversed = swapped.spatialDepth(DepthMap(width: 2, height: 1, values: [0.2, 0.9]))
        XCTAssertEqual(reversed.values[0], 0.8, accuracy: 0.000_001)
        XCTAssertEqual(swapped.disparityAdjustment, 0.006, accuracy: 0.000_001)
    }

    func testClockwisePortraitTransformKeepsQuadrantsInCorrectCorners() throws {
        let buffer = try Self.quadrantBuffer(width: 8, height: 4)
        let clockwise = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 4, ty: 0)
        let image = VideoExporter.orientedImage(buffer, transform: clockwise)
        XCTAssertEqual(image.extent.width, 4)
        XCTAssertEqual(image.extent.height, 8)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let output = try VideoExporter.blankBuffer(size: PixelSize(width: 4, height: 8))
        context.render(image, to: output, bounds: image.extent, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        // Original: red green / blue white. Clockwise: blue red / white green.
        XCTAssertEqual(Self.rgb(output, x: 0, y: 0), [0, 0, 255])
        XCTAssertEqual(Self.rgb(output, x: 3, y: 0), [255, 0, 0])
        XCTAssertEqual(Self.rgb(output, x: 0, y: 7), [255, 255, 255])
        XCTAssertEqual(Self.rgb(output, x: 3, y: 7), [0, 255, 0])
        let identity = VideoExporter.orientedImage(buffer, transform: .identity)
        XCTAssertEqual(identity.extent.size, CGSize(width: 8, height: 4))
    }

    func test60FPSVideoPreservesFramesTimestampsAudioAndFullSBSSize() async throws {
        try await runVideoTest(durations: Array(repeating: 1_000, count: 12), format: .sideBySide)
    }

    func testVariableTimingAndSeparateEyesStaySynchronized() async throws {
        try await runVideoTest(durations: [1_000, 1_000, 2_000, 500, 1_500, 1_000, 2_000, 500], format: .separateEyes)
    }

    func testSpatialVideoPreservesBothEyeLayersAndLastFrameDurationWithLongerAudio() async throws {
        // Exercise the native tagged sample-buffer path. Audio ends 0.1 s after
        // video, so a PTS-only writer would silently stretch the final frame.
        try await runVideoTest(durations: Array(repeating: 1_000, count: 12),
                               format: .spatial, audioTailTicks: 6_000)
    }

    func testPhotoPreservesOddDimensionsAndWritesSpatialMetadata() throws {
        let renderer = try Self.renderer()
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoURL = directory.appendingPathComponent("input.png")
        let image = try renderer.cgImage(from: Self.quadrantBuffer(width: 63, height: 31))
        guard let destination = CGImageDestinationCreateWithURL(photoURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return XCTFail("Could not create the test photo")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = MediaSource(url: photoURL, name: "input.png", kind: .photo, size: PixelSize(width: 63, height: 31))
        var options = ConversionOptions()
        options.format = .sideBySide
        options.photoEncoding = .png
        options.depthAmount = 0
        let result = try PhotoExporter(source: source, options: options, outputDirectory: directory, renderer: renderer)
            .export(predictDepth: Self.fakeDepth, onProgress: { _ in })
        XCTAssertEqual(result.size, PixelSize(width: 126, height: 31))
        try PhotoExporter.verify(result.files[0], expectedSize: result.size, spatial: false)

        // HEIC is allowed to reject odd sizes on a particular encoder; create a
        // normal even-sized fixture for the stereo-metadata contract.
        let evenURL = directory.appendingPathComponent("even.png")
        let even = try renderer.cgImage(from: Self.quadrantBuffer(width: 128, height: 72))
        let evenDestination = CGImageDestinationCreateWithURL(evenURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(evenDestination, even, nil)
        XCTAssertTrue(CGImageDestinationFinalize(evenDestination))
        let spatialSource = MediaSource(url: evenURL, name: "even.png", kind: .photo, size: PixelSize(width: 128, height: 72))
        options.format = .spatial
        options.depthAmount = 0.018
        let spatial = try PhotoExporter(source: spatialSource, options: options, outputDirectory: directory, renderer: renderer)
            .export(predictDepth: Self.fakeDepth, onProgress: { _ in })
        try PhotoExporter.verify(spatial.files[0], expectedSize: spatialSource.size, spatial: true)
    }

    private func runVideoTest(durations: [Int64], format: OutputFormat, audioTailTicks: Int64 = 0) async throws {
        let renderer = try Self.renderer()
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("source.mov")
        let expected = try await Self.makeVideoFixture(at: input, durations: durations, audioTailTicks: audioTailTicks)
        let source = MediaSource(url: input, name: "source.mov", kind: .video,
            size: PixelSize(width: 128, height: 72), frameRate: 60,
            duration: Double(durations.reduce(0, +) + audioTailTicks) / 60_000, hasAudio: true)
        var options = ConversionOptions()
        options.format = format
        options.depthAmount = format == .spatial ? 0.018 : 0
        let exporter = VideoExporter(source: source, options: options, outputDirectory: directory, renderer: renderer)
        try await exporter.prepare(onProgress: { _ in })
        let result = try await exporter.export(predictDepth: Self.fakeDepth, onProgress: { _ in })
        XCTAssertEqual(result.frameCount, durations.count)
        XCTAssertEqual(result.files.count, format == .separateEyes ? 2 : 1)
        XCTAssertEqual(result.size, format.outputSize(for: source.size))
        for file in result.files {
            let asset = AVURLAsset(url: file)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let naturalSize = try await track.load(.naturalSize)
            XCTAssertEqual(Int(naturalSize.width), result.size.width)
            XCTAssertEqual(Int(naturalSize.height), result.size.height)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            XCTAssertEqual(audio.count, 1)
            let outputDuration = try await asset.load(.duration)
            XCTAssertEqual(outputDuration.seconds, source.duration, accuracy: 1 / 60_000)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            var times: [CMTime] = []
            var actualDurations: [CMTime] = []
            while let sample = output.copyNextSampleBuffer() {
                times.append(CMSampleBufferGetPresentationTimeStamp(sample))
                actualDurations.append(CMSampleBufferGetDuration(sample))
            }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertEqual(times.count, expected.count)
            for (actual, requested) in zip(times, expected) { XCTAssertEqual(CMTimeCompare(actual, requested), 0) }
            XCTAssertEqual(actualDurations.count, durations.count)
            for (actual, requested) in zip(actualDurations, durations) {
                XCTAssertEqual(CMTimeCompare(actual, CMTime(value: requested, timescale: 60_000)), 0,
                               "Every encoded video duration, including the last, must match its source frame.")
            }
            if format == .spatial {
                // The exporter's own verification additionally requires both
                // layers and exact baseline/FOV/convergence metadata.
                let stereoTracks = try await asset.loadTracks(withMediaCharacteristic: .containsStereoMultiviewVideo)
                XCTAssertEqual(stereoTracks.count, 1)
                XCTAssertEqual(stereoTracks.first?.trackID, track.trackID)
            }
            let audioReader = try AVAssetReader(asset: asset)
            let audioOutput = AVAssetReaderTrackOutput(track: audio[0], outputSettings: nil)
            audioReader.add(audioOutput)
            XCTAssertTrue(audioReader.startReading())
            let firstAudio = try XCTUnwrap(audioOutput.copyNextSampleBuffer())
            XCTAssertEqual(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(firstAudio), .zero), 0)
            XCTAssertGreaterThan(CMSampleBufferGetNumSamples(firstAudio), 0)
        }
    }

    private static func renderer() throws -> StereoRenderer {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("This test host has no Metal device.") }
        return try StereoRenderer()
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fakeDepth(_ image: CIImage, _ temporal: Bool) throws -> DepthMap {
        DepthMap(width: 2, height: 2, values: [0.2, 0.4, 0.6, 0.8])
    }

    private static func quadrantBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try VideoExporter.blankBuffer(size: PixelSize(width: width, height: height))
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let rgb: [UInt8] = y < height / 2 ? (x < width / 2 ? [255, 0, 0] : [0, 255, 0])
                    : (x < width / 2 ? [0, 0, 255] : [255, 255, 255])
                let index = y * stride + x * 4
                bytes[index] = rgb[2]; bytes[index + 1] = rgb[1]; bytes[index + 2] = rgb[0]; bytes[index + 3] = 255
            }
        }
        return buffer
    }

    private static func rgb(_ buffer: CVPixelBuffer, x: Int, y: Int) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let index = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
        return [bytes[index + 2], bytes[index + 1], bytes[index]]
    }

    private static func makeVideoFixture(at url: URL, durations: [Int64], audioTailTicks: Int64 = 0) async throws -> [CMTime] {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieTimeScale = 60_000
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 72,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false, AVVideoExpectedSourceFrameRateKey: 60]
        ])
        input.mediaTimeScale = 60_000
        writer.add(input)
        let totalTicks = durations.reduce(0, +) + audioTailTicks
        let audioSample = try makeAudioSample(frameCount: Int(totalTicks * 48_000 / 60_000))
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil,
                                          sourceFormatHint: CMSampleBufferGetFormatDescription(audioSample))
        writer.add(audioInput)
        guard writer.startWriting() else { throw writer.error! }
        writer.startSession(atSourceTime: .zero)
        // Prime audio so the writer's interleaver never waits for an absent track.
        while !audioInput.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
        guard audioInput.append(audioSample) else { throw writer.error ?? DepthCheckError.message("Fixture audio write failed") }
        audioInput.markAsFinished()
        var pts: Int64 = 0
        var requested: [CMTime] = []
        for duration in durations {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error! }
                try await Task.sleep(for: .milliseconds(2))
            }
            let time = CMTime(value: pts, timescale: 60_000)
            let buffer = try quadrantBuffer(width: 128, height: 72)
            var format: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                imageBuffer: buffer, formatDescriptionOut: &format) == noErr, let format else {
                throw DepthCheckError.message("Fixture video description failed")
            }
            var timing = CMSampleTimingInfo(duration: CMTime(value: duration, timescale: 60_000),
                                           presentationTimeStamp: time, decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
                  let sample, input.append(sample) else {
                throw writer.error ?? DepthCheckError.message("Fixture frame write failed")
            }
            requested.append(time)
            pts += duration
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: totalTicks, timescale: 60_000))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DepthCheckError.message("Fixture finalization failed") }
        return requested
    }

    private static func makeAudioSample(frameCount: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr else {
            throw DepthCheckError.message("Fixture audio description failed")
        }
        var block: CMBlockBuffer?
        let byteCount = frameCount * 4
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == noErr, let block else {
            throw DepthCheckError.message("Fixture audio allocation failed")
        }
        let samples: [Int16] = (0..<(frameCount * 2)).map { Int16(sin(Double($0 / 2) * 2 * .pi * 440 / 48_000) * 8_000) }
        let status = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        }
        guard status == noErr else { throw DepthCheckError.message("Fixture audio fill failed") }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var sampleSize = 4
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: frameCount, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr, let sample else {
            throw DepthCheckError.message("Fixture audio sample creation failed")
        }
        return sample
    }
}
