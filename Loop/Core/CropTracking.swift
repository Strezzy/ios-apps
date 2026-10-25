import Foundation

/// Subject observations stay in upright source coordinates, independently of overlays.
/// The crop is a camera move over those coordinates, never a transform of their tracks.
struct CropTrackingSettings: Codable, Equatable, Sendable {
    var enabled = false
    var subjectRect = NormalizedRect.centered
    var anchorTime: Double = 0
    var keyframes: [TrackingKeyframe] = []
    var followScale = true
    var needsReview = false

    func rect(at time: Double) -> NormalizedRect {
        guard let first = keyframes.first, let last = keyframes.last else { return subjectRect.clamped() }
        if !time.isFinite || time <= first.time { return first.rect.clamped() }
        if time >= last.time { return last.rect.clamped() }
        var low = 0, high = keyframes.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if keyframes[middle].time <= time { low = middle } else { high = middle }
        }
        let span = keyframes[high].time - keyframes[low].time
        return .interpolate(keyframes[low].rect, keyframes[high].rect,
                            fraction: span > 0 ? (time - keyframes[low].time) / span : 0)
    }

    func covers(start: Double, end: Double) -> Bool {
        guard start.isFinite, end.isFinite, end > start,
              anchorTime.isFinite, keyframes.count >= 2,
              let first = keyframes.first, let last = keyframes.last,
              first.time <= start + 0.02, last.time >= end - 0.02,
              anchorTime >= first.time - 0.0001, anchorTime <= last.time + 0.0001,
              Self.valid(subjectRect),
              keyframes.allSatisfy({ $0.time.isFinite && $0.confidence.isFinite &&
                  $0.confidence >= 0.3 && Self.valid($0.rect) }),
              zip(keyframes, keyframes.dropFirst()).allSatisfy({ pair in pair.0.time < pair.1.time }) else { return false }
        return true
    }

    private static func valid(_ rect: NormalizedRect) -> Bool {
        rect.x.isFinite && rect.y.isFinite && rect.width.isFinite && rect.height.isFinite &&
        rect.width > 0 && rect.height > 0 && rect.width <= 1 && rect.height <= 1 &&
        rect.x >= -0.0001 && rect.y >= -0.0001 &&
        rect.x + rect.width <= 1.0001 && rect.y + rect.height <= 1.0001
    }
}

extension CropSettings {
    /// Preserve the composition chosen at the anchor, then pan with the subject.
    /// Optional size-follow keeps its apparent size by zooming out as it approaches.
    /// Source edges and the 1×–8× framing limit always take precedence.
    func rect(source: PixelSize, at time: Double) -> NormalizedRect {
        let base = rect(source: source)
        guard let tracking, tracking.enabled, !tracking.keyframes.isEmpty else { return base }
        let subject = tracking.rect(at: time)
        let anchor = tracking.subjectRect.clamped()
        var scale = 1.0
        if tracking.followScale {
            let ratio = (subject.width * subject.height) / (anchor.width * anchor.height)
            scale = ratio.isFinite && ratio > 0 ? sqrt(ratio) : 1
        }
        let ratio = aspect.ratio(source: source)
        let fullWidth = min(1, ratio / source.aspect)
        let fullHeight = min(1, source.aspect / ratio)
        // Scale both axes by the same amount, including at the source boundary.
        let minimumScale = max(fullWidth / 8 / base.width, fullHeight / 8 / base.height)
        let maximumScale = min(fullWidth / base.width, fullHeight / base.height)
        scale = min(maximumScale, max(minimumScale, scale))
        let width = base.width * scale, height = base.height * scale
        let centerX = subject.centerX + (base.centerX - anchor.centerX) * scale
        let centerY = subject.centerY + (base.centerY - anchor.centerY) * scale
        return NormalizedRect(x: min(1 - width, max(0, centerX - width / 2)),
                              y: min(1 - height, max(0, centerY - height / 2)),
                              width: width, height: height)
    }

    /// The output canvas is fixed, while source decoding must cover the tightest
    /// tracked zoom in the chosen clip. This is evaluated once per export, not per frame.
    func minimumRect(source: PixelSize, from start: Double, through end: Double) -> NormalizedRect {
        var minimum = rect(source: source)
        guard let tracking, tracking.enabled, tracking.followScale else { return minimum }
        let times = [start, end] + tracking.keyframes.filter { $0.time > start && $0.time < end }.map(\.time)
        for time in times {
            let current = rect(source: source, at: time)
            if current.width < minimum.width { minimum = current }
        }
        return minimum
    }

    /// Translate a visible crop drag back into the user's anchor composition.
    func framingScale(source: PixelSize, at time: Double) -> Double {
        rect(source: source, at: time).width / rect(source: source).width
    }
}

enum CropTrackingPath {
    /// A small symmetric temporal filter reduces box jitter without the directional
    /// lag of a playback-time filter. Export, reverse and scrubbing share one path.
    /// The user's anchor and path endpoints remain exact.
    static func smoothed(_ input: [TrackingKeyframe], anchorTime: Double) -> [TrackingKeyframe] {
        guard input.count > 2 else { return input }
        let radius = 0.10
        return input.indices.map { index in
            let key = input[index]
            guard index > 0, index < input.count - 1,
                  abs(key.time - anchorTime) > 0.00001 else { return key }
            var x = 0.0, y = 0.0, logWidth = 0.0, logHeight = 0.0, total = 0.0
            var first = index, last = index
            while first > 0, key.time - input[first - 1].time < radius { first -= 1 }
            while last + 1 < input.count, input[last + 1].time - key.time < radius { last += 1 }
            for neighbor in first...last {
                let sample = input[neighbor]
                let weight = max(0, 1 - abs(sample.time - key.time) / radius)
                let rect = sample.rect.clamped()
                total += weight
                x += rect.centerX * weight; y += rect.centerY * weight
                logWidth += log(rect.width) * weight; logHeight += log(rect.height) * weight
            }
            let width = exp(logWidth / total), height = exp(logHeight / total)
            var result = key
            result.rect = NormalizedRect(x: x / total - width / 2, y: y / total - height / 2,
                                         width: width, height: height).clamped()
            return result
        }
    }
}
