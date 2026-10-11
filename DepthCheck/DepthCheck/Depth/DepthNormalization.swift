import Foundation

/// Stabilizes the *range* of relative inverse depth. It never averages pixels
/// from different frames, which would leave old silhouettes behind moving objects.
/// This is intentionally not advertised as a temporally trained video model.
final class DepthNormalization {
    private struct History {
        var lower: Float
        var upper: Float
        var luma: [Float]
    }

    private var history: History?

    func reset() { history = nil }

    func normalize(_ raw: [Float], isInverseDepth: Bool, luma: [Float], temporal: Bool) throws -> [Float] {
        guard !raw.isEmpty else { throw DepthCheckError.message("The depth model returned an empty image.") }

        var inverse = raw.map { value -> Float in
            guard value.isFinite else { return .nan }
            if isInverseDepth { return value }
            // DA3 predicts depth (farther = larger), unlike DA2's inverse depth.
            guard value > 0 else { return .nan }
            return 1 / max(value, 0.000_001)
        }
        var valid = inverse.filter(\.isFinite)
        guard valid.count * 100 >= raw.count * 95 else {
            throw DepthCheckError.message("The model returned invalid depth values. Try the Balanced model for this media.")
        }
        valid.sort()
        let lower = percentile(valid, fraction: 0.015)
        let upper = percentile(valid, fraction: 0.985)
        let median = percentile(valid, fraction: 0.5)
        let currentSpan = upper - lower
        guard currentSpan > max(0.000_001, abs(median) * 0.000_001) else {
            // A flat depth estimate should be a flat screen plane, not NaN/Inf.
            history = temporal ? History(lower: lower, upper: upper, luma: luma) : nil
            return [Float](repeating: 0.5, count: raw.count)
        }

        var stableLower = lower
        var stableUpper = upper
        if temporal, let previous = history, previous.luma.count == luma.count, !luma.isEmpty {
            let change = frameChange(previous.luma, luma)
            let previousSpan = previous.upper - previous.lower
            let rangeRatio = currentSpan / max(previousSpan, 0.000_001)
            let cut = change.mean > 0.28 || (change.mean > 0.13 && change.histogram > 0.55)
            let changedScale = rangeRatio > 3 || rangeRatio < 1 / 3 || previousSpan <= 0

            if !cut && !changedScale {
                // Follow a moving camera/subject faster. Only two scalar values
                // persist; every output pixel always comes from the current frame.
                let motion = min(1, change.mean / 0.16)
                let alpha: Float = 0.18 + 0.72 * motion
                stableLower = previous.lower + alpha * (lower - previous.lower)
                stableUpper = previous.upper + alpha * (upper - previous.upper)
                // Bound transient scale lag to avoid turning newly close objects
                // into large clipped regions when scene composition changes.
                stableLower = min(max(stableLower, lower - currentSpan * 0.1), lower + currentSpan * 0.1)
                stableUpper = min(max(stableUpper, upper - currentSpan * 0.1), upper + currentSpan * 0.1)
            }
        }

        history = temporal ? History(lower: stableLower, upper: stableUpper, luma: luma) : nil
        let span = max(stableUpper - stableLower, 0.000_001)
        for index in inverse.indices {
            let value = inverse[index].isFinite ? inverse[index] : median
            inverse[index] = min(1, max(0, (value - stableLower) / span))
        }
        return inverse
    }

    private func percentile(_ sorted: [Float], fraction: Float) -> Float {
        let position = Float(sorted.count - 1) * fraction
        let lower = Int(position)
        let upper = min(sorted.count - 1, lower + 1)
        let weight = position - Float(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private func frameChange(_ lhs: [Float], _ rhs: [Float]) -> (mean: Float, histogram: Float) {
        var difference: Float = 0
        var firstHistogram = [Float](repeating: 0, count: 16)
        var secondHistogram = firstHistogram
        for index in lhs.indices {
            difference += abs(lhs[index] - rhs[index])
            firstHistogram[min(15, max(0, Int(lhs[index] * 16)))] += 1
            secondHistogram[min(15, max(0, Int(rhs[index] * 16)))] += 1
        }
        let count = Float(lhs.count)
        let histogramDifference = zip(firstHistogram, secondHistogram).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }
        return (difference / count, histogramDifference / count)
    }
}
