import Foundation
import AVFoundation
import CryptoKit

struct ExportResult: Sendable {
    let url: URL
    let frames: Int
    let bytes: Int64
    let sha256: String
    let duration: Double
}

final class VideoEngine: @unchecked Sendable {
    private struct Frame { let buffer: CVPixelBuffer; let time: CMTime }
    func export(clip: ClipInfo, settings: EnhanceSettings, output: URL,
                control: WorkControl, previewSeconds: Double? = nil,
                progress: @escaping @Sendable (WorkProgress) -> Void) async throws -> ExportResult {
        try settings.validate(width: clip.width, height: clip.height, sourceFPS: clip.fps)
        try control.checkpoint(gentle: settings.gentleProcessing)
        guard output.isFileURL, !FileManager.default.fileExists(atPath: output.path) else {
            throw LiftError.message("The export destination is not a new local file.")
        }
        let length = min(clip.duration, previewSeconds ?? clip.duration)
        let duration = CMTime(seconds: length, preferredTimescale: 60000)
        let range = CMTimeRange(start: clip.timeRange.start, duration: duration)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("LumaLift-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let temporary = work.appendingPathComponent("frames.mov")
        var succeeded = false
        defer {
            try? FileManager.default.removeItem(at: work)
            if !succeeded { try? FileManager.default.removeItem(at: output) }
        }
        let available = try output.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        let estimate = Int64(Double(clip.width * clip.height * settings.scale * settings.scale) * max(clip.fps, Double(settings.fps)) * length * 0.22 / 8) * 2 + 200_000_000
        guard available == 0 || available > estimate else {
            throw LiftError.message("There is not enough free space for this export and its temporary file. Choose a smaller output or free some storage.")
        }
        progress(WorkProgress(fraction: 0, stage: "Preparing on-device models"))
        let processor = try FrameProcessor()
        if settings.usesRestoration { try processor.loadRestoration() }
        let asset = AVURLAsset(url: clip.url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LiftError.message("The imported video is no longer available.")
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw LiftError.message("The video decoder could not open this format.") }
        reader.add(readerOutput)
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let outputFPS = settings.fps == 0 ? clip.fps : Double(settings.fps)
        let width = clip.width * settings.scale, height = clip.height * settings.scale
        let bitrate = Int(min(100_000_000, max(2_000_000, Double(width * height) * outputFPS * 0.22)))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: outputFPS,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false, AVVideoMaxKeyFrameIntervalDurationKey: 2]
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw LiftError.message("The encoder does not support this size and frame rate on this device.")
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        var transform = clip.transform
        transform.tx *= Double(settings.scale); transform.ty *= Double(settings.scale)
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw LiftError.message("The video encoder could not start.") }
        writer.add(input)
        writer.metadata = []
        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? LiftError.message("Could not begin decoding and encoding.")
        }
        writer.startSession(atSourceTime: .zero)
        defer {
            reader.cancelReading()
            if writer.status == .writing { writer.cancelWriting() }
        }
        var frames = 0
        var lastOutputTime = CMTime.invalid
        var lastInputTime = CMTime.invalid
        var latestFraction = 0.0
        let onWait: (String) -> Void = { message in
            progress(WorkProgress(fraction: latestFraction, stage: message, frames: frames))
        }
        func readFrame() throws -> Frame? {
            guard let sample = readerOutput.copyNextSampleBuffer() else {
                if reader.status == .failed { throw reader.error ?? LiftError.message("Video decoding failed.") }
                return nil
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw LiftError.message("A decoded video frame is missing.") }
            let time = CMTimeSubtract(CMSampleBufferGetPresentationTimeStamp(sample), range.start)
            guard time.isNumeric, time >= .zero, !lastInputTime.isValid || time > lastInputTime else {
                throw LiftError.message("The source has invalid or non-increasing frame timestamps.")
            }
            lastInputTime = time
            return Frame(buffer: buffer, time: time)
        }
        func append(_ buffer: CVPixelBuffer, at time: CMTime) async throws {
            try control.checkpoint(gentle: settings.gentleProcessing, onWait: onWait)
            guard !lastOutputTime.isValid || time > lastOutputTime else {
                throw LiftError.message("The output clock produced an invalid timestamp.")
            }
            let restored = try autoreleasepool {
                try processor.restore(buffer, settings: settings, control: control, onWait: onWait)
            }
            let waitingSince = ProcessInfo.processInfo.systemUptime
            while !input.isReadyForMoreMediaData {
                try control.checkpoint(gentle: settings.gentleProcessing, onWait: onWait)
                guard writer.status == .writing else { throw writer.error ?? LiftError.message("The encoder stopped unexpectedly.") }
                guard ProcessInfo.processInfo.systemUptime - waitingSince < 120 else { throw LiftError.message("The encoder stopped responding.") }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard adaptor.append(restored, withPresentationTime: time) else {
                throw writer.error ?? LiftError.message("The encoder rejected a video frame.")
            }
            frames += 1
            lastOutputTime = time
            latestFraction = min(0.9, time.seconds / length * 0.9)
            progress(WorkProgress(fraction: latestFraction, stage: "\(settings.usesRestoration ? "Enhancing" : "Processing") frames", frames: frames))
        }
        guard var previous = try readFrame() else { throw LiftError.message("The video contains no decodable frames.") }
        if settings.fps == 0 {
            try await append(previous.buffer, at: previous.time)
            while let next = try readFrame() {
                if next.time >= duration { break }
                try await append(next.buffer, at: next.time)
            }
        } else {
            var clock = FrameClock(fps: settings.fps)
            while let next = try readFrame() {
                let gap = CMTimeSubtract(next.time, previous.time).seconds
                let cut = autoreleasepool { processor.isSceneCut(previous.buffer, next.buffer) } || gap > 0.5
                while clock.time < next.time && clock.time < duration {
                    try control.checkpoint(gentle: settings.gentleProcessing, onWait: onWait)
                    let fraction = FrameClock.fraction(at: clock.time, between: previous.time, and: next.time)
                    let frame: CVPixelBuffer
                    if cut { frame = fraction < 0.5 ? previous.buffer : next.buffer }
                    else { frame = try autoreleasepool { try processor.interpolate(previous.buffer, next.buffer, fraction: fraction) } }
                    try await append(frame, at: clock.time)
                    clock.advance()
                }
                previous = next
                if clock.time >= duration { break }
            }
            while clock.time < duration {
                try await append(previous.buffer, at: clock.time)
                clock.advance()
            }
        }
        guard frames > 0 else { throw LiftError.message("No output frames were generated.") }
        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? LiftError.message("The video could not be finalized.") }
        try control.checkpoint(gentle: settings.gentleProcessing, onWait: onWait)
        progress(WorkProgress(fraction: 0.92, stage: "Preserving audio", frames: frames))
        let expectedAudio = try await assemble(video: temporary, source: asset, sourceRange: range,
                                               output: output, preserveAudio: settings.preserveAudio, control: control)
        progress(WorkProgress(fraction: 0.97, stage: "Verifying your export", frames: frames))
        try await verify(output, width: width, height: height, frames: frames, duration: length,
                         audioTracks: expectedAudio, control: control)
        let bytes = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? 0
        let hash = try fingerprint(output, control: control)
        succeeded = true
        progress(WorkProgress(fraction: 1, stage: "Ready", frames: frames))
        return ExportResult(url: output, frames: frames, bytes: bytes, sha256: hash, duration: length)
    }
    private func assemble(video: URL, source: AVURLAsset, sourceRange: CMTimeRange, output: URL,
                          preserveAudio: Bool, control: WorkControl) async throws -> Int {
        let sourceAudio = preserveAudio ? try await source.loadTracks(withMediaType: .audio) : []
        if sourceAudio.isEmpty {
            try FileManager.default.moveItem(at: video, to: output)
            return 0
        }
        let videoAsset = AVURLAsset(url: video)
        let composition = AVMutableComposition()
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let destinationVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw LiftError.message("Could not prepare the final video.")
        }
        try destinationVideo.insertTimeRange(CMTimeRange(start: .zero, duration: sourceRange.duration), of: sourceVideo, at: .zero)
        destinationVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)
        var count = 0
        for track in sourceAudio {
            let intersection = CMTimeRangeGetIntersection(try await track.load(.timeRange), otherRange: sourceRange)
            guard intersection.isValid, intersection.duration > .zero else { continue }
            guard let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw LiftError.message("Could not preserve an audio track.")
            }
            try audio.insertTimeRange(intersection, of: track, at: CMTimeSubtract(intersection.start, sourceRange.start))
            count += 1
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw LiftError.message("The original audio cannot be combined with this video.")
        }
        session.metadata = []
        session.timeRange = CMTimeRange(start: .zero, duration: sourceRange.duration)
        try control.checkpoint()
        try await withTaskCancellationHandler(operation: {
            try await session.export(to: output, as: .mov)
        }, onCancel: { session.cancelExport() })
        try control.checkpoint()
        return count
    }
    private func verify(_ url: URL, width: Int, height: Int, frames: Int, duration: Double,
                        audioTracks: Int, control: WorkControl) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let description = try await track.load(.formatDescriptions).first else {
            throw LiftError.message("Export verification found no video track.")
        }
        let size = CMVideoFormatDescriptionGetDimensions(description)
        let actualDuration = try await track.load(.timeRange).duration.seconds
        guard size.width == width, size.height == height, abs(actualDuration - duration) < 0.12,
              try await asset.loadTracks(withMediaType: .audio).count == audioTracks else {
            throw LiftError.message("The exported dimensions, timing or audio did not match the requested settings.")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { throw LiftError.message("Cannot verify the exported frames.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? LiftError.message("Cannot inspect the finished video.") }
        defer { reader.cancelReading() }
        var count = 0
        var last = CMTime.invalid
        while let sample = output.copyNextSampleBuffer() {
            try control.checkpoint()
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard !last.isValid || timestamp > last else { throw LiftError.message("The exported video has invalid frame ordering.") }
            last = timestamp
            count += CMSampleBufferGetNumSamples(sample)
        }
        guard reader.status == .completed, count == frames else {
            throw LiftError.message("Export verification found missing video frames. The incomplete output was discarded.")
        }
    }
    private func fingerprint(_ url: URL, control: WorkControl) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try control.checkpoint()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
