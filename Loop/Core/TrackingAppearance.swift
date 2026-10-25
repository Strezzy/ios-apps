import Foundation
import CoreGraphics

/// Small, frame-independent identity samples. The original selected appearance
/// is never replaced; only a second, trusted appearance adapts to lighting/pose.
/// No video-sized bitmap is retained by the tracker.
struct TrackingAppearance {
    private var colors: [Double]
    private var layout: [Double]

    init?(image: CGImage, rect: NormalizedRect) {
        let r = rect.clamped()
        // Favor the interior: the selection's background should not become the
        // identity of a person who walks in front of someone else.
        let inset = 0.08
        let area = CGRect(x: (r.x + r.width * inset) * Double(image.width),
                          y: (r.y + r.height * inset) * Double(image.height),
                          width: r.width * (1 - 2 * inset) * Double(image.width),
                          height: r.height * (1 - 2 * inset) * Double(image.height)).integral
        guard let crop = image.cropping(to: area) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return nil }
        // Twelve softly binned hues, two saturation bands, and eight gray bins.
        // Hue tolerates lighting shifts; the spatial grid distinguishes similar
        // colors arranged differently (for example a red shirt vs red trousers).
        colors = [Double](repeating: 0, count: 32)
        layout = [Double](repeating: 0, count: 4 * 4 * 3)
        var total = 0.0
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                let red = Double(pixels[offset]) / 255
                let green = Double(pixels[offset + 1]) / 255
                let blue = Double(pixels[offset + 2]) / 255
                let high = max(red, max(green, blue)), low = min(red, min(green, blue))
                let delta = high - low
                let saturation = high > 0.001 ? delta / high : 0
                let weight = (x >= 5 && x < 19 && y >= 3 && y < 21) ? 1.0 : 0.45
                total += weight
                // Blend saturation boundaries; a small lighting change must not
                // move the whole histogram into an unrelated color band.
                let chromaWeight = min(1, max(0, (saturation - 0.08) / 0.20)) *
                                   min(1, max(0, (high - 0.04) / 0.10))
                let grayValue = high * 7
                let grayFirst = Int(grayValue), grayFraction = grayValue - Double(grayFirst)
                colors[24 + grayFirst] += weight * (1 - chromaWeight) * (1 - grayFraction)
                colors[24 + min(7, grayFirst + 1)] += weight * (1 - chromaWeight) * grayFraction
                if delta > 0.0001 && chromaWeight > 0 {
                    var hue: Double
                    if high == red { hue = (green - blue) / delta }
                    else if high == green { hue = 2 + (blue - red) / delta }
                    else { hue = 4 + (red - green) / delta }
                    if hue < 0 { hue += 6 }
                    let value = hue * 2
                    let first = Int(value) % 12, fraction = value - floor(value)
                    let saturated = min(1, max(0, (saturation - 0.25) / 0.5))
                    for band in 0...1 {
                        let contribution = weight * chromaWeight * (band == 0 ? 1 - saturated : saturated)
                        colors[band * 12 + first] += contribution * (1 - fraction)
                        colors[band * 12 + (first + 1) % 12] += contribution * fraction
                    }
                }
                let cell = ((y / 6) * 4 + x / 6) * 3
                layout[cell] += red / 36
                layout[cell + 1] += green / 36
                layout[cell + 2] += blue / 36
            }
        }
        colors = colors.map { $0 / total }
    }

    func distance(to other: Self) -> Double {
        let color = zip(colors, other.colors).reduce(0) { $0 + abs($1.0 - $1.1) } / 2
        let spatial = zip(layout, other.layout).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(layout.count)
        return 0.65 * color + 0.35 * min(1, spatial * 2)
    }

    mutating func adapt(toward sample: Self) {
        // Update only after a strong, unambiguous match. The immutable anchor
        // is checked separately even after the recent template has adapted.
        colors = zip(colors, sample.colors).map { pair in pair.0 * 0.96 + pair.1 * 0.04 }
        layout = zip(layout, sample.layout).map { pair in pair.0 * 0.96 + pair.1 * 0.04 }
    }
}

struct TrackingIdentity {
    let anchor: TrackingAppearance
    private(set) var recent: TrackingAppearance

    init(appearance: TrackingAppearance) { anchor = appearance; recent = appearance }

    func distances(to appearance: TrackingAppearance) -> (anchor: Double, recent: Double) {
        (anchor.distance(to: appearance), recent.distance(to: appearance))
    }

    func accepts(_ appearance: TrackingAppearance, recovering: Bool) -> Bool {
        let distance = distances(to: appearance)
        return distance.anchor <= (recovering ? 0.34 : 0.42) &&
               distance.recent <= (recovering ? 0.23 : 0.31)
    }

    mutating func learn(_ appearance: TrackingAppearance) {
        let distance = distances(to: appearance)
        if distance.anchor < 0.27 && distance.recent < 0.18 { recent.adapt(toward: appearance) }
    }
}

struct TrackingMotion {
    private(set) var last: TrackingKeyframe
    private var velocityX = 0.0
    private var velocityY = 0.0

    init(anchor: TrackingKeyframe) { last = anchor }

    func predicted(at time: Double) -> NormalizedRect {
        // Extrapolate briefly, then stop extending the prediction. A prediction
        // guides the search only and is never committed without reacquisition.
        let elapsed = min(0.25, max(-0.25, time - last.time))
        let rect = last.rect
        return NormalizedRect(x: rect.x + velocityX * elapsed, y: rect.y + velocityY * elapsed,
                              width: rect.width, height: rect.height).clamped()
    }

    func accepts(_ rect: NormalizedRect, at time: Double, recovering: Bool) -> Bool {
        let elapsed = abs(time - last.time)
        let prediction = predicted(at: time)
        let horizontal = max(0.025, last.rect.width * (recovering ? 1.2 : 0.55)) + elapsed * 0.65
        let vertical = max(0.025, last.rect.height * (recovering ? 0.9 : 0.45)) + elapsed * 0.5
        let sizeLimit = recovering ? 1.65 : max(1.25, 1 + elapsed * 3)
        return abs(rect.centerX - prediction.centerX) <= horizontal &&
               abs(rect.centerY - prediction.centerY) <= vertical &&
               rect.width / last.rect.width <= sizeLimit && last.rect.width / rect.width <= sizeLimit &&
               rect.height / last.rect.height <= sizeLimit && last.rect.height / rect.height <= sizeLimit
    }

    mutating func accept(_ keyframe: TrackingKeyframe) {
        let elapsed = keyframe.time - last.time
        if abs(elapsed) > 0.00001 {
            let vx = (keyframe.rect.centerX - last.rect.centerX) / elapsed
            let vy = (keyframe.rect.centerY - last.rect.centerY) / elapsed
            velocityX = velocityX * 0.55 + min(2, max(-2, vx)) * 0.45
            velocityY = velocityY * 0.55 + min(2, max(-2, vy)) * 0.45
        }
        last = keyframe
    }

    static func overlap(_ a: NormalizedRect, _ b: NormalizedRect) -> Double {
        let intersection = a.cgRect.intersection(b.cgRect)
        guard !intersection.isNull else { return 0 }
        let area = Double(intersection.width * intersection.height)
        return area / max(0.000001, a.width * a.height + b.width * b.height - area)
    }
}
