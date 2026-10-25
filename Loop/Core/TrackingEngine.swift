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
        let rate = min(60, max(15, project.metadata.nominalFrameRate))
        let stride = 1.0 / rate
        let forwardCount = max(1, Int(ceil((end - anchor) * rate - 1e-9)))
        let backwardCount = max(1, Int(ceil((anchor - start) * rate - 1e-9)))
        guard end - start <= 1_200, forwardCount + backwardCount <= 72_002 else {
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
            // Independent appearance, motion and Vision state in each direction.
            // Only the compact appearance descriptor outlives the anchor frame.
            let pass = try await makePass(generator: generator, rect: initialRect,
                time: anchor, duration: project.metadata.duration, control: control)
            let steps = direction > 0 ? forwardCount : backwardCount
            for step in 1...steps {
                try await control.checkpoint()
                let time = direction > 0 ? min(boundary, anchor + Double(step) * stride)
                                         : max(boundary, anchor - Double(step) * stride)
                let keyframes = try await sample(generator: generator, pass: pass,
                    time: time, duration: project.metadata.duration,
                    isLastFrame: step == steps, control: control)
                result.append(contentsOf: keyframes)
                completed += 1
                progress(min(0.999, Double(completed) / Double(total)))
                await Task.yield()
            }
        }
        result.sort { $0.time < $1.time }
        progress(1)
        return result
    }

    private static func makePass(generator: AVAssetImageGenerator, rect: NormalizedRect,
                                 time: Double, duration: Double,
                                 control: ExportControl) async throws -> IdentityPass {
        let frame = try await generator.image(at: sampleTime(time, duration: duration)).image
        try await control.checkpoint()
        return try autoreleasepool { try IdentityPass(frame: frame, rect: rect, time: time) }
    }

    /// Frame images and Vision temporaries are released before progress reporting
    /// or decoding another frame. The pass retains only small identity descriptors.
    private static func sample(generator: AVAssetImageGenerator, pass: IdentityPass,
                               time: Double, duration: Double,
                               isLastFrame: Bool, control: ExportControl) async throws -> [TrackingKeyframe] {
        let frame = try await generator.image(at: sampleTime(time, duration: duration)).image
        try await control.checkpoint()
        return try autoreleasepool { try pass.sample(frame: frame, time: time, isLastFrame: isLastFrame) }
    }

    private struct Candidate {
        let rect: NormalizedRect
        let appearance: TrackingAppearance
        let score: Double
        let confidence: Double
    }

    /// A detector can suggest the same selected subregion on another person box,
    /// but it cannot establish identity. Every suggestion must pass the frozen
    /// appearance, motion and ambiguity checks before it can reset Vision.
    private struct PersonContext {
        let relativeSelection: NormalizedRect
        init?(selection: NormalizedRect, people: [NormalizedRect]) {
            let matches = people.map { person -> (NormalizedRect, Double) in
                let intersection = selection.cgRect.intersection(person.cgRect)
                let area = intersection.isNull ? 0 : Double(intersection.width * intersection.height)
                return (person, area / max(0.000001, selection.width * selection.height))
            }.sorted { $0.1 > $1.1 }
            guard let best = matches.first, best.1 > 0.75,
                  matches.count < 2 || best.1 - matches[1].1 > 0.15 else { return nil }
            let person = best.0
            relativeSelection = NormalizedRect(x: (selection.x - person.x) / person.width,
                y: (selection.y - person.y) / person.height,
                width: selection.width / person.width, height: selection.height / person.height)
        }
        func selection(in person: NormalizedRect) -> NormalizedRect {
            NormalizedRect(x: person.x + relativeSelection.x * person.width,
                y: person.y + relativeSelection.y * person.height,
                width: relativeSelection.width * person.width,
                height: relativeSelection.height * person.height).clamped()
        }
    }

    private final class IdentityPass {
        private var handler = VNSequenceRequestHandler()
        private var request: VNTrackObjectRequest
        private var identity: TrackingIdentity
        private var motion: TrackingMotion
        private let personContext: PersonContext?
        private var pendingTimes: [Double] = []
        private var lastPersonSearch = -Double.infinity
        private let maximumGap = 0.75

        init(frame: CGImage, rect: NormalizedRect, time: Double) throws {
            guard let appearance = TrackingAppearance(image: frame, rect: rect) else {
                throw LoopError.trackingLost(time: time)
            }
            identity = TrackingIdentity(appearance: appearance)
            motion = TrackingMotion(anchor: TrackingKeyframe(time: time, rect: rect))
            request = Self.makeRequest(rect)
            personContext = PersonContext(selection: rect, people: Self.people(in: frame))
            try handler.perform([request], on: frame, orientation: .up)
            // Keep Vision's observation identity to continue the same temporal
            // tracker; the separately stored path/appearance anchor stays exact.
            if let observation = request.results?.first as? VNDetectedObjectObservation {
                request.inputObservation = observation
            }
        }

        func sample(frame: CGImage, time: Double, isLastFrame: Bool) throws -> [TrackingKeyframe] {
            var accepted: Candidate?
            var visionCandidate: NormalizedRect?
            var acceptedVisionObservation: VNDetectedObjectObservation?
            let recovering = !pendingTimes.isEmpty
            if recovering && abs(time - motion.last.time) > maximumGap + 0.0001 {
                finishTracker(on: frame)
                throw LoopError.trackingLost(time: motion.last.time)
            }
            var usedRecovery = false
            if !recovering {
                // The terminal signal must reach perform(), not be set afterward.
                request.isLastFrame = isLastFrame
                try handler.perform([request], on: frame, orientation: .up)
                if let observation = request.results?.first as? VNDetectedObjectObservation,
                   observation.boundingBox.width > 0.005, observation.boundingBox.height > 0.005 {
                    let rect = Self.sourceRect(observation.boundingBox)
                    visionCandidate = rect
                    if observation.confidence >= 0.4,
                       motion.accepts(rect, at: time, recovering: false),
                       let appearance = TrackingAppearance(image: frame, rect: rect),
                       identity.accepts(appearance, recovering: false) {
                        let distance = identity.distances(to: appearance)
                        accepted = Candidate(rect: rect, appearance: appearance,
                            score: distance.anchor * 0.4 + distance.recent * 0.6,
                            confidence: Double(observation.confidence))
                        acceptedVisionObservation = observation
                    }
                }
            }
            // A sudden appearance change with high Vision confidence is the
            // common identity-switch case. Recheck the local alternatives before
            // letting that observation update either the path or template.
            if let candidate = accepted, candidate.score > 0.22 {
                accepted = nil
            }
            if accepted == nil {
                accepted = recover(frame: frame, at: time, visionCandidate: visionCandidate)
                usedRecovery = accepted != nil
            }
            guard let accepted else {
                pendingTimes.append(time)
                // Never save a blind extrapolation or silently continue on the
                // nearest person. An unresolved gap preserves the old saved path.
                if abs(time - motion.last.time) > maximumGap || isLastFrame {
                    finishTracker(on: frame)
                    throw LoopError.trackingLost(time: motion.last.time)
                }
                return []
            }

            let previous = motion.last
            let keyframe = TrackingKeyframe(time: time, rect: accepted.rect, confidence: accepted.confidence)
            var result: [TrackingKeyframe] = []
            if !pendingTimes.isEmpty {
                // Interpolation is permitted only after strict, unambiguous
                // same-appearance recovery. Its confidence marks an estimate,
                // rather than claiming these occluded frames were observed.
                let span = time - previous.time
                result = pendingTimes.map { pending in
                    TrackingKeyframe(time: pending,
                        rect: .interpolate(previous.rect, accepted.rect,
                                           fraction: (pending - previous.time) / span),
                        confidence: 0.3)
                }
            }
            result.append(keyframe)
            motion.accept(keyframe)
            if !usedRecovery { identity.learn(accepted.appearance) }
            if usedRecovery {
                // Discard a contaminated tracker instead of feeding a bystander's
                // internal state back into the verified subject.
                finishTracker(on: frame)
                handler = VNSequenceRequestHandler()
                request = Self.makeRequest(accepted.rect)
                request.isLastFrame = isLastFrame
                try handler.perform([request], on: frame, orientation: .up)
                if let observation = request.results?.first as? VNDetectedObjectObservation {
                    request.inputObservation = observation
                }
            } else if let observation = acceptedVisionObservation {
                request.inputObservation = observation
            }
            pendingTimes.removeAll(keepingCapacity: true)
            return result
        }

        private func recover(frame: CGImage, at time: Double,
                             visionCandidate: NormalizedRect?) -> Candidate? {
            let predicted = motion.predicted(at: time)
            let elapsed = abs(time - motion.last.time)
            let radiusX = max(0.025, predicted.width * (0.4 + elapsed))
            let radiusY = max(0.025, predicted.height * (0.3 + elapsed * 0.6))
            var rectangles: [NormalizedRect] = []
            if let visionCandidate { rectangles.append(visionCandidate) }
            // Bounded multiscale search around the expected trajectory, including
            // the last verified position for a subject that stops or turns.
            rectangles.append(motion.last.rect)
            for scale in [0.9, 1.0, 1.1] {
                for row in -2...2 {
                    for column in -2...2 {
                        let width = predicted.width * scale, height = predicted.height * scale
                        rectangles.append(NormalizedRect(
                            x: predicted.centerX + Double(column) * radiusX / 2 - width / 2,
                            y: predicted.centerY + Double(row) * radiusY / 2 - height / 2,
                            width: width, height: height).clamped())
                    }
                }
            }
            if let personContext, abs(time - lastPersonSearch) >= 0.12 {
                rectangles.append(contentsOf: Self.people(in: frame).map { personContext.selection(in: $0) })
                lastPersonSearch = time
            }
            var candidates: [Candidate] = []
            for rect in rectangles {
                guard motion.accepts(rect, at: time, recovering: true),
                      let appearance = TrackingAppearance(image: frame, rect: rect),
                      identity.accepts(appearance, recovering: true) else { continue }
                let distance = identity.distances(to: appearance)
                let displacement = hypot((rect.centerX - predicted.centerX) / max(0.01, predicted.width),
                                         (rect.centerY - predicted.centerY) / max(0.01, predicted.height))
                let scale = abs(log(rect.width / predicted.width)) + abs(log(rect.height / predicted.height))
                candidates.append(Candidate(rect: rect, appearance: appearance,
                    score: distance.anchor * 0.4 + distance.recent * 0.6 + displacement * 0.035 + scale * 0.025,
                    confidence: 0.6))
            }
            candidates.sort { $0.score < $1.score }
            guard let best = candidates.first else { return nil }
            // Neighboring search windows describe one subject. Compare the next
            // distinct region, not those duplicate windows, for identity ambiguity.
            if let alternative = candidates.dropFirst().first(where: {
                TrackingMotion.overlap(best.rect, $0.rect) < 0.35
            }), alternative.score - best.score < 0.035 { return nil }
            return best
        }

        private func finishTracker(on frame: CGImage) {
            guard !request.isLastFrame else { return }
            request.isLastFrame = true
            // Finish the old sequence before replacing a contaminated tracker.
            // Failure here is irrelevant to the verified new seed, but releasing
            // the request/handler below always releases their bounded resources.
            try? handler.perform([request], on: frame, orientation: .up)
        }

        private static func makeRequest(_ rect: NormalizedRect) -> VNTrackObjectRequest {
            let request = VNTrackObjectRequest(detectedObjectObservation:
                VNDetectedObjectObservation(boundingBox: visionRect(rect)))
            request.trackingLevel = .accurate
            return request
        }

        private static func sourceRect(_ box: CGRect) -> NormalizedRect {
            NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height).clamped()
        }

        private static func people(in image: CGImage) -> [NormalizedRect] {
            let request = VNDetectHumanRectanglesRequest()
            request.upperBodyOnly = false
            // Person detection is only an optional candidate source. Non-person
            // objects and very small overlay regions still use appearance search.
            guard (try? VNImageRequestHandler(cgImage: image, orientation: .up)
                .perform([request])) != nil else { return [] }
            return (request.results ?? []).filter { $0.confidence >= 0.5 }
                .prefix(12).map { sourceRect($0.boundingBox) }
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
