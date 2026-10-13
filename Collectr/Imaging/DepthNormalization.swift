import Foundation

/// Removes the current prediction's arbitrary inverse-depth scale before any
/// temporal filtering. Locally unchanged, textured interiors can reuse a small,
/// bounded amount of history; detected motion and depth boundaries reject it.
/// State is one model-resolution depth/luma pair, independent of video length.
final class DepthNormalization {
    private struct History {
        var depth: [Float]
        var luma: [Float]
        var width: Int
        var height: Int
    }

    private var history: History?

    func reset() { history = nil }

    func normalize(_ raw: [Float], isInverseDepth: Bool, luma: [Float], temporal: Bool,
                   width: Int = 0, height: Int = 0) throws -> [Float] {
        guard !raw.isEmpty else {
            history = nil
            throw DepthCheckError.message("The depth model returned an empty image.")
        }

        var inverse = raw.map { value -> Float in
            guard value.isFinite else { return .nan }
            if isInverseDepth { return value }
            // DA3 predicts depth (farther = larger), unlike DA2's inverse depth.
            guard value > 0 else { return .nan }
            return 1 / max(value, 0.000_001)
        }
        var valid = inverse.filter(\.isFinite)
        guard valid.count * 100 >= raw.count * 95 else {
            history = nil
            throw DepthCheckError.message("The model returned invalid depth values. Try the Balanced model for this media.")
        }
        valid.sort()
        let lower = percentile(valid, fraction: 0.015)
        let upper = percentile(valid, fraction: 0.985)
        let median = percentile(valid, fraction: 0.5)
        let span = upper - lower
        guard span > max(0.000_001, abs(median) * 0.000_001) else {
            // A flat estimate belongs on the screen plane and cannot provide
            // useful temporal correspondences for the following prediction.
            history = nil
            return [Float](repeating: 0.5, count: raw.count)
        }

        // Percentiles must be from THIS prediction. If a model returns a*d+b
        // for the same scene, these current endpoints cancel a and b exactly.
        // Averaging raw endpoints across frames mixes incompatible units and
        // creates the very disparity shifts temporal filtering should remove.
        for index in inverse.indices {
            let value = inverse[index].isFinite ? inverse[index] : median
            inverse[index] = min(1, max(0, (value - lower) / span))
        }

        // A thumbnail signature cannot identify local motion. Missing or
        // mismatched full model-resolution luma therefore disables history.
        guard temporal, width > 2, height > 2, width <= Int.max / height,
              width * height == inverse.count, luma.count == inverse.count,
              luma.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            history = nil
            return inverse
        }
        guard let previous = history, previous.width == width, previous.height == height else {
            history = History(depth: inverse, luma: luma, width: width, height: height)
            return inverse
        }

        let change = frameChange(previous.luma, luma)
        let cut = change.mean > 0.28 || (change.mean > 0.13 && change.histogram > 0.55)
        guard !cut else {
            history = History(depth: inverse, luma: luma, width: width, height: height)
            return inverse
        }

        var result = inverse
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let current = inverse[index]
                let old = previous.depth[index]
                let depthChange = abs(current - old)
                // Large depth innovations can be real object/camera motion,
                // including motion that happens to leave luma unchanged.
                guard depthChange < 0.06 else { continue }

                var currentMin = current
                var currentMax = current
                var previousMin = old
                var previousMax = old
                var lumaMin = luma[index]
                var lumaMax = luma[index]
                var lumaDifference: Float = 0
                var patchMatches = true
                for dy in -1...1 {
                    for dx in -1...1 {
                        let neighbor = index + dy * width + dx
                        let difference = abs(luma[neighbor] - previous.luma[neighbor])
                        if difference > 0.025 { patchMatches = false }
                        lumaDifference += difference
                        lumaMin = min(lumaMin, luma[neighbor])
                        lumaMax = max(lumaMax, luma[neighbor])
                        currentMin = min(currentMin, inverse[neighbor])
                        currentMax = max(currentMax, inverse[neighbor])
                        previousMin = min(previousMin, previous.depth[neighbor])
                        previousMax = max(previousMax, previous.depth[neighbor])
                    }
                }
                let meanLumaDifference = lumaDifference / 9
                // Flat color has no evidence of correspondence. A detected
                // depth edge in either frame may be an occlusion/disocclusion;
                // reject its history instead of carrying an old silhouette.
                guard patchMatches, meanLumaDifference < 0.015,
                      lumaMax - lumaMin >= 0.04,
                      currentMax - currentMin < 0.035,
                      previousMax - previousMin < 0.035 else { continue }

                let imageConfidence = 1 - meanLumaDifference / 0.015
                let depthConfidence = 1 - depthChange / 0.06
                let historyWeight: Float = 0.65 * imageConfidence * depthConfidence
                // Keep history near the current local depth range, and cap
                // every correction. This is a conservative static-region
                // filter, not an assumption that all pixels remain stationary.
                let boundedHistory = min(currentMax + 0.015, max(currentMin - 0.015, old))
                let correction = min(Float(0.012), max(-0.012, (boundedHistory - current) * historyWeight))
                result[index] = min(1, max(0, current + correction))
            }
        }

        history = History(depth: result, luma: luma, width: width, height: height)
        return result
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
        // A fixed-size sample is enough for a global cut check. Local filtering
        // still checks all nine luma samples around each eligible depth pixel.
        let sampleStride = max(1, lhs.count / 576)
        var count: Float = 0
        for index in Swift.stride(from: 0, to: lhs.count, by: sampleStride) {
            difference += abs(lhs[index] - rhs[index])
            firstHistogram[min(15, max(0, Int(lhs[index] * 16)))] += 1
            secondHistogram[min(15, max(0, Int(rhs[index] * 16)))] += 1
            count += 1
        }
        let histogramDifference = zip(firstHistogram, secondHistogram).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }
        return (difference / count, histogramDifference / count)
    }
}
