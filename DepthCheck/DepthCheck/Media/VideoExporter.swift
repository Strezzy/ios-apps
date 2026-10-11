import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import CryptoKit
import VideoToolbox

/// Streaming conversion with one processed frame and one source lookahead.
/// No frame-rate preset, video-composition frameDuration, or segment join is used.
final class VideoExporter {
    private let source: MediaSource
    private let options: ConversionOptions
    private let outputDirectory: URL
    private let renderer: StereoRenderer
    private let asset: AVURLAsset
    private var videoTrack: AVAssetTrack?
    private var audioTracks: [AVAssetTrack] = []
    private var transform = CGAffineTransform.identity
    private var size = PixelSize(width: 0, height: 0)
    private var duration = CMTime.zero
    private var videoEndTime = CMTime.zero
    private var nominalRate: Double = 0
    private var timeScale: CMTimeScale = 60_000
    private var sourceIsHDR = false

    init(source: MediaSource, options: ConversionOptions, outputDirectory: URL, renderer: StereoRenderer) {
        self.source = source
        self.options = options
        self.outputDirectory = outputDirectory
        self.renderer = renderer
        self.asset = AVURLAsset(url: source.url)
    }

    func prepare(onProgress: @Sendable (ConversionProgress) -> Void) async throws {
        try Task.checkCancellation()
        if options.format == .spatial, !VTIsStereoMVHEVCEncodeSupported() {
            throw DepthCheckError.message("This device does not support native MV-HEVC spatial video encoding. Choose Side by Side or Separate Eyes to keep both views at the full source resolution.")
        }
        onProgress(.init(fraction: 0.005, stage: "Checking source video"))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DepthCheckError.message("This file does not contain a readable video track.")
        }
        let (naturalSize, preferredTransform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        size = PixelSize(width: Int(bounds.width.rounded()), height: Int(bounds.height.rounded()))
        transform = preferredTransform
        nominalRate = Double(rate)
        duration = try await asset.load(.duration)
        videoEndTime = try await track.load(.timeRange).end
        timeScale = max(1, try await track.load(.naturalTimeScale))
        guard size.width > 0, size.height > 0,
              duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 else {
            throw DepthCheckError.message("The source has invalid dimensions or duration.")
        }
        videoTrack = track
        audioTracks = options.preserveAudio ? try await asset.loadTracks(withMediaType: .audio) : []
        let descriptions = try await track.load(.formatDescriptions)
        sourceIsHDR = source.isHDR || descriptions.contains { description in
            guard let transfer = CMFormatDescriptionGetExtension(description,
                extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else { return false }
            return transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
                || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
        }
        let outputSize = options.format.outputSize(for: size)
        guard outputSize.width <= 16_384, outputSize.height <= 16_384 else {
            throw unsupportedSize(outputSize, detail: "The requested packed image exceeds the texture limit.")
        }
        onProgress(.init(fraction: 0.015, stage: "Checking full-resolution encoder"))
        try await preflight(size: outputSize)
    }

    func export(predictDepth: DepthPrediction,
                onProgress: @Sendable (ConversionProgress) -> Void) async throws -> ExportResult {
        guard let videoTrack else { throw DepthCheckError.message("Video preparation did not finish.") }
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: Self.readerSettings)
        decoded.alwaysCopiesSampleData = false
        guard reader.canAdd(decoded) else { throw DepthCheckError.message("The source video could not be decoded.") }
        reader.add(decoded)

        let names = options.format == .separateEyes ? ["Left-Eye.mov", "Right-Eye.mov"] : ["Depth-Check-\(options.format.rawValue).mov"]
        var outputs: [VideoOutput] = []
        do {
            for name in names {
                let output = try VideoOutput(url: outputDirectory.appendingPathComponent(name),
                    settings: writerSettings(size: options.format.outputSize(for: size)),
                    spatial: options.format == .spatial, timeScale: timeScale)
                outputs.append(output)
                try await output.addAudio(tracks: audioTracks, asset: asset)
            }
            for output in outputs { try output.start() }
            guard reader.startReading() else { throw reader.error ?? DepthCheckError.message("Video decoding could not start.") }
            // One-frame lookahead recovers a missing sample duration from the
            // next original PTS. It never determines a new frame rate.
            var nextSourceSample = decoded.copyNextSampleBuffer()

            let metadata = VirtualStereoMetadata(options: options)
            var timings = FrameTimingLedger()
            var videoFinished = false
            var lastProgressAt = Date()
            let estimate = nominalRate > 0 ? Int(min(Double(Int.max), (duration.seconds * nominalRate).rounded())) : 0
            while !videoFinished || outputs.contains(where: { !$0.audioFinished }) {
                try Task.checkCancellation()
                for output in outputs { try output.checkStatus() }
                var madeProgress = false
                // Separate audio readers prevent a blocked video reader from
                // retaining decoded frames while waiting for interleaved audio.
                let audioHorizon = videoFinished ? nil : CMTimeAdd(timings.lastPTS ?? .zero, CMTime(seconds: 1, preferredTimescale: 600))
                for output in outputs {
                    madeProgress = try autoreleasepool { try output.pumpAudio(until: audioHorizon) } || madeProgress
                    madeProgress = try output.pumpVideo() || madeProgress
                }
                if !videoFinished, outputs.allSatisfy({ $0.isReadyForVideoFrame }) {
                    let frameRead = try autoreleasepool { () throws -> Bool in
                        guard let sample = nextSourceSample else {
                            if reader.status == .failed { throw reader.error ?? DepthCheckError.message("Source video decoding failed.") }
                            return false
                        }
                        nextSourceSample = decoded.copyNextSampleBuffer()
                        if reader.status == .failed { throw reader.error ?? DepthCheckError.message("Source video decoding failed.") }
                        guard let buffer = CMSampleBufferGetImageBuffer(sample) else {
                            throw DepthCheckError.message("A source frame could not be decoded. The export was stopped instead of dropping it.")
                        }
                        let pts = CMSampleBufferGetOutputPresentationTimeStamp(sample)
                        let declaredDuration = CMSampleBufferGetOutputDuration(sample)
                        let nextPTS = nextSourceSample.map(CMSampleBufferGetOutputPresentationTimeStamp) ?? videoEndTime
                        let frameDuration = declaredDuration.isNumeric && CMTimeCompare(declaredDuration, .zero) > 0
                            ? declaredDuration : CMTimeSubtract(nextPTS, pts)
                        guard frameDuration.isNumeric, CMTimeCompare(frameDuration, .zero) > 0 else {
                            throw DepthCheckError.message("A source frame has no recoverable duration. The export was stopped rather than inventing its timing.")
                        }
                        try timings.record(pts: pts, duration: frameDuration)
                        let image = Self.orientedImage(buffer, transform: transform)
                        guard Int(image.extent.width.rounded()) == size.width,
                              Int(image.extent.height.rounded()) == size.height else {
                            throw DepthCheckError.message("The source changed dimensions during playback. No resized export was created.")
                        }
                        let depth = try predictDepth(image, options.temporalStability)
                        try Task.checkCancellation()
                        if options.format == .depthMap {
                            let depthBuffer = try renderer.depthPixelBuffer(depth: depth, size: size)
                            try outputs[0].append(buffer: depthBuffer, pts: pts, duration: frameDuration)
                        } else {
                            let spatial = options.format == .spatial
                            let pair = try renderer.render(source: image,
                                depth: spatial ? metadata.spatialDepth(depth) : depth,
                                options: spatial ? metadata.unshiftedOptions : options)
                            switch options.format {
                            case .spatial:
                                try outputs[0].append(pair: pair, pts: pts, duration: frameDuration)
                            case .separateEyes:
                                try outputs[0].append(buffer: pair.left, pts: pts, duration: frameDuration)
                                try outputs[1].append(buffer: pair.right, pts: pts, duration: frameDuration)
                            case .sideBySide, .overUnder, .anaglyph:
                                let packed = try renderer.packed(pair: pair, format: options.format)
                                try outputs[0].append(buffer: packed, pts: pts, duration: frameDuration)
                            case .depthMap:
                                preconditionFailure("Depth-map conversion is handled before stereo rendering")
                            }
                        }
                        return true
                    }
                    madeProgress = true
                    if frameRead {
                        if options.memorySaver, timings.count.isMultiple(of: 24) { renderer.purgeCaches() }
                        let progress = min(0.94, max(0, (timings.lastPTS?.seconds ?? 0) / duration.seconds) * 0.9 + 0.04)
                        onProgress(.init(fraction: progress, stage: "Converting at full resolution",
                                         framesProcessed: timings.count, totalFramesEstimate: estimate))
                    } else {
                        videoFinished = true
                        for output in outputs { try output.finishVideoInput() }
                    }
                }
                if madeProgress {
                    lastProgressAt = Date()
                } else {
                    guard Date().timeIntervalSince(lastProgressAt) < 180 else {
                        throw DepthCheckError.message("The encoder stopped accepting full-resolution frames. Close other large apps, enable Memory Saver, and retry; no lower-quality export was saved.")
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
            guard timings.count > 0 else { throw DepthCheckError.message("The source contains no decodable video frames.") }
            onProgress(.init(fraction: 0.95, stage: "Finishing video and audio", framesProcessed: timings.count))
            let endTime = CMTimeMaximum(duration, timings.endTime)
            for output in outputs {
                // Explicitly retain the last frame's duration; finishing at its
                // presentation timestamp would truncate the source timeline.
                output.writer.endSession(atSourceTime: endTime)
                await output.writer.finishWriting()
                try Task.checkCancellation()
                guard output.writer.status == .completed else {
                    throw output.writer.error ?? DepthCheckError.message("The video could not be finalized.")
                }
            }
            onProgress(.init(fraction: 0.98, stage: "Verifying every frame timestamp", framesProcessed: timings.count))
            for output in outputs {
                try await Self.verify(url: output.url, size: options.format.outputSize(for: size),
                                      timings: timings, audioTrackCount: audioTracks.count,
                                      spatialMetadata: options.format == .spatial ? metadata : nil)
            }
            var note = "Every source frame and its original presentation timestamp was preserved. No resolution or frame-rate downgrade."
            if sourceIsHDR { note += " HDR was intentionally tone-mapped to SDR Rec.709." }
            else { note += " Video is encoded as SDR HEVC." }
            if !audioTracks.isEmpty { note += " Original audio tracks were copied without re-encoding." }
            if options.format == .spatial { note += " Spatial metadata describes the synthetic virtual cameras." }
            if options.format == .depthMap { note += " Estimated depth is upsampled to source dimensions." }
            return ExportResult(files: outputs.map(\.url), sourceName: source.name, format: options.format,
                                size: options.format.outputSize(for: size), frameCount: timings.count,
                                frameRate: nominalRate, duration: endTime.seconds, note: note)
        } catch {
            reader.cancelReading()
            for output in outputs { output.cancel() }
            throw error
        }
    }

    static let colorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    static var readerSettings: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
         kCVPixelBufferMetalCompatibilityKey as String: true,
         kCVPixelBufferIOSurfacePropertiesKey as String: [:],
         // Tone mapping happens together with 10-bit -> 8-bit conversion.
         AVVideoColorPropertiesKey: colorProperties]
    }

    static func orientedImage(_ buffer: CVPixelBuffer, transform: CGAffineTransform) -> CIImage {
        // Track transforms use top-left display coordinates, whereas Core Image
        // uses bottom-left coordinates. Conjugating the transform avoids turning
        // portrait clips in the opposite direction or mirroring their contents.
        let toDisplay = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                         tx: 0, ty: CGFloat(CVPixelBufferGetHeight(buffer)))
        let toCoreImage = CGAffineTransform(scaleX: 1, y: -1)
        let ciTransform = toDisplay.concatenating(transform).concatenating(toCoreImage)
        let oriented = CIImage(cvPixelBuffer: buffer).transformed(by: ciTransform)
        return oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
    }

    private func writerSettings(size: PixelSize) -> [String: Any] {
        let rateHint = nominalRate > 0 ? nominalRate : 60
        let pixels = Double(size.width) * Double(size.height) * (options.format == .spatial ? 2 : 1)
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(min(300_000_000, max(2_000_000, pixels * rateHint * 0.15))),
            AVVideoExpectedSourceFrameRateKey: rateHint,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalKey: max(1, Int((rateHint * 2).rounded())),
            kVTCompressionPropertyKey_RealTime as String: false
        ]
        if options.format == .spatial {
            let spatial = VirtualStereoMetadata(options: options)
            compression[kVTCompressionPropertyKey_MVHEVCVideoLayerIDs as String] = [0, 1]
            compression[kVTCompressionPropertyKey_MVHEVCViewIDs as String] = [0, 1]
            compression[kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs as String] = [0, 1]
            compression[kVTCompressionPropertyKey_HasLeftStereoEyeView as String] = true
            compression[kVTCompressionPropertyKey_HasRightStereoEyeView as String] = true
            compression[kVTCompressionPropertyKey_ProjectionKind as String] = kCMFormatDescriptionProjectionKind_Rectilinear
            compression[kVTCompressionPropertyKey_StereoCameraBaseline as String] = UInt32((options.virtualBaselineMillimeters * 1_000).rounded())
            compression[kVTCompressionPropertyKey_HorizontalFieldOfView as String] = UInt32((options.horizontalFieldOfViewDegrees * 1_000).rounded())
            compression[kVTCompressionPropertyKey_HorizontalDisparityAdjustment as String] = Int32((spatial.disparityAdjustment * 10_000).rounded())
        } else {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel
        }
        return [AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
                AVVideoColorPropertiesKey: Self.colorProperties,
                AVVideoCompressionPropertiesKey: compression]
    }

    private func preflight(size: PixelSize) async throws {
        let url = outputDirectory.appendingPathComponent("encoder-check.mov")
        defer {
            // AVAssetWriter may already remove its file after a failed encode.
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
        }
        let output: VideoOutput
        do {
            output = try VideoOutput(url: url, settings: writerSettings(size: size),
                                     spatial: options.format == .spatial, timeScale: timeScale)
        } catch { throw unsupportedSize(size, detail: error.localizedDescription) }
        do {
            try output.start()
            let frame = try Self.blankBuffer(size: size)
            // Each tagged eye owns a distinct surface, just as in a real render.
            // Reusing one CVPixelBuffer for both tags is not a valid capability
            // probe for an encoder that requires separate multiview images.
            let rightFrame = options.format == .spatial ? try Self.blankBuffer(size: size) : nil
            let frameDuration = CMTime(seconds: 1 / max(1, nominalRate), preferredTimescale: timeScale)
            for index in 0..<2 {
                let began = Date()
                while !output.isReadyForVideoFrame {
                    try Task.checkCancellation()
                    try output.checkStatus()
                    _ = try output.pumpVideo()
                    guard Date().timeIntervalSince(began) < 30 else {
                        throw DepthCheckError.message("The device did not accept the requested encoder configuration.")
                    }
                    try await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTimeMultiply(frameDuration, multiplier: Int32(index))
                if let rightFrame {
                    try output.append(pair: StereoPair(left: frame, right: rightFrame), pts: pts, duration: frameDuration)
                } else {
                    try output.append(buffer: frame, pts: pts, duration: frameDuration)
                }
            }
            let drainBegan = Date()
            while output.hasPendingVideo {
                try Task.checkCancellation()
                try output.checkStatus()
                _ = try output.pumpVideo()
                guard Date().timeIntervalSince(drainBegan) < 30 else {
                    throw DepthCheckError.message("The device did not finish the full-resolution encoder check.")
                }
                if output.hasPendingVideo { try await Task.sleep(for: .milliseconds(5)) }
            }
            try output.finishVideoInput()
            output.writer.endSession(atSourceTime: CMTimeMultiply(frameDuration, multiplier: 2))
            await output.writer.finishWriting()
            try Task.checkCancellation()
            guard output.writer.status == .completed else {
                throw output.writer.error ?? DepthCheckError.message("The encoder rejected the test frames.")
            }
        } catch {
            // Keep the original encoder error before cancellation can update
            // AVAssetWriter.error or remove an incomplete output file.
            let wasCancelled = error is CancellationError
            let native = error as NSError
            let detail = "\(native.localizedDescription) (\(native.domain), \(native.code))"
            output.cancel()
            if wasCancelled { throw CancellationError() }
            throw unsupportedSize(size, detail: detail)
        }
    }

    private func unsupportedSize(_ size: PixelSize, detail: String) -> DepthCheckError {
        let alternative = options.format == .separateEyes
            ? "This device cannot encode this exact size with the requested settings."
            : "Try Separate Eyes, which keeps each eye at the source resolution in its own file."
        return .message("The device could not encode \(size.label) at the source frame timing. \(alternative) No pixels or frames were reduced.\n\n\(detail)")
    }

    static func blankBuffer(size: PixelSize) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                                         kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height, kCVPixelFormatType_32BGRA,
                                  attributes as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else {
            throw DepthCheckError.message("There is not enough available memory for a full-resolution encoder test.")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) { memset(base, 0, CVPixelBufferGetBytesPerRow(buffer) * size.height) }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private static func verify(url: URL, size: PixelSize, timings: FrameTimingLedger,
                               audioTrackCount: Int, spatialMetadata: VirtualStereoMetadata?) async throws {
        let result = AVURLAsset(url: url)
        guard let track = try await result.loadTracks(withMediaType: .video).first else {
            throw DepthCheckError.message("The exported video is missing its video track.")
        }
        let dimensions = try await track.load(.naturalSize)
        guard Int(dimensions.width.rounded()) == size.width, Int(dimensions.height.rounded()) == size.height else {
            throw DepthCheckError.message("The encoder changed the requested dimensions. The export was rejected.")
        }
        let audio = try await result.loadTracks(withMediaType: .audio)
        guard audio.count == audioTrackCount else {
            throw DepthCheckError.message("The encoder did not preserve all requested audio tracks. The export was rejected.")
        }
        if let spatialMetadata {
            let stereoTracks = try await result.loadTracks(withMediaCharacteristic: .containsStereoMultiviewVideo)
            let descriptions = try await track.load(.formatDescriptions)
            guard stereoTracks.contains(where: { $0.trackID == track.trackID }), let description = descriptions.first else {
                throw DepthCheckError.message("The encoder did not create a stereoscopic multiview track. The export was rejected.")
            }
            let layers: [Int64] = (description.tagCollections ?? []).flatMap { $0 }.compactMap {
                $0.value(onlyIfMatching: .videoLayerID)
            }
            func number(_ key: CFString) -> NSNumber? {
                CMFormatDescriptionGetExtension(description, extensionKey: key) as? NSNumber
            }
            let projection = CMFormatDescriptionGetExtension(description,
                extensionKey: kCMFormatDescriptionExtension_ProjectionKind) as? String
            guard Set(layers) == Set([Int64(0), Int64(1)]),
                  number(kCMFormatDescriptionExtension_HasLeftStereoEyeView)?.boolValue == true,
                  number(kCMFormatDescriptionExtension_HasRightStereoEyeView)?.boolValue == true,
                  projection == (kCMFormatDescriptionProjectionKind_Rectilinear as String),
                  number(kCMFormatDescriptionExtension_StereoCameraBaseline)?.uint32Value
                    == UInt32((spatialMetadata.options.virtualBaselineMillimeters * 1_000).rounded()),
                  number(kCMFormatDescriptionExtension_HorizontalFieldOfView)?.uint32Value
                    == UInt32((spatialMetadata.options.horizontalFieldOfViewDegrees * 1_000).rounded()),
                  number(kCMFormatDescriptionExtension_HorizontalDisparityAdjustment)?.int32Value
                    == Int32((spatialMetadata.disparityAdjustment * 10_000).rounded()) else {
                throw DepthCheckError.message("The encoded movie is missing its two eye layers or required spatial camera metadata. The incomplete spatial export was rejected.")
            }
        }
        let reader = try AVAssetReader(asset: result)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DepthCheckError.message("The export could not be verified.") }
        var exported = FrameTimingLedger()
        while true {
            try Task.checkCancellation()
            let read = try autoreleasepool { () throws -> Bool in
                guard let sample = output.copyNextSampleBuffer() else { return false }
                try VideoSampleTiming.forEach(in: sample) { timing in
                    try exported.record(pts: timing.presentationTimeStamp, duration: timing.duration)
                }
                return true
            }
            if !read { break }
        }
        guard reader.status == .completed, exported.count == timings.count,
              exported.signature == timings.signature, CMTimeCompare(exported.endTime, timings.endTime) == 0 else {
            throw DepthCheckError.message("The encoded frame count, timestamps, or final frame duration differ from the source. The export was rejected instead of keeping altered timing.")
        }
    }
}

/// A compressed reader can coalesce several video samples into one buffer or
/// return a zero-sample marker describing an empty timeline interval. Neither
/// changes the number of encoded frames. Read every actual sample's own timing.
enum VideoSampleTiming {
    static func forEach(in buffer: CMSampleBuffer, _ visit: (CMSampleTimingInfo) throws -> Void) throws {
        let count = CMSampleBufferGetNumSamples(buffer)
        guard count >= 0 else { throw DepthCheckError.message("The encoded sample count is invalid.") }
        if count == 0 {
            guard CMSampleBufferGetTotalSampleSize(buffer) == 0, CMSampleBufferGetImageBuffer(buffer) == nil else {
                throw DepthCheckError.message("An encoded buffer contains media without a sample count. Its frame timing cannot be verified.")
            }
            return
        }
        for index in 0..<count {
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
            let status = CMSampleBufferGetSampleTimingInfo(buffer, at: index, timingInfoOut: &timing)
            guard status == noErr else {
                throw DepthCheckError.message("An encoded frame's timing could not be read (Core Media \(status)).")
            }
            try visit(timing)
        }
    }
}

/// A constant-memory record of the exact rational presentation timestamps.
/// Encoder verification never needs to retain a movie's worth of frames or times.
struct FrameTimingLedger {
    private var hash = SHA256()
    private(set) var count = 0
    private(set) var lastPTS: CMTime?
    private(set) var endTime = CMTime.zero

    mutating func record(pts: CMTime, duration: CMTime) throws {
        guard pts.isNumeric, pts.timescale > 0, CMTimeCompare(pts, .zero) >= 0,
              lastPTS.map({ CMTimeCompare(pts, $0) > 0 }) ?? true else {
            throw DepthCheckError.message("The source has duplicate, invalid, or out-of-order frame timestamps. The export was stopped rather than changing the frame timing.")
        }
        var a = pts.value.magnitude, b = UInt64(pts.timescale)
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        let divisor = Int64(max(1, a))
        let canonical = "\(pts.value / divisor)/\(Int64(pts.timescale) / divisor)@\(pts.epoch);"
        hash.update(data: Data(canonical.utf8))
        count += 1
        lastPTS = pts
        endTime = CMTimeMaximum(endTime, duration.isNumeric && CMTimeCompare(duration, .zero) > 0 ? CMTimeAdd(pts, duration) : pts)
    }

    var signature: String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
}

private final class VideoOutput {
    let url: URL
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    private let spatialEncoder: SpatialVideoEncoder?
    private var pendingSpatialSample: CMSampleBuffer?
    private var videoDescription: CMVideoFormatDescription?
    private var audio: [AudioCopyStream] = []

    init(url: URL, settings: [String: Any], spatial: Bool, timeScale: CMTimeScale) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.movieTimeScale = timeScale
        if !spatial, !writer.canApply(outputSettings: settings, forMediaType: .video) {
            throw DepthCheckError.message("The HEVC writer does not accept these dimensions and settings.")
        }
        spatialEncoder = spatial ? try SpatialVideoEncoder(settings: settings) : nil
        // VideoToolbox emits compressed media of type Video. QuickTime .mov
        // accepts this pass-through input without a source format hint; the first
        // compressed sample supplies the complete multiview format description.
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: spatial ? nil : settings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = timeScale
        guard writer.canAdd(videoInput) else { throw DepthCheckError.message("A full-resolution video track could not be created.") }
        writer.add(videoInput)
    }

    func addAudio(tracks: [AVAssetTrack], asset: AVAsset) async throws {
        for track in tracks {
            let stream = try await AudioCopyStream(track: track, asset: asset)
            guard writer.canAdd(stream.input) else {
                throw DepthCheckError.message("An original audio track cannot be copied into this movie. Turn off Preserve Audio only if you want a silent export.")
            }
            writer.add(stream.input)
            audio.append(stream)
        }
    }

    func start() throws {
        guard writer.startWriting() else { throw writer.error ?? DepthCheckError.message("The video encoder could not start.") }
        writer.startSession(atSourceTime: .zero)
        for stream in audio { try stream.start() }
    }

    var audioFinished: Bool { audio.allSatisfy(\.finished) }

    var hasPendingVideo: Bool { pendingSpatialSample != nil }
    var isReadyForVideoFrame: Bool { pendingSpatialSample == nil && videoInput.isReadyForMoreMediaData }

    func pumpAudio(until time: CMTime?) throws -> Bool {
        var progressed = false
        for stream in audio { progressed = try stream.pump(until: time) || progressed }
        return progressed
    }

    func append(pair: StereoPair, pts: CMTime, duration: CMTime) throws {
        guard let spatialEncoder else { throw DepthCheckError.message("A stereo frame was sent to a single-view output.") }
        guard pendingSpatialSample == nil else {
            throw DepthCheckError.message("The previous spatial frame has not finished writing.")
        }
        pendingSpatialSample = try spatialEncoder.encode(pair: pair, pts: pts, duration: duration)
        _ = try pumpVideo()
    }

    /// Retain at most one compressed frame when the movie interleaver applies
    /// backpressure. The caller can keep pumping audio before trying again.
    func pumpVideo() throws -> Bool {
        guard let sample = pendingSpatialSample, videoInput.isReadyForMoreMediaData else { return false }
        guard videoInput.append(sample) else {
            throw writer.error ?? DepthCheckError.message("The movie writer rejected a compressed spatial frame. No frame was skipped.")
        }
        pendingSpatialSample = nil
        return true
    }

    func finishVideoInput() throws {
        guard pendingSpatialSample == nil else { throw DepthCheckError.message("A spatial frame is still waiting to be written.") }
        spatialEncoder?.invalidate()
        videoInput.markAsFinished()
    }

    func append(buffer: CVPixelBuffer, pts: CMTime, duration: CMTime) throws {
        if videoDescription == nil {
            guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                formatDescriptionOut: &videoDescription) == noErr else {
                throw DepthCheckError.message("The rendered video frame has an unsupported pixel format.")
            }
        }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
            formatDescription: videoDescription!, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample, videoInput.append(sample) else {
            throw writer.error ?? DepthCheckError.message("The encoder rejected a full-resolution frame. No frame was skipped.")
        }
    }

    func checkStatus() throws {
        if writer.status == .failed || writer.status == .cancelled {
            throw writer.error ?? DepthCheckError.message("The video encoder stopped before the conversion finished.")
        }
    }

    func cancel() {
        for stream in audio { stream.reader.cancelReading() }
        pendingSpatialSample = nil
        spatialEncoder?.invalidate()
        if writer.status == .writing { writer.cancelWriting() }
        if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
    }
}

/// VideoToolbox's multiview entry point accepts both PTS and explicit duration.
/// The AVFoundation tagged-pixel adaptor/receiver only accepts PTS, while a raw
/// TaggedBufferGroup sample is not media type Video and cannot be appended to a
/// video AVAssetWriterInput. Encode here, then mux ordinary compressed samples.
private final class SpatialVideoEncoder {
    private var session: VTCompressionSession?

    init(settings: [String: Any]) throws {
        guard let width = settings[AVVideoWidthKey] as? Int,
              let height = settings[AVVideoHeightKey] as? Int,
              width > 0, height > 0, width <= Int(Int32.max), height <= Int(Int32.max),
              let compression = settings[AVVideoCompressionPropertiesKey] as? [String: Any] else {
            throw DepthCheckError.message("The full-resolution spatial encoder settings are invalid.")
        }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var created: VTCompressionSession?
        let creation = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &created)
        guard creation == noErr, let created else {
            throw Self.failure(creation, operation: "Creating the full-resolution MV-HEVC encoder")
        }
        session = created
        do {
            // AVAssetWriter compression names are not all VideoToolbox names.
            // Convert the generic controls and retain the native multiview keys.
            var properties: [String: Any] = [:]
            for (key, value) in compression {
                let destination: CFString
                switch key {
                case AVVideoAverageBitRateKey: destination = kVTCompressionPropertyKey_AverageBitRate
                case AVVideoExpectedSourceFrameRateKey: destination = kVTCompressionPropertyKey_ExpectedFrameRate
                case AVVideoAllowFrameReorderingKey: destination = kVTCompressionPropertyKey_AllowFrameReordering
                case AVVideoMaxKeyFrameIntervalKey: destination = kVTCompressionPropertyKey_MaxKeyFrameInterval
                case AVVideoProfileLevelKey: destination = kVTCompressionPropertyKey_ProfileLevel
                default: destination = key as CFString
                }
                properties[destination as String] = value
            }
            if let colors = settings[AVVideoColorPropertiesKey] as? [String: String] {
                properties[kVTCompressionPropertyKey_ColorPrimaries as String] = colors[AVVideoColorPrimariesKey]
                properties[kVTCompressionPropertyKey_TransferFunction as String] = colors[AVVideoTransferFunctionKey]
                properties[kVTCompressionPropertyKey_YCbCrMatrix as String] = colors[AVVideoYCbCrMatrixKey]
            }
            let configured = VTSessionSetProperties(created, propertyDictionary: properties as CFDictionary)
            guard configured == noErr else { throw Self.failure(configured, operation: "Configuring multiview encoding and spatial metadata") }
            let prepared = VTCompressionSessionPrepareToEncodeFrames(created)
            guard prepared == noErr else { throw Self.failure(prepared, operation: "Preparing the full-resolution MV-HEVC encoder") }
        } catch {
            invalidate()
            throw error
        }
    }

    func encode(pair: StereoPair, pts: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        try Task.checkCancellation()
        guard let session else { throw DepthCheckError.message("The spatial encoder has already finished.") }
        let tagged = [
            CMTaggedBuffer(tags: [.videoLayerID(0), .stereoView(.leftEye)], buffer: .pixelBuffer(pair.left)),
            CMTaggedBuffer(tags: [.videoLayerID(1), .stereoView(.rightEye)], buffer: .pixelBuffer(pair.right))
        ]
        let frame = SpatialEncodedFrame()
        var flags: VTEncodeInfoFlags = []
        let encoded = VTCompressionSessionEncodeMultiImageFrame(session, taggedBuffers: tagged,
            presentationTimeStamp: pts, duration: duration, frameProperties: nil, infoFlagsOut: &flags) {
                status, info, sample in frame.receive(status: status, flags: info, sample: sample)
            }
        guard encoded == noErr else { throw Self.failure(encoded, operation: "Encoding a full-resolution stereo frame") }
        guard !flags.contains(.frameDropped) else {
            throw DepthCheckError.message("The multiview encoder dropped a frame. The export was stopped to preserve the source frame count.")
        }
        // Only one submitted frame is outstanding. CompleteFrames guarantees
        // its output callback has been emitted before returning, bounding the
        // encoder's application-owned input/output queue without segment joins.
        let completed = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: pts)
        guard completed == noErr else { throw Self.failure(completed, operation: "Completing a full-resolution stereo frame") }
        try Task.checkCancellation()
        let sample = try frame.take()
        guard let format = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(format) == kCMMediaType_Video,
              CMSampleBufferDataIsReady(sample) else {
            throw DepthCheckError.message("The multiview encoder did not return a ready compressed video sample.")
        }
        return sample
    }

    func invalidate() {
        if let session { VTCompressionSessionInvalidate(session) }
        session = nil
    }

    deinit { invalidate() }

    private static func failure(_ status: OSStatus, operation: String) -> DepthCheckError {
        .message("\(operation) failed (VideoToolbox \(status)).")
    }
}

/// The encoder may invoke its output handler on another thread. The lock guards
/// a single result, and no callback touches AVAssetWriter or the render buffers.
private final class SpatialEncodedFrame: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<CMSampleBuffer, DepthCheckError>?

    func receive(status: OSStatus, flags: VTEncodeInfoFlags, sample: CMSampleBuffer?) {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else {
            result = .failure(.message("The multiview encoder returned more than one result for a source frame."))
            return
        }
        guard status == noErr, !flags.contains(.frameDropped), let sample else {
            result = .failure(.message("The multiview encoder failed to produce a source frame (VideoToolbox \(status)). No frame was skipped."))
            return
        }
        result = .success(sample)
    }

    func take() throws -> CMSampleBuffer {
        lock.lock()
        defer { lock.unlock() }
        guard let result else {
            throw DepthCheckError.message("The multiview encoder finished without returning a source frame. The incomplete export was stopped.")
        }
        return try result.get()
    }
}

private final class AudioCopyStream {
    let reader: AVAssetReader
    let input: AVAssetWriterInput
    private let output: AVAssetReaderTrackOutput
    private var pending: CMSampleBuffer?
    private(set) var finished = false

    init(track: AVAssetTrack, asset: AVAsset) async throws {
        let formats = try await track.load(.formatDescriptions)
        guard let format = formats.first else { throw DepthCheckError.message("The source audio format is unreadable.") }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw DepthCheckError.message("The original audio track cannot be read.") }
        reader.add(output)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
    }

    func start() throws {
        guard reader.startReading() else { throw reader.error ?? DepthCheckError.message("Original audio copying could not start.") }
    }

    func pump(until horizon: CMTime?) throws -> Bool {
        guard !finished else { return false }
        var progressed = false
        // A small cap makes cancellation and video work responsive even for
        // sources containing many tiny audio packets.
        var packets = 0
        while input.isReadyForMoreMediaData, packets < 32 {
            try Task.checkCancellation()
            guard let sample = pending ?? output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw reader.error ?? DepthCheckError.message("Original audio could not be fully copied.") }
                input.markAsFinished()
                finished = true
                return true
            }
            if let horizon, CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), horizon) > 0 {
                pending = sample
                break
            }
            guard input.append(sample) else {
                throw DepthCheckError.message("The movie writer rejected an original audio packet. The incomplete export was stopped.")
            }
            pending = nil
            packets += 1
            progressed = true
        }
        return progressed
    }
}
