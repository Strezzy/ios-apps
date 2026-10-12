import Foundation
@preconcurrency import AVFoundation
import CoreVideo
import AudioToolbox

/// Decodes into uncompressed samples and constructs a new movie. It never copies
/// source compressed packets, metadata tracks, chapters or container metadata.
enum VideoCleaner {
    static func audit(_ url: URL) async throws -> Audit {
        let asset = AVURLAsset(url: url)
        var fields = Set<String>()
        func collect(_ items: [AVMetadataItem], prefix: String) {
            for item in items {
                let name = item.identifier?.rawValue ?? String(describing: item.key ?? "unknown" as NSString)
                fields.insert(prefix + name)
            }
        }
        collect(try await asset.load(.metadata), prefix: "Container: ")
        for format in try await asset.load(.availableMetadataFormats) {
            collect(try await asset.loadMetadata(for: format), prefix: "Container: ")
        }
        let tracks = try await asset.load(.tracks)
        for track in tracks {
            collect(try await track.load(.metadata), prefix: "Track: ")
            for format in try await track.load(.availableMetadataFormats) {
                collect(try await track.loadMetadata(for: format), prefix: "Track: ")
            }
            if track.mediaType != .video && track.mediaType != .audio {
                fields.insert("Additional track: " + track.mediaType.rawValue)
            }
        }
        let duration = try await asset.load(.duration).seconds
        return Audit(fields: fields.sorted(), mediaDescription: String(format: "%.1f seconds", duration))
    }

    static func rebuild(_ input: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> (URL, [String]) {
        let asset = AVURLAsset(url: input)
        guard !(try await asset.load(.hasProtectedContent)) else {
            throw RinseError.message("Protected videos cannot be processed.")
        }
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        guard videos.count == 1, audios.count <= 1, let video = videos.first else {
            throw RinseError.message("Version 1 supports one video track and at most one audio track.")
        }
        for characteristic: AVMediaCharacteristic in [.containsHDRVideo, .containsStereoMultiviewVideo, .containsAlphaChannel, .usesWideGamutColorSpace] {
            if video.hasMediaCharacteristic(characteristic) {
                throw RinseError.message("HDR, wide-color, spatial and transparent videos are not supported in version 1. Export an SDR copy first; your original is unchanged.")
            }
        }
        let size = try await video.load(.naturalSize)
        let transform = try await video.load(.preferredTransform)
        let fps = try await video.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0, width % 2 == 0, height % 2 == 0,
              max(width, height) <= 4096, width * height <= 4096 * 2160,
              fps <= 60.1, duration.seconds.isFinite, duration.seconds > 0 else {
            throw RinseError.message("Choose an SDR video up to 4K and 60 fps, with even pixel dimensions.")
        }
        let bitRate = Int(min(64_000_000, max(8_000_000, Double(width * height) * Double(max(fps, 24)) * 0.16)))
        try Workspace.checkSpace(for: Int64(min(duration.seconds * Double(bitRate) / 8 * 1.25, Double(Int64.max / 4))))
        let output = Workspace.destination(extension: "mp4")
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        var completed = false
        defer {
            if !completed {
                reader.cancelReading(); writer.cancelWriting()
                try? FileManager.default.removeItem(at: output)
            }
        }
        writer.metadata = []
        writer.shouldOptimizeForNetworkUse = false
        writer.directoryForTemporaryFiles = Workspace.root
        let pixels = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
        pixels.alwaysCopiesSampleData = false
        let encoded = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitRate,
                                              AVVideoAllowFrameReorderingKey: false],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]])
        encoded.transform = transform
        encoded.metadata = []
        encoded.expectsMediaDataInRealTime = false
        guard reader.canAdd(pixels), writer.canAdd(encoded) else { throw RinseError.message("Video conversion is unavailable for this file.") }
        reader.add(pixels); writer.add(encoded)
        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?
        if let audio = audios.first {
            let formats = try await audio.load(.formatDescriptions)
            guard let format = formats.first, let description = CMAudioFormatDescriptionGetStreamBasicDescription(format) else {
                throw RinseError.message("This audio format could not be read.")
            }
            let channels = Int(description.pointee.mChannelsPerFrame)
            let rate = description.pointee.mSampleRate
            guard (1...2).contains(channels), rate >= 8_000, rate <= 96_000 else {
                throw RinseError.message("Version 1 supports mono or stereo audio, not surround audio.")
            }
            let decoded = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false])
            decoded.alwaysCopiesSampleData = false
            let compressed = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: min(rate, 48_000),
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: channels == 1 ? 128_000 : 256_000])
            compressed.metadata = []; compressed.expectsMediaDataInRealTime = false
            guard reader.canAdd(decoded), writer.canAdd(compressed) else { throw RinseError.message("This audio track cannot be converted.") }
            reader.add(decoded); writer.add(compressed)
            audioOutput = decoded; audioInput = compressed
        }
        guard writer.startWriting() else { throw writer.error ?? RinseError.message("The movie writer could not start.") }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else { throw reader.error ?? RinseError.message("The video reader could not start.") }
        var videoDone = false, audioDone = audioOutput == nil
        var count = 0
        var lastProgress = 0.0
        var lastMovement = Date()
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            if ProcessInfo.processInfo.thermalState == .critical {
                throw RinseError.message("Processing stopped because your iPhone became too warm. Let it cool and retry this item.")
            }
            if reader.status == .failed { throw reader.error ?? RinseError.message("Video decoding failed.") }
            if writer.status == .failed { throw writer.error ?? RinseError.message("Video encoding failed.") }
            var moved = false
            if !videoDone && encoded.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let buffer = pixels.copyNextSampleBuffer() {
                        guard encoded.append(buffer) else { throw writer.error ?? RinseError.message("A video frame could not be written.") }
                        count += 1
                        let fraction = max(0, min(0.98, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / duration.seconds))
                        if fraction - lastProgress >= 0.01 { progress(fraction); lastProgress = fraction }
                    } else {
                        if reader.status == .failed { throw reader.error ?? RinseError.message("Video decoding failed.") }
                        // EOF belongs to this track, even while another track is reading.
                        encoded.markAsFinished(); videoDone = true
                    }
                }
                moved = true
            }
            if !audioDone, let decoded = audioOutput, let compressed = audioInput, compressed.isReadyForMoreMediaData {
                try autoreleasepool {
                    if let buffer = decoded.copyNextSampleBuffer() {
                        guard compressed.append(buffer) else { throw writer.error ?? RinseError.message("An audio sample could not be written.") }
                    } else {
                        if reader.status == .failed { throw reader.error ?? RinseError.message("Audio decoding failed.") }
                        compressed.markAsFinished(); audioDone = true
                    }
                }
                moved = true
            }
            if moved { lastMovement = Date() }
            else {
                if Date().timeIntervalSince(lastMovement) > 45 { throw RinseError.message("The encoder stopped responding. No unfinished file was exported.") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
        }
        guard count > 0 else { throw RinseError.message("This video contains no readable frames.") }
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw writer.error ?? RinseError.message("The cleaned video could not be completed.") }
        let result = AVURLAsset(url: output)
        let outputDuration = try await result.load(.duration)
        let outputVideos = try await result.loadTracks(withMediaType: .video)
        let outputAudios = try await result.loadTracks(withMediaType: .audio)
        guard abs(outputDuration.seconds - duration.seconds) <= 0.15,
              outputVideos.count == 1, outputAudios.count == audios.count else {
            throw RinseError.message("The exported video's timing or tracks failed verification.")
        }
        completed = true
        return (output, ["Rebuilt as high-quality SDR H.264 / AAC MP4. Resolution, frame timestamps and orientation are retained; encoding is lossy.",
            "Metadata tracks, chapters and subtitles are omitted. Visible faces, text, watermarks and audible speech remain."])
    }
}
