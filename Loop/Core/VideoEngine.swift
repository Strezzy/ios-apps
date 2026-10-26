import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
@preconcurrency import AVFoundation

/// Explicit control is shared by export and tracking. Pausing never blocks the UI thread.
final class ExportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func pause() { lock.lock(); paused = true; lock.unlock() }
    func resume() { lock.lock(); paused = false; lock.unlock() }
    private func state() -> (cancelled: Bool, paused: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (cancelled, paused)
    }
    func checkpoint() async throws {
        while true {
            try Task.checkCancellation()
            let current = state()
            if current.cancelled { throw LoopError.cancelled }
            // Thermal state is tested each frame. The work can always be cancelled while cooling.
            if !current.paused && ProcessInfo.processInfo.thermalState != .critical { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }
}

enum MediaEngine {
    static func inspect(url: URL) async throws -> VideoMetadata {
        guard url.isFileURL else { throw LoopError.invalidVideo("Choose a video stored on your device.") }
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable), !(try await asset.load(.hasProtectedContent)),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LoopError.invalidVideo("This file is not a readable video. Choose a video format supported by your iPhone.")
        }
        let duration = try await asset.load(.duration).seconds
        let (natural, transform, rate, descriptions) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
        let displayed = CGRect(origin: .zero, size: natural).applying(transform).standardized
        guard duration.isFinite, duration >= 0.02, displayed.width.isFinite, displayed.height.isFinite,
              displayed.width >= 1, displayed.height >= 1,
              displayed.width <= 32768, displayed.height <= 32768 else {
            throw LoopError.invalidVideo("The video has no usable picture or duration.")
        }
        var hdr = false
        for description in descriptions {
            guard let rawExtensions = CMFormatDescriptionGetExtensions(description) else { continue }
            let extensions = rawExtensions as NSDictionary
            if let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String {
                hdr = hdr || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
                          || transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            }
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return VideoMetadata(name: url.deletingPathExtension().lastPathComponent,
                             duration: duration,
                             size: PixelSize(width: Int(displayed.width.rounded()), height: Int(displayed.height.rounded())),
                             nominalFrameRate: Double(rate.isFinite && rate > 0 ? rate : 30),
                             isHDR: hdr, byteCount: Int64(bytes))
    }

    static func thumbnail(url: URL, time: Double, maximumDimension: Int = 1000) async throws -> CGImage {
        let generator = makeGenerator(url: url, maximumDimension: maximumDimension)
        let duration = try await generator.asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw LoopError.invalidVideo("The video has no frames to preview.") }
        // Stay at least one CMTime tick before EOF; a smaller epsilon rounds back to EOF.
        let clamped = min(max(0, duration - 1.0 / 60_000), max(0, time.isFinite ? time : 0))
        return try await generator.image(at: CMTime(seconds: clamped, preferredTimescale: 60_000)).image
    }

    static func makeGenerator(url: URL, maximumDimension: Int, preserveHDR: Bool = false) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.dynamicRangePolicy = preserveHDR ? .matchSource : .forceSDR
        if maximumDimension > 0 {
            generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        }
        return generator
    }
}

actor ExportEngine {
    func export(sourceURL: URL, project: LoopProject, destination: URL,
                control: ExportControl, progress: @escaping @Sendable (ExportProgress) -> Void) async throws -> ExportResult {
        CreativeAssets.register(project, url: sourceURL)
        if project.export.format.isVideo {
            return try await VideoFileExporter.export(sourceURL: sourceURL, project: project, destination: destination,
                                                      control: control, progress: progress)
        }
        let plan = try ExportPlan(project: project)
        let realismSession = RealismSession()
        try await control.checkpoint()
        guard sourceURL.isFileURL, destination.isFileURL,
              FileManager.default.fileExists(atPath: sourceURL.path),
              !FileManager.default.fileExists(atPath: destination.path) else {
            throw LoopError.encoding("Choose a new local export filename and keep the original video available.")
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".loop-\(UUID().uuidString).partial")
        var complete = false
        defer {
            if !complete { try? FileManager.default.removeItem(at: partial) }
            FrameRenderer.clearCaches()
        }
        let available = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage) ?? 0
        guard available == 0 || available > 32_000_000 else {
            throw LoopError.encoding("Your iPhone needs more free space to start this export.")
        }
        progress(ExportProgress(fraction: 0, completedFrames: 0, totalFrames: plan.frames.count,
                                message: "Preparing \(project.export.format.title)"))
        let writer: any AnimationWriter
        if project.export.format == .gif {
            writer = try GIFEncoder(destination: partial, size: plan.size,
                                    frameCount: plan.frames.count, settings: project.export)
        } else {
            writer = try APNGEncoder(destination: partial, size: plan.size,
                                     frameCount: plan.frames.count, settings: project.export)
        }
        let crop = project.crop.minimumRect(source: project.metadata.size,
            from: project.trimStart, through: project.trimEnd)
        // Decode only the source resolution needed by the selected crop/output.
        // A single source frame and a single processed frame are retained, including reverse playback.
        let requiredSourceEdge = Int(ceil(max(Double(plan.size.width) / crop.width,
                                              Double(plan.size.height) / crop.height)))
        let generator = MediaEngine.makeGenerator(url: sourceURL,
            maximumDimension: min(project.metadata.size.longEdge, requiredSourceEdge))
        defer { generator.cancelAllCGImageGeneration() }
        if project.export.stableGIFPalette == true, let gif = writer as? GIFEncoder {
            let sampleGenerator=MediaEngine.makeGenerator(url:sourceURL,maximumDimension:256)
            defer {sampleGenerator.cancelAllCGImageGeneration()}
            var thumbnails=[CGImage]()
            var sampleProject=project;sampleProject.effects?.matteTuning?.showMask=false
            for i in 0..<min(8,plan.frames.count) {
                try await control.checkpoint()
                let frame=plan.frames[i*(plan.frames.count-1)/max(1,min(8,plan.frames.count)-1)]
                let source=try await sampleGenerator.image(at:CMTime(seconds:frame.sourceTime,preferredTimescale:60_000)).image
                thumbnails.append(try FrameRenderer.render(source,project:sampleProject,time:frame.sourceTime,maximumDimension:128))
                progress(ExportProgress(fraction:0,completedFrames:0,totalFrames:plan.frames.count,message:"Choosing consistent GIF colors…"))
            }
            try gif.prepareStablePalette(thumbnails)
        }
        for (index, frame) in plan.frames.enumerated() {
            if ProcessInfo.processInfo.thermalState == .critical {
                progress(ExportProgress(fraction: Double(index) / Double(plan.frames.count), completedFrames: index,
                                        totalFrames: plan.frames.count, message: "Cooling down · export will resume"))
            }
            try await control.checkpoint()
            let source = try await generator.image(at:
                CMTime(seconds: frame.sourceTime, preferredTimescale: 60_000)).image
            try await control.checkpoint()
            try autoreleasepool {
                let rendered = try FrameRenderer.render(source, project: project, time: frame.sourceTime, effectsSession: realismSession)
                try writer.add(rendered, delay: frame.delay, gifDelayCentiseconds: frame.gifDelayCentiseconds)
            }
            if index % 16 == 0 {
                let remaining = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                    .volumeAvailableCapacityForImportantUsage) ?? 0
                guard remaining == 0 || remaining > 16_000_000 else {
                    throw LoopError.encoding("Storage filled up while exporting. The incomplete file has been removed.")
                }
            }
            let completed = index + 1
            progress(ExportProgress(fraction: Double(completed) / Double(plan.frames.count), completedFrames: completed,
                                    totalFrames: plan.frames.count, message: "Rendering frame \(completed) of \(plan.frames.count)"))
            // Give the cooperative executor and media services regular scheduling opportunities.
            await Task.yield()
            if ProcessInfo.processInfo.thermalState == .serious {
                try await Task.sleep(nanoseconds: 30_000_000)
            }
        }
        try await control.checkpoint()
        try writer.finish()
        try await control.checkpoint()
        try FileManager.default.moveItem(at: partial, to: destination)
        complete = true
        let bytes = (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ExportResult(url: destination, size: plan.size, frameCount: plan.frames.count,
                            duration: plan.duration, byteCount: Int64(bytes))
    }
}
