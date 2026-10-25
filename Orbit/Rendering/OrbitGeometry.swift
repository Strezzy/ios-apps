import CoreGraphics
import UIKit
import simd

enum OrbitGeometry {
    static func displaySize(source: CGSize, transform: CGAffineTransform) -> CGSize {
        guard source.width > 0, source.height > 0,
              source.width.isFinite, source.height.isFinite else { return CGSize(width: 1, height: 1) }
        let bounds = CGRect(origin: .zero, size: source).applying(transform)
        return CGSize(width: max(1, abs(bounds.width)), height: max(1, abs(bounds.height)))
    }

    /// Maps an upright, normalized display point to the original encoded image.
    /// Translation is derived from all four transformed corners, including mirrored media.
    static func textureTransform(source: CGSize, transform: CGAffineTransform) -> simd_float3x3 {
        guard source.width > 0, source.height > 0 else { return matrix_identity_float3x3 }
        let bounds = CGRect(origin: .zero, size: source).applying(transform)
        let inverse = transform.inverted()
        func point(_ x: CGFloat, _ y: CGFloat) -> SIMD3<Float> {
            let p = CGPoint(x: bounds.minX + x * bounds.width,
                            y: bounds.minY + y * bounds.height).applying(inverse)
            return SIMD3(Float(p.x / source.width), Float(p.y / source.height), 1)
        }
        let origin = point(0, 0)
        return simd_float3x3(columns: (point(1, 0) - origin, point(0, 1) - origin, origin))
    }

    /// Displayed image dimensions divided by the viewport dimensions.
    static func contentScale(source: CGSize, viewport: CGSize, fill: Bool) -> SIMD2<Float> {
        guard source.width > 0, source.height > 0, viewport.width > 0, viewport.height > 0 else {
            return SIMD2(repeating: 1)
        }
        let x = viewport.width / source.width
        let y = viewport.height / source.height
        let scale = fill ? max(x, y) : min(x, y)
        return SIMD2(Float(source.width * scale / viewport.width), Float(source.height * scale / viewport.height))
    }

    static func screenTilt(_ raw: SIMD2<Double>, orientation: UIInterfaceOrientation) -> SIMD2<Double> {
        switch orientation {
        case .landscapeLeft: return SIMD2(-raw.y, raw.x)
        case .landscapeRight: return SIMD2(raw.y, -raw.x)
        case .portraitUpsideDown: return -raw
        default: return raw
        }
    }

    static func boundedTilt(_ value: SIMD2<Double>) -> SIMD2<Double> {
        SIMD2(value.x.isFinite ? min(1, max(-1, value.x)) : 0,
              value.y.isFinite ? min(1, max(-1, value.y)) : 0)
    }
}
