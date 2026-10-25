import Foundation
import CoreGraphics
import CoreMedia
@preconcurrency import AVFoundation
@preconcurrency import Vision

enum TrackingEngine {
    // Tracking works in upright source coordinates; decoding 4K-sized analysis
    // images is unnecessary. This bound does not alter the source or export size.
    static let analysisMaximumDimension = 960

    static func trackCrop(sourceURL: URL, project: LoopProject, anchorTime: Double,
                          control: ExportControl,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> CropTrackingSettings {
        guard var tracking = project.crop.tracking else {
            throw LoopError.invalidSettings("Select the subject you want the crop to follow.")
        }
        let anchor = min(project.trimEnd, max(project.trimStart, anchorTime))
        guard anchor.isFinite else { throw LoopError.invalidSettings("Choose a frame before tracking the subject.") }
        // Reuse the proven independent object tracker. This temporary item never
        // enters the project's overlay list and cannot replace any overlay path.
        var subject = OverlayItem(kind: .cover, startTime: project.trimStart, endTime: project.trimEnd)
        subject.rect = tracking.subjectRect.clamped()
        let observations = try await track(sourceURL: sourceURL, project: project, overlay: subject,
            anchorTime: anchor, control: control, progress: progress)
        try await control.checkpoint()
        tracking.subjectRect = subject.rect
        tracking.anchorTime = anchor
        tracking.keyframes = CropTrackingPath.smoothed(observations, anchorTime: anchor)
        tracking.enabled = true
        tracking.needsReview = false
        return tracking
    }

    static func track(sourceURL: URL, project: LoopProject, overlay: OverlayItem,
                      anchorTime: Double, control: ExportControl,
                      progress: @escaping @Sendable (Double) -> Void) async throws -> [TrackingKeyframe] {
        let start = max(project.trimStart, overlay.startTime)
        let end = min(project.trimEnd, overlay.endTime)
        guard start.isFinite, end.isFinite, end > start else {
            throw LoopError.invalidSettings("Give the overlay a time range inside the selected clip.")
        }
        let anchor = min(end, max(start, anchorTime))
        let initialRect = overlay.rect(at: anchor).clamped()
        let rate = min(30, max(15, project.metadata.nominalFrameRate))
        let stride = 1.0 / rate
        let forwardCount = max(1, Int(ceil((end - anchor) / stride)))
        let backwardCount = max(1, Int(ceil((anchor - start) / stride)))
        guard forwardCount + backwardCount <= 36_000 else {
            throw LoopError.invalidSettings("Trim the clip to 20 minutes or less before automatic tracking.")
        }
        let generator = MediaEngine.makeGenerator(url: sourceURL, maximumDimension: analysisMaximumDimension)
        defer { generator.cancelAllCGImageGeneration() }
        var result = [TrackingKeyframe(time: anchor, rect: initialRect)]
        var completed = 0
        let total = max(1, forwardCount + backwardCount)
        for direction in [1.0, -1.0] {
            let boundary = direction > 0 ? end : start
            if abs(boundary - anchor) < 0.00001 { continue }
            try await control.checkpoint()
            // Each direction has independent Vision state. The anchor image is
            // scoped inside seed(), so it cannot remain alive for the whole pass.
            let (handler, request) = autoreleasepool {
                let observation = VNDetectedObjectObservation(boundingBox: visionRect(initialRect))
                let request = VNTrackObjectRequest(detectedObjectObservation: observation)
                request.trackingLevel = .accurate
                return (VNSequenceRequestHandler(), request)
            }
            try await seed(generator: generator, handler: handler, request: request,
                           time: anchor, duration: project.metadata.duration, control: control)
            let steps = direction > 0 ? forwardCount : backwardCount
            for step in 1...steps {
                try await control.checkpoint()
                let time = direction > 0 ? min(boundary, anchor + Double(step) * stride)
                                         : max(boundary, anchor - Double(step) * stride)
                let keyframe = try await sample(generator: generator, handler: handler,
                    request: request, time: time, duration: project.metadata.duration,
                    isLastFrame: step == steps, control: control)
                result.append(keyframe)
                completed += 1
                progress(min(0.999, Double(completed) / Double(total)))
                await Task.yield()
            }
        }
        result.sort { $0.time < $1.time }
        progress(1)
        return result
    }

    private static func seed(generator: AVAssetImageGenerator, handler: VNSequenceRequestHandler,
                             request: VNTrackObjectRequest, time: Double, duration: Double,
                             control: ExportControl) async throws {
        let frame = try await generator.image(at: sampleTime(time, duration: duration)).image
        try await control.checkpoint()
        try autoreleasepool {
            try handler.perform([request], on: frame, orientation: .up)
            if let initial = request.results?.first as? VNDetectedObjectObservation {
                request.inputObservation = initial
            }
        }
    }

    /// Only normalized value data leaves this frame scope. Release its image and
    /// temporary Vision objects before reporting progress or requesting the next frame.
    private static func sample(generator: AVAssetImageGenerator, handler: VNSequenceRequestHandler,
                               request: VNTrackObjectRequest, time: Double, duration: Double,
                               isLastFrame: Bool, control: ExportControl) async throws -> TrackingKeyframe {
        let frame = try await generator.image(at: sampleTime(time, duration: duration)).image
        try await control.checkpoint()
        return try autoreleasepool {
            // Vision returns the tracker to its pool when a terminal request FINISHES.
            // Setting this after perform() (as before) never sends a terminal frame.
            request.isLastFrame = isLastFrame
            try handler.perform([request], on: frame, orientation: .up)
            guard let observation = request.results?.first as? VNDetectedObjectObservation,
                  observation.confidence >= 0.3,
                  observation.boundingBox.width > 0.005,
                  observation.boundingBox.height > 0.005 else {
                throw LoopError.trackingLost(time: time)
            }
            request.inputObservation = observation
            let box = observation.boundingBox
            let rect = NormalizedRect(x: box.minX, y: 1 - box.maxY,
                                      width: box.width, height: box.height).clamped()
            return TrackingKeyframe(time: time, rect: rect,
                                     confidence: Double(observation.confidence))
        }
    }

    private static func sampleTime(_ time: Double, duration: Double) -> CMTime {
        CMTime(seconds: min(duration - 1.0 / 60_000, time), preferredTimescale: 60_000)
    }

    static func visionRect(_ rect: NormalizedRect) -> CGRect {
        let r = rect.clamped()
        return CGRect(x: r.x, y: 1 - r.y - r.height, width: r.width, height: r.height)
    }
}
