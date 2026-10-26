import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import CoreMedia
import AudioToolbox
@preconcurrency import AVFoundation

extension PixelSize {
    var videoAligned: PixelSize { PixelSize(width: max(2, width - width % 2), height: max(2, height - height % 2)) }
}

/// Streaming video writer. At most one source frame and one output frame are retained.
/// Audio is read concurrently to avoid starving either AVAssetWriter input.
enum VideoFileExporter {
    private final class Session: @unchecked Sendable {
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        var audio: AVAssetWriterInput?
        var audioReader: AVAssetReader?
        var audioOutput: AVAssetReaderAudioMixOutput?
        let context = CIContext(options: [.cacheIntermediates: false])
        init(url: URL, project: LoopProject, plan: ExportPlan) throws {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let codec: AVVideoCodecType = project.export.format == .hevc ? .hevc : .h264
            let bitRate = min(120_000_000, max(2_000_000, Int(Double(plan.size.width * plan.size.height) * project.export.frameRate * (codec == .hevc ? 0.10 : 0.15))))
            var compression: [String: Any] = [AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: project.export.frameRate,
                AVVideoMaxKeyFrameIntervalKey: max(1, Int(project.export.frameRate * 2))]
            if codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            let settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: plan.size.width,
                AVVideoHeightKey: plan.size.height, AVVideoCompressionPropertiesKey: compression,
                AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_IEC_sRGB,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]]
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
                throw LoopError.encoding("This device cannot encode these video settings. Try MP4 or a smaller resolution.")
            }
            video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            video.expectsMediaDataInRealTime = false
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: plan.size.width, kCVPixelBufferHeightKey as String: plan.size.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
            guard writer.canAdd(video) else { throw LoopError.encoding("The video encoder could not be started.") }
            writer.add(video); writer.shouldOptimizeForNetworkUse = true
        }
        func prepareAudio(sourceURL: URL, project: LoopProject, duration: Double) async throws {
            guard project.export.includeAudio != false, project.export.playback == .forward else { return }
            let source = AVURLAsset(url: sourceURL)
            guard let original = try await source.loadTracks(withMediaType: .audio).first else { return }
            let sourceRange = try await original.load(.timeRange)
            let trim = CMTimeRange(start: CMTime(seconds: project.trimStart, preferredTimescale: 60_000), duration: CMTime(seconds: project.duration, preferredTimescale: 60_000))
            let intersection = CMTimeRangeGetIntersection(trim, otherRange: sourceRange)
            guard intersection.duration.seconds > 0 else { return }
            let composition = AVMutableComposition()
            guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw LoopError.encoding("The audio track could not be prepared.")
            }
            try track.insertTimeRange(intersection, of: original, at: CMTimeSubtract(intersection.start, trim.start))
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: trim.duration), toDuration: CMTime(seconds: duration, preferredTimescale: 60_000))
            let reader = try AVAssetReader(asset: composition)
            let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false])
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTimePitchAlgorithm = .timeDomain
            let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]; output.audioMix = mix
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { throw LoopError.encoding("This video's audio could not be decoded. Disable Include audio to export a silent video.") }
            reader.add(output)
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw LoopError.encoding("The audio encoder is unavailable. Disable Include audio to export a silent video.") }
            writer.add(input); audio = input; audioReader = reader; audioOutput = output
        }
        func waitForInput(_ input: AVAssetWriterInput, control: ExportControl) async throws {
            var waits = 0
            while !input.isReadyForMoreMediaData {
                try await control.checkpoint()
                guard writer.status == .writing else { throw writer.error ?? LoopError.encoding("Video encoding stopped unexpectedly.") }
                waits += 1
                guard waits < 24_000 else { throw LoopError.encoding("The video encoder stopped responding. Try a smaller output size.") }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }
    static func export(sourceURL: URL, project: LoopProject, destination: URL,
                       control: ExportControl, progress: @escaping @Sendable (ExportProgress) -> Void) async throws -> ExportResult {
        let plan = try ExportPlan(project: project)
        guard sourceURL.isFileURL, destination.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path), !FileManager.default.fileExists(atPath: destination.path) else {
            throw LoopError.encoding("Keep the source video available and choose a new local export filename.")
        }
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".loop-\(UUID().uuidString).mp4")
        let session = try Session(url: temporary, project: project, plan: plan)
        var complete = false
        defer {
            if !complete { session.writer.cancelWriting(); session.audioReader?.cancelReading(); try? FileManager.default.removeItem(at: temporary) }
            session.context.clearCaches(); FrameRenderer.clearCaches()
        }
        try await control.checkpoint()
        try await session.prepareAudio(sourceURL: sourceURL, project: project, duration: plan.duration)
        guard session.writer.startWriting() else { throw session.writer.error ?? LoopError.encoding("The video encoder could not start.") }
        session.writer.startSession(atSourceTime: .zero)
        if let reader = session.audioReader, !reader.startReading() { throw reader.error ?? LoopError.encoding("Audio decoding could not start.") }
        progress(ExportProgress(fraction: 0, completedFrames: 0, totalFrames: plan.frames.count, message: "Preparing \(project.export.format.title) video"))
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                guard let input = session.audio, let output = session.audioOutput, let reader = session.audioReader else { return }
                while true {
                    try await control.checkpoint(); try await session.waitForInput(input, control: control)
                    let more = try autoreleasepool { () throws -> Bool in
                        guard let sample = output.copyNextSampleBuffer() else { return false }
                        guard input.append(sample) else { throw session.writer.error ?? LoopError.encoding("Audio could not be written.") }
                        return true
                    }
                    if !more { break }
                    await Task.yield()
                }
                guard reader.status != .failed, reader.status != .cancelled else { throw reader.error ?? LoopError.encoding("Audio decoding was interrupted.") }
                input.markAsFinished()
            }
            group.addTask {
                let crop = project.crop.minimumRect(source: project.metadata.size, from: project.trimStart, through: project.trimEnd)
                let required = Int(ceil(max(Double(plan.size.width) / crop.width, Double(plan.size.height) / crop.height)))
                let generator = MediaEngine.makeGenerator(url: sourceURL, maximumDimension: min(project.metadata.size.longEdge, required))
                defer { generator.cancelAllCGImageGeneration() }
                var outputTime = 0.0
                for (index, frame) in plan.frames.enumerated() {
                    try await control.checkpoint()
                    try await session.waitForInput(session.video, control: control)
                    let source = try await generator.image(at: CMTime(seconds: frame.sourceTime, preferredTimescale: 60_000)).image
                    try await control.checkpoint()
                    try autoreleasepool {
                        let rendered = try FrameRenderer.render(source, project: project, time: frame.sourceTime)
                        guard let pool = session.adaptor.pixelBufferPool else { throw LoopError.encoding("The video buffer pool is unavailable.") }
                        var buffer: CVPixelBuffer?
                        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw LoopError.encoding("Not enough memory for this video frame. Choose a smaller resolution.") }
                        let bounds = CGRect(x: 0, y: 0, width: plan.size.width, height: plan.size.height)
                        session.context.render(CIImage(cgImage: rendered), to: buffer, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                        guard session.adaptor.append(buffer, withPresentationTime: CMTime(seconds: outputTime, preferredTimescale: 60_000)) else { throw session.writer.error ?? LoopError.encoding("A video frame could not be encoded.") }
                    }
                    outputTime += frame.delay
                    if index % 16 == 0 {
                        let remaining = (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
                        guard remaining == 0 || remaining > 32_000_000 else { throw LoopError.encoding("Storage is full. The unfinished video has been removed.") }
                    }
                    progress(ExportProgress(fraction: Double(index + 1) / Double(plan.frames.count) * 0.98, completedFrames: index + 1, totalFrames: plan.frames.count, message: "Rendering video frame \(index + 1) of \(plan.frames.count)"))
                    await Task.yield()
                    if ProcessInfo.processInfo.thermalState == .serious { try await Task.sleep(nanoseconds: 30_000_000) }
                }
                session.video.markAsFinished()
            }
            do { while let _ = try await group.next() { } }
            catch { group.cancelAll(); session.writer.cancelWriting(); session.audioReader?.cancelReading(); throw error }
        }
        try await control.checkpoint()
        session.writer.endSession(atSourceTime: CMTime(seconds: plan.duration, preferredTimescale: 60_000))
        progress(ExportProgress(fraction: 0.99, completedFrames: plan.frames.count, totalFrames: plan.frames.count, message: "Finishing video"))
        await session.writer.finishWriting()
        guard session.writer.status == .completed else { throw session.writer.error ?? LoopError.encoding("The video could not be finalized.") }
        try await control.checkpoint()
        let verified = try await MediaEngine.inspect(url: temporary)
        guard verified.size == plan.size, abs(verified.duration - plan.duration) < 0.15 else { throw LoopError.encoding("The saved video's dimensions or duration did not match the edit.") }
        try FileManager.default.moveItem(at: temporary, to: destination); complete = true
        progress(ExportProgress(fraction: 1, completedFrames: plan.frames.count, totalFrames: plan.frames.count, message: "Video ready"))
        let bytes = (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ExportResult(url: destination, size: plan.size, frameCount: plan.frames.count, duration: plan.duration, byteCount: Int64(bytes))
    }
}
