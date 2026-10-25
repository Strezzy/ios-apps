import Foundation

extension OverlayItem {
    /// Keep visibility inside the clip without moving the playhead or discarding
    /// position keyframes. Crossing the other endpoint moves that endpoint just
    /// enough to keep a nonempty interval, so “here” still means the visible frame.
    mutating func setVisibleStart(_ time: Double, within clip: ClosedRange<Double>) {
        guard time.isFinite, clip.lowerBound.isFinite, clip.upperBound.isFinite,
              clip.upperBound > clip.lowerBound else { return }
        let minimumDuration = min(0.001, clip.upperBound - clip.lowerBound)
        let start = min(clip.upperBound - minimumDuration, max(clip.lowerBound, time))
        let end = min(clip.upperBound, max(start + minimumDuration, endTime))
        setVisibility(start: start, end: end)
    }

    mutating func setVisibleEnd(_ time: Double, within clip: ClosedRange<Double>) {
        guard time.isFinite, clip.lowerBound.isFinite, clip.upperBound.isFinite,
              clip.upperBound > clip.lowerBound else { return }
        let minimumDuration = min(0.001, clip.upperBound - clip.lowerBound)
        let end = min(clip.upperBound, max(clip.lowerBound + minimumDuration, time))
        let start = max(clip.lowerBound, min(end - minimumDuration, startTime))
        setVisibility(start: start, end: end)
    }

    mutating func useWholeClip(_ clip: ClosedRange<Double>) {
        guard clip.lowerBound.isFinite, clip.upperBound.isFinite,
              clip.upperBound > clip.lowerBound else { return }
        setVisibility(start: clip.lowerBound, end: clip.upperBound)
    }

    private mutating func setVisibility(start: Double, end: Double) {
        startTime = start
        endTime = end
        // A shorter visibility interval can reuse its existing motion path. A
        // longer one must not silently treat extrapolated positions as tracked.
        if trackingEnabled {
            guard let first = keyframes.first, let last = keyframes.last else {
                trackingNeedsReview = true
                return
            }
            if start < first.time - 0.0001 || end > last.time + 0.0001 {
                trackingNeedsReview = true
            }
        }
    }
}
