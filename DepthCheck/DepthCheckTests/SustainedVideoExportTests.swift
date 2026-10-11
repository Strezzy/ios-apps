import XCTest
import Foundation
import AVFoundation
import AudioToolbox
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import CryptoKit
import Metal
@testable import DepthCheck

/// Sustained, real encoder/muxer tests. No depth-model download or inference is
/// involved: the deterministic depth input isolates media scheduling and EOF.
/// The audio fixture is genuinely packetized AAC, rather than one PCM buffer
/// whose input can be marked finished before video encoding even begins.
final class SustainedVideoExportTests: XCTestCase {
    private static let evidenceStore = SustainedEvidenceStore()

    /// The native harness consumes an entry only after this test's independent
    /// media checks all succeeded. XCTest must also report zero failures/skips.
    static var nativeEvidence: [String: [String: Any]] { evidenceStore.snapshot }

    func test874FramesWithAudioTailReproduce920FrameEstimate() async throws {
        // Exactly matches the reported progress: 874 actual video frames, but
        // 920 estimated from the whole asset's duration, including its audio
        // tail. Last video PTS = 14.55 s; the old progress formula shows 89.4%.
        try await run(
            name: "test874FramesWithAudioTailReproduce920FrameEstimate",
            configuration: Configuration(size: PixelSize(width: 640, height: 360),
                frameCount: 874, audioStart: 0, audioEnd: 920 * 800),
            expectedEstimate: 920
        )
    }

    func test920FramesOf60FPSSBSWithAACEndingBeforeVideo() async throws {
        // The opposite boundary: the audio input has to announce EOF while
        // another 120 video frames remain to be submitted to the same muxer.
        try await run(
            name: "test920FramesOf60FPSSBSWithAACEndingBeforeVideo",
            configuration: Configuration(size: PixelSize(width: 640, height: 360),
                frameCount: 920, audioStart: 0, audioEnd: 920 * 800 - 96_000)
        )
    }

    func testThreeMinute60FPSSBSWithDelayedAAC() async throws {
        guard ProcessInfo.processInfo.environment["DEPTHCHECK_RUN_THREE_MINUTE_SUSTAINED"] == "1" else {
            throw XCTSkip("The separate sustained native gate runs this 10,800-frame, three-minute test with an explicit time budget.")
        }
        // 180 seconds of video, a real 2.25-second initial audio offset, and a
        // 137 ms audio tail exercise late starts and non-frame-aligned endings.
        try await run(
            name: "testThreeMinute60FPSSBSWithDelayedAAC",
            configuration: Configuration(size: PixelSize(width: 160, height: 90),
                frameCount: 10_800, audioStart: 108_000, audioEnd: 10_800 * 800 + 6_576)
        )
    }

    func test920FramesOf4K60FPSPreservesFullSBSWithAAC() async throws {
        guard ProcessInfo.processInfo.environment["DEPTHCHECK_RUN_4K_SUSTAINED"] == "1" else {
            throw XCTSkip("The separate native gate runs 920 real 4K60 frames with full 7680 × 2160 SBS output and a longer time budget.")
        }
        try await run(
            name: "test920FramesOf4K60FPSPreservesFullSBSWithAAC",
            configuration: Configuration(size: PixelSize(width: 3_840, height: 2_160),
                frameCount: 920, audioStart: 0, audioEnd: 920 * 800 + 6_576)
        )
    }

    private func run(name: String, configuration: Configuration, expectedEstimate: Int? = nil) async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("These encoder/renderer tests require a real Metal device; an unsupported host is not a passing native gate.")
        }
        let started = Self.now
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DepthCheck-Sustained-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Packetized-AAC-Source.mov")
        var elapsed: [String: Double] = [:]
        let progress = SustainedProgressRecorder(name: name)

        do {
            var mark = Self.now
            try await Self.makeFixture(at: original, configuration: configuration)
            elapsed["fixture"] = Self.now - mark
            Self.logPhase(name, phase: "fixture", seconds: elapsed["fixture"]!)

            mark = Self.now
            let sourceVideo = try await Self.inspectVideo(original, expectedCount: configuration.frameCount,
                                                          expectedSize: configuration.size)
            let sourceAudio = try await Self.inspectAAC(original)
            let expectedAudioStart = CMTime(value: Int64(configuration.audioStart), timescale: 48_000)
            let expectedAudioEnd = CMTime(value: Int64(configuration.audioEnd), timescale: 48_000)
            try Self.logAudioInspection(sourceAudio, name: name, phase: "source",
                                        expectedStart: expectedAudioStart, expectedEnd: expectedAudioEnd)
            try Self.require(sourceAudio.packetCount > 500, "Fixture must contain hundreds of actual AAC packets.")
            // An initial empty edit can make track.timeRange start at zero.
            // The nonempty segment's target range identifies playable audio;
            // its source range separately exposes the AAC media/priming edit.
            try Self.require(CMTimeCompare(sourceAudio.playableStart, expectedAudioStart) == 0,
                             "Fixture playable audio start must be \(Self.timeString(expectedAudioStart)). \(sourceAudio.timelineDescription)")
            try Self.require(CMTimeCompare(sourceAudio.playableEnd, expectedAudioEnd) == 0,
                             "Fixture playable audio end must be \(Self.timeString(expectedAudioEnd)). \(sourceAudio.timelineDescription)")
            try Self.require(CMTimeCompare(CMTimeRangeGetEnd(sourceAudio.trackRange), expectedAudioEnd) == 0,
                             "Fixture track end must be \(Self.timeString(expectedAudioEnd)). \(sourceAudio.timelineDescription)")
            if configuration.audioStart > 0 {
                try Self.require(CMTimeCompare(sourceAudio.firstPTS, CMTime(value: 1, timescale: 1)) > 0,
                                 "The delayed-audio fixture must retain a real initial gap in its AAC packet timeline. \(sourceAudio.timelineDescription)")
            }
            if configuration.audioEnd < configuration.frameCount * 800 {
                try Self.require(CMTimeCompare(sourceAudio.end, configuration.videoEnd) < 0,
                                 "The short-audio fixture must reach AAC EOF before video EOF.")
            } else {
                try Self.require(CMTimeCompare(sourceAudio.end, configuration.videoEnd) > 0,
                                 "The audio-tail fixture must contain real AAC packets beyond video EOF.")
            }
            let asset = AVURLAsset(url: original)
            let duration = try await asset.load(.duration)
            try Self.require(CMTimeCompare(duration, configuration.assetEnd) == 0,
                             "Fixture duration \(Self.timeString(duration)) differs from its requested \(Self.timeString(configuration.assetEnd)).")
            let nominalRate = try await sourceVideo.track.load(.nominalFrameRate)
            let estimate = Int((duration.seconds * Double(nominalRate)).rounded())
            if let expectedEstimate {
                try Self.require(estimate == expectedEstimate,
                                 "The reproduction needs \(expectedEstimate) estimated frames, but its real source reports \(estimate).")
                try Self.require(configuration.frameCount == 874, "The user reproduction must retain 874 actual video frames.")
            }
            elapsed["source_inspection"] = Self.now - mark
            Self.logPhase(name, phase: "source inspection", seconds: elapsed["source_inspection"]!)

            let source = MediaSource(url: original, name: "Packetized-AAC-Source.mov", kind: .video,
                size: configuration.size, frameRate: Double(nominalRate), duration: duration.seconds, hasAudio: true)
            var options = ConversionOptions()
            options.format = .sideBySide
            options.memorySaver = true
            options.temporalStability = true
            options.preserveAudio = true
            options.depthAmount = 0.018
            let renderer = try StereoRenderer()
            defer { renderer.purgeCaches() }
            let exporter = VideoExporter(source: source, options: options, outputDirectory: directory, renderer: renderer)
            mark = Self.now
            try await exporter.prepare(onProgress: { update in progress.receive(update) })
            elapsed["prepare"] = Self.now - mark
            Self.logPhase(name, phase: "prepare", seconds: elapsed["prepare"]!)
            mark = Self.now
            let result = try await exporter.export(predictDepth: Self.fixtureDepth,
                                                   onProgress: { update in progress.receive(update) })
            elapsed["export"] = Self.now - mark
            Self.logPhase(name, phase: "export", seconds: elapsed["export"]!)

            try Self.require(result.frameCount == configuration.frameCount,
                             "Export reported \(result.frameCount) frames instead of \(configuration.frameCount).")
            try Self.require(result.files.count == 1, "Full SBS must produce one complete video file.")
            let outputSize = PixelSize(width: configuration.size.width * 2, height: configuration.size.height)
            try Self.require(result.size == outputSize, "The export changed the full SBS dimensions.")
            let outputURL = try XCTUnwrap(result.files.first)
            mark = Self.now
            let outputVideo = try await Self.inspectVideo(outputURL, expectedCount: configuration.frameCount,
                                                          expectedSize: outputSize)
            let outputAudio = try await Self.inspectAAC(outputURL)
            try Self.logAudioInspection(outputAudio, name: name, phase: "output",
                                        expectedStart: expectedAudioStart, expectedEnd: expectedAudioEnd)
            try Self.require(outputVideo.timingHash == sourceVideo.timingHash,
                             "The exported video changed a source frame's PTS or duration.")
            try Self.require(outputAudio.packetCount == sourceAudio.packetCount,
                             "AAC packet loss: source \(sourceAudio.packetCount), output \(outputAudio.packetCount).")
            try Self.require(outputAudio.payloadHash == sourceAudio.payloadHash,
                             "Original AAC payload bytes were lost, changed, reordered, or re-encoded.")
            try Self.require(outputAudio.timingHash == sourceAudio.timingHash,
                             "The AAC packet timeline changed, including its initial offset or final duration.")
            try Self.require(CMTimeCompare(outputAudio.trackRange.start, sourceAudio.trackRange.start) == 0 &&
                             CMTimeCompare(outputAudio.trackRange.duration, sourceAudio.trackRange.duration) == 0,
                             "The aggregate audio track range changed. Source: \(sourceAudio.timelineDescription) Output: \(outputAudio.timelineDescription)")
            try Self.require(CMTimeCompare(outputAudio.playableStart, sourceAudio.playableStart) == 0 &&
                             CMTimeCompare(outputAudio.playableEnd, sourceAudio.playableEnd) == 0,
                             "The playable audio interval changed, including its initial gap or final trim. Source: \(sourceAudio.timelineDescription) Output: \(outputAudio.timelineDescription)")
            let outputAsset = AVURLAsset(url: outputURL)
            let outputDuration = try await outputAsset.load(.duration)
            try Self.require(CMTimeCompare(outputDuration, duration) == 0,
                             "The output duration no longer covers the original video and audio endings.")
            elapsed["output_verification"] = Self.now - mark
            Self.logPhase(name, phase: "output verification", seconds: elapsed["output_verification"]!)

            mark = Self.now
            try await Self.verifyFinalFrame(at: outputURL, configuration: configuration, outputSize: outputSize)
            elapsed["final_frame_decode"] = Self.now - mark
            Self.logPhase(name, phase: "final frame decode", seconds: elapsed["final_frame_decode"]!)
            elapsed["total"] = Self.now - started

            let recorded: [String: Any] = [
                "test": name,
                "status": "passed",
                "source": sourceVideo.evidence.merging(sourceAudio.evidence) { _, new in new }.merging([
                    "duration": Self.timeString(duration), "estimated_frame_count": estimate
                ]) { _, new in new },
                "output": outputVideo.evidence.merging(outputAudio.evidence) { _, new in new }.merging([
                    "duration": Self.timeString(outputDuration)
                ]) { _, new in new },
                "elapsed_seconds": elapsed,
                "memory_saver": true,
                "depth_provider": "Deterministic depth fixture; no model inference",
                "terminal_frame_verified": true,
                "progress_max_frames": progress.maximumFrames
            ]
            Self.evidenceStore.record(recorded, named: name)
            let json = try JSONSerialization.data(withJSONObject: recorded, options: [.sortedKeys])
            Self.log("[DepthCheckSustainedEvidence] " + String(decoding: json, as: UTF8.self))
        } catch {
            Self.log("[DepthCheckSustainedFailure] \(name): \(error.localizedDescription); last observed frame \(progress.maximumFrames), elapsed \(String(format: "%.3f", Self.now - started)) s")
            throw error
        }
    }

    private struct Configuration {
        let size: PixelSize
        let frameCount: Int
        /// Absolute PCM-frame positions on a 48 kHz clock, including any offset.
        let audioStart: Int
        let audioEnd: Int
        var videoEnd: CMTime { CMTime(value: Int64(frameCount), timescale: 60) }
        var assetEnd: CMTime { CMTimeMaximum(videoEnd, CMTime(value: Int64(audioEnd), timescale: 48_000)) }
    }

    /// Independent producer-side fixture: known sample counts announce EOF
    /// immediately after their last append, never after a readiness callback.
    private static func makeFixture(at url: URL, configuration: Configuration) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieTimeScale = 60_000
        let size = configuration.size
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAllowFrameReorderingKey: false,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoAverageBitRateKey: max(750_000, size.width * size.height * 6)
            ]
        ])
        video.mediaTimeScale = 60_000
        video.expectsMediaDataInRealTime = false
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ])
        audio.expectsMediaDataInRealTime = false
        try require(writer.canAdd(video) && writer.canAdd(audio), "The test host cannot create an HEVC/AAC fixture.")
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw writer.error ?? Failure("Fixture writer could not start.") }
        writer.startSession(atSourceTime: .zero)
        defer { if writer.status == .writing { writer.cancelWriting() } }

        // Only two immutable source surfaces are retained, including at 4K.
        // The final blue frame is distinct from every earlier red frame.
        let regular = try colorBuffer(size: size, red: 195, green: 48, blue: 30)
        let terminal = try colorBuffer(size: size, red: 20, green: 75, blue: 230)
        var description: CMVideoFormatDescription?
        try require(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
            imageBuffer: regular, formatDescriptionOut: &description) == noErr, "Fixture video description failed.")
        let videoDescription = try XCTUnwrap(description)
        let audioDescription = try pcmFormat()
        var videoIndex = 0
        var audioPosition = configuration.audioStart
        var videoFinished = false
        var audioFinished = false
        var lastProgress = now

        while !videoFinished || !audioFinished {
            try Task.checkCancellation()
            guard writer.status == .writing else { throw writer.error ?? Failure("Fixture writer stopped.") }
            var progressed = false
            if !audioFinished, audio.isReadyForMoreMediaData {
                // Feed AAC's natural 1,024-frame quantum and retain no audio
                // array beyond the current small PCM packet.
                let count = min(1_024, configuration.audioEnd - audioPosition)
                try autoreleasepool {
                    let packet = try pcmPacket(start: audioPosition, count: count, format: audioDescription)
                    guard audio.append(packet) else { throw writer.error ?? Failure("Fixture AAC encoder rejected a packet.") }
                }
                audioPosition += count
                if audioPosition == configuration.audioEnd { audio.markAsFinished(); audioFinished = true }
                progressed = true
            }
            if !videoFinished, video.isReadyForMoreMediaData {
                try autoreleasepool {
                    var timing = CMSampleTimingInfo(duration: CMTime(value: 1_000, timescale: 60_000),
                        presentationTimeStamp: CMTime(value: Int64(videoIndex) * 1_000, timescale: 60_000), decodeTimeStamp: .invalid)
                    var sample: CMSampleBuffer?
                    let pixels = videoIndex == configuration.frameCount - 1 ? terminal : regular
                    try require(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                        imageBuffer: pixels, formatDescription: videoDescription, sampleTiming: &timing,
                        sampleBufferOut: &sample) == noErr, "Fixture video sample creation failed.")
                    guard video.append(try XCTUnwrap(sample)) else { throw writer.error ?? Failure("Fixture HEVC encoder rejected a frame.") }
                }
                videoIndex += 1
                if videoIndex == configuration.frameCount { video.markAsFinished(); videoFinished = true }
                progressed = true
            }
            if progressed { lastProgress = now }
            else {
                try require(now - lastProgress < 45, "The independent fixture producer stalled before export was tested.")
                try await Task.sleep(for: .milliseconds(1))
            }
        }
        writer.endSession(atSourceTime: configuration.assetEnd)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure("Fixture finalization failed.") }
    }

    private static func pcmFormat() throws -> CMAudioFormatDescription {
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        try require(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format) == noErr, "Fixture PCM format creation failed.")
        return try XCTUnwrap(format)
    }

    private static func pcmPacket(start: Int, count: Int, format: CMAudioFormatDescription) throws -> CMSampleBuffer {
        try require(count > 0 && count <= 1_024, "Fixture PCM packet must be bounded and nonempty.")
        let byteCount = count * 4
        var block: CMBlockBuffer?
        try require(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: byteCount, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: byteCount, flags: 0, blockBufferOut: &block) == noErr,
            "Fixture PCM allocation failed.")
        let data = try XCTUnwrap(block)
        let samples: [Int16] = (0..<(count * 2)).map { index in
            let sample = start + index / 2
            let frequency = index.isMultiple(of: 2) ? 440.0 : 660.0
            return Int16(sin(Double(sample) * 2 * .pi * frequency / 48_000) * 7_000)
        }
        let status = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: data,
                offsetIntoDestination: 0, dataLength: byteCount)
        }
        try require(status == noErr, "Fixture PCM fill failed.")
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(value: Int64(start), timescale: 48_000), decodeTimeStamp: .invalid)
        var sampleSize = 4
        var sample: CMSampleBuffer?
        try require(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
            formatDescription: format, sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr,
            "Fixture PCM sample creation failed.")
        return try XCTUnwrap(sample)
    }

    private static func colorBuffer(size: PixelSize, red: UInt8, green: UInt8, blue: UInt8) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        try require(CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &result) == kCVReturnSuccess, "Fixture pixel-buffer allocation failed.")
        let buffer = try XCTUnwrap(result)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let pixel = (UInt32(blue) | UInt32(green) << 8 | UInt32(red) << 16 | 0xFF00_0000).littleEndian
        let row = Array(repeating: pixel, count: size.width)
        row.withUnsafeBytes { bytes in
            for y in 0..<size.height {
                base.advanced(by: y * stride).copyMemory(from: bytes.baseAddress!, byteCount: size.width * 4)
            }
        }
        return buffer
    }

    private struct VideoInspection {
        let track: AVAssetTrack
        let frameCount: Int
        let size: PixelSize
        let timingHash: String
        let end: CMTime
        var evidence: [String: Any] {
            ["frame_count": frameCount, "width": size.width, "height": size.height,
             "video_timing_sha256": timingHash, "video_end": SustainedVideoExportTests.timeString(end)]
        }
    }

    private static func inspectVideo(_ url: URL, expectedCount: Int, expectedSize: PixelSize) async throws -> VideoInspection {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        try require(tracks.count == 1, "The fixture and SBS output must each contain exactly one video track.")
        let track = try XCTUnwrap(tracks.first)
        let naturalSize = try await track.load(.naturalSize)
        try require(Int(naturalSize.width) == expectedSize.width && Int(naturalSize.height) == expectedSize.height,
                    "Actual encoded video dimensions differ from \(expectedSize.label).")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure("Video verification reader could not start.") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var count = 0
        var hash = SHA256()
        var end = CMTime.zero
        while true {
            let hadSample = try autoreleasepool { () throws -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                // Do not use the production timing iterator/ledger: validate
                // the encoded samples directly against the fixture's 60 Hz grid.
                for index in 0..<CMSampleBufferGetNumSamples(sample) {
                    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
                    try require(CMSampleBufferGetSampleTimingInfo(sample, at: index, timingInfoOut: &timing) == noErr,
                                "Encoded video sample timing is unreadable.")
                    try require(CMTimeCompare(timing.presentationTimeStamp, CMTime(value: Int64(count), timescale: 60)) == 0,
                                "Frame \(count) was dropped, repeated, or retimed: \(timeString(timing.presentationTimeStamp)).")
                    try require(CMTimeCompare(timing.duration, CMTime(value: 1, timescale: 60)) == 0,
                                "Frame \(count), including the final frame, must retain its exact 1/60 s duration.")
                    hash.update(data: Data(try timingToken(timing).utf8))
                    end = CMTimeAdd(timing.presentationTimeStamp, timing.duration)
                    count += 1
                }
                return true
            }
            if !hadSample { break }
        }
        try require(reader.status == .completed, "Video verification did not reach EOF: \(reader.error?.localizedDescription ?? "unknown error").")
        try require(count == expectedCount, "Encoded video contains \(count) frames; expected \(expectedCount).")
        return VideoInspection(track: track, frameCount: count, size: expectedSize, timingHash: hex(hash.finalize()), end: end)
    }

    private struct AudioInspection {
        let packetCount: Int
        let payloadBytes: Int
        let payloadHash: String
        let timingHash: String
        let firstPTS: CMTime
        let end: CMTime
        let trackRange: CMTimeRange
        let playableStart: CMTime
        let playableEnd: CMTime
        let segments: [AudioSegmentInspection]
        var evidence: [String: Any] {
            ["audio_codec": "AAC", "audio_packet_count": packetCount, "audio_payload_bytes": payloadBytes,
             "audio_payload_sha256": payloadHash, "audio_timing_sha256": timingHash,
             "audio_first_pts": SustainedVideoExportTests.timeString(firstPTS),
             "audio_end": SustainedVideoExportTests.timeString(end),
             "audio_track_start": SustainedVideoExportTests.timeString(trackRange.start),
             "audio_track_end": SustainedVideoExportTests.timeString(CMTimeRangeGetEnd(trackRange)),
             "audio_playable_start": SustainedVideoExportTests.timeString(playableStart),
             "audio_playable_end": SustainedVideoExportTests.timeString(playableEnd),
             "audio_segments": segments.map(\.evidence)]
        }
        var timelineDescription: String {
            "Track \(SustainedVideoExportTests.rangeString(trackRange)); playable \(SustainedVideoExportTests.timeString(playableStart))…\(SustainedVideoExportTests.timeString(playableEnd)); first AAC PTS \(SustainedVideoExportTests.timeString(firstPTS)); final AAC end \(SustainedVideoExportTests.timeString(end)); segments [\(segments.map(\.description).joined(separator: "; "))]."
        }
    }

    private struct AudioSegmentInspection {
        let isEmpty: Bool
        let source: CMTimeRange
        let target: CMTimeRange
        var evidence: [String: Any] {
            ["empty": isEmpty,
             "source_start": SustainedVideoExportTests.timeString(source.start),
             "source_end": SustainedVideoExportTests.timeString(CMTimeRangeGetEnd(source)),
             "target_start": SustainedVideoExportTests.timeString(target.start),
             "target_end": SustainedVideoExportTests.timeString(CMTimeRangeGetEnd(target))]
        }
        var description: String {
            "\(isEmpty ? "empty" : "media") source \(SustainedVideoExportTests.rangeString(source)) → target \(SustainedVideoExportTests.rangeString(target))"
        }
    }

    private static func inspectAAC(_ url: URL) async throws -> AudioInspection {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try require(tracks.count == 1, "A complete stereo AAC track must be present.")
        let track = try XCTUnwrap(tracks.first)
        let trackRange = try await track.load(.timeRange)
        let trackSegments = try await track.load(.segments)
        let segments = trackSegments.map {
            AudioSegmentInspection(isEmpty: $0.isEmpty, source: $0.timeMapping.source, target: $0.timeMapping.target)
        }
        let playableSegments = segments.filter {
            !$0.isEmpty && $0.target.start.isNumeric && $0.target.duration.isNumeric && CMTimeCompare($0.target.duration, .zero) > 0
        }.sorted { CMTimeCompare($0.target.start, $1.target.start) < 0 }
        guard let firstPlayable = playableSegments.first else {
            throw Failure("No nonempty audio segment maps to a playable interval. Track \(rangeString(trackRange)); segments [\(segments.map(\.description).joined(separator: "; "))].")
        }
        let playableEnd = playableSegments.reduce(CMTimeRangeGetEnd(firstPlayable.target)) {
            CMTimeMaximum($0, CMTimeRangeGetEnd($1.target))
        }
        let formats = try await track.load(.formatDescriptions)
        let format = try XCTUnwrap(formats.first)
        try require(CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC,
                    "The sustained regression must exercise actual compressed AAC, not PCM.")
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? Failure("AAC verification could not start.") }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var packetCount = 0
        var payloadBytes = 0
        var payloadHash = SHA256()
        var timingHash = SHA256()
        var firstPTS: CMTime?
        var end = CMTime.zero
        while true {
            let hadSample = try autoreleasepool { () throws -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                let count = CMSampleBufferGetNumSamples(sample)
                if count == 0 { return true } // An empty edit marker is not an AAC packet.
                let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(sample))
                var offset = 0
                for index in 0..<count {
                    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
                    try require(CMSampleBufferGetSampleTimingInfo(sample, at: index, timingInfoOut: &timing) == noErr,
                                "An original AAC packet's timing is unreadable.")
                    try require(timing.presentationTimeStamp.isNumeric && timing.duration.isNumeric,
                                "AAC must expose its complete packet timeline.")
                    let size = CMSampleBufferGetSampleSize(sample, at: index)
                    try require(size > 0, "An AAC packet has no compressed payload.")
                    var bytes = [UInt8](repeating: 0, count: size)
                    let copied = bytes.withUnsafeMutableBytes {
                        CMBlockBufferCopyDataBytes(block, atOffset: offset, dataLength: size, destination: $0.baseAddress!)
                    }
                    try require(copied == noErr, "An AAC packet's bytes could not be read.")
                    // Explicit packet boundaries make the signature independent
                    // of how AVAssetReader batches packets into sample buffers.
                    payloadHash.update(data: Data("\(size):".utf8))
                    payloadHash.update(data: Data(bytes))
                    timingHash.update(data: Data(try timingToken(timing).utf8))
                    if firstPTS == nil { firstPTS = timing.presentationTimeStamp }
                    end = CMTimeMaximum(end, CMTimeAdd(timing.presentationTimeStamp, timing.duration))
                    offset += size
                    payloadBytes += size
                    packetCount += 1
                }
                return true
            }
            if !hadSample { break }
        }
        try require(reader.status == .completed, "AAC verification did not reach EOF: \(reader.error?.localizedDescription ?? "unknown error").")
        return AudioInspection(packetCount: packetCount, payloadBytes: payloadBytes,
            payloadHash: hex(payloadHash.finalize()), timingHash: hex(timingHash.finalize()),
            firstPTS: try XCTUnwrap(firstPTS), end: end, trackRange: trackRange,
            playableStart: firstPlayable.target.start, playableEnd: playableEnd, segments: segments)
    }

    private static func logAudioInspection(_ audio: AudioInspection, name: String, phase: String,
                                           expectedStart: CMTime, expectedEnd: CMTime) throws {
        let diagnostic = audio.evidence.merging([
            "test": name, "phase": phase,
            "expected_playable_start": timeString(expectedStart),
            "expected_playable_end": timeString(expectedEnd)
        ]) { _, new in new }
        let json = try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])
        log("[DepthCheckSustainedAudio] " + String(decoding: json, as: UTF8.self))
    }

    private static func verifyFinalFrame(at url: URL, configuration: Configuration, outputSize: PixelSize) async throws {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: CGFloat(outputSize.width), height: CGFloat(outputSize.height))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let requested = CMTime(value: Int64(configuration.frameCount - 1), timescale: 60)
        let image = try await generator.image(at: requested)
        try require(CMTimeCompare(image.actualTime, requested) == 0, "The final encoded frame cannot be decoded at its original timestamp.")
        try require(image.image.width == outputSize.width && image.image.height == outputSize.height,
                    "The decoded terminal frame does not have the full SBS dimensions.")
        var pixels = [UInt8](repeating: 0, count: 8)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 2, height: 1,
                bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            context.draw(image.image, in: CGRect(x: 0, y: 0, width: 2, height: 1))
        }
        for offset in [0, 4] {
            try require(pixels[offset] < 80 && pixels[offset + 1] < 135 && pixels[offset + 2] > 175,
                        "The final frame in both eyes must be the distinct blue terminal image, not an earlier red frame.")
        }
    }

    private static func fixtureDepth(_ image: CIImage, _ temporal: Bool) throws -> DepthMap {
        DepthMap(width: 2, height: 2, values: [0.2, 0.4, 0.6, 0.8])
    }

    private static func timingToken(_ timing: CMSampleTimingInfo) throws -> String {
        // The fixture's 60,000 Hz video and 48,000 Hz AAC clocks both divide
        // this exact common clock; reject any accidental lossy conversion.
        func ticks(_ time: CMTime) throws -> String {
            let converted = CMTimeConvertScale(time, timescale: 2_400_000, method: .default)
            try require(time.isNumeric && converted.isNumeric && CMTimeCompare(time, converted) == 0,
                        "A packet timestamp fell off the fixture's exact rational clock.")
            return "\(converted.value)@\(converted.epoch)"
        }
        return try "\(ticks(timing.presentationTimeStamp)):\(ticks(timing.duration));"
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func timeString(_ time: CMTime) -> String { "\(time.value)/\(time.timescale)@\(time.epoch)" }
    private static func rangeString(_ range: CMTimeRange) -> String { "\(timeString(range.start))…\(timeString(CMTimeRangeGetEnd(range)))" }
    private static var now: Double { ProcessInfo.processInfo.systemUptime }
    private static func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure(message) } }
    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    private static func logPhase(_ name: String, phase: String, seconds: Double) {
        log("[DepthCheckSustained] \(name): \(phase) \(String(format: "%.3f", seconds)) s")
    }
    private static func log(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
}

private final class SustainedEvidenceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String: Any]] = [:]
    var snapshot: [String: [String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
    func record(_ evidence: [String: Any], named name: String) {
        lock.lock()
        values[name] = evidence
        lock.unlock()
    }
}

private final class SustainedProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let name: String
    private var maximum = 0
    private var lastLog = 0.0
    init(name: String) { self.name = name }
    var maximumFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return maximum
    }
    func receive(_ progress: ConversionProgress) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        maximum = max(maximum, progress.framesProcessed)
        let shouldLog = now - lastLog >= 5
        if shouldLog { lastLog = now }
        lock.unlock()
        if shouldLog {
            FileHandle.standardOutput.write(Data(("[DepthCheckSustainedProgress] \(name): \(progress.framesProcessed) frames; \(progress.stage)\n").utf8))
        }
    }
}
