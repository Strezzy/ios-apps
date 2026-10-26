import Foundation
import CoreGraphics
import CoreImage
@preconcurrency import UIKit
@preconcurrency import Vision

enum FaceEffects {
    static func apply(_ input: CIImage, id: String, faces: [VNFaceObservation], time: Double) -> CIImage {
        let extent = input.extent
        var image = input
        for face in faces {
            let box = face.boundingBox
            let rect = CGRect(x: box.minX * extent.width, y: box.minY * extent.height,
                              width: box.width * extent.width, height: box.height * extent.height)
            guard rect.width > 8, rect.height > 8 else { continue }
            let left = center(face.landmarks?.leftEye, face: face, extent: extent)
            let right = center(face.landmarks?.rightEye, face: face, extent: extent)
            let mouth = center(face.landmarks?.outerLips, face: face, extent: extent)
            let nose = center(face.landmarks?.nose, face: face, extent: extent)
            func bump(_ point: CGPoint?, radius: CGFloat, scale: Double) {
                guard let point else { return }
                image = image.clampedToExtent().applyingFilter("CIBumpDistortion", parameters: [
                    kCIInputCenterKey: CIVector(cgPoint: point), kCIInputRadiusKey: radius, kCIInputScaleKey: scale
                ]).cropped(to: extent)
            }
            if ["bigEyes", "tinyEyes", "alien", "doll"].contains(id) {
                let amount = id == "tinyEyes" ? -0.55 : id == "alien" ? 0.75 : 0.45
                bump(left, radius: rect.width * 0.22, scale: amount)
                bump(right, radius: rect.width * 0.22, scale: amount)
            }
            if id == "bigMouth" || id == "tinyMouth" { bump(mouth, radius: rect.width * 0.3, scale: id == "bigMouth" ? 0.55 : -0.55) }
            if id == "wideNose" { bump(nose, radius: rect.width * 0.23, scale: 0.6) }
            if id == "ogre" {
                bump(CGPoint(x: rect.midX, y: rect.midY), radius: rect.height * 0.52, scale: 0.35)
                let mask = CIFilter(name: "CIRadialGradient", parameters: [kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY), "inputRadius0": rect.width * 0.28, "inputRadius1": rect.width * 0.5, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: extent)
                let green = image.applyingFilter("CIColorMonochrome", parameters: [kCIInputColorKey: CIColor(red: 0.3, green: 0.65, blue: 0.22), kCIInputIntensityKey: 0.7])
                image = green.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
            }
        }
        let decorated = !["bigEyes", "tinyEyes", "bigMouth", "tinyMouth", "wideNose", "ogre"].contains(id)
        guard decorated, !faces.isEmpty, let overlay = draw(id: id, extent: extent, faces: faces, time: time) else { return image }
        return CIImage(cgImage: overlay).composited(over: image).cropped(to: extent)
    }
    private static func center(_ region: VNFaceLandmarkRegion2D?, face: VNFaceObservation, extent: CGRect) -> CGPoint? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        let x = points.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(points.count)
        let y = points.reduce(CGFloat(0)) { $0 + $1.y } / CGFloat(points.count)
        return CGPoint(x: (face.boundingBox.minX + x * face.boundingBox.width) * extent.width,
                       y: (face.boundingBox.minY + y * face.boundingBox.height) * extent.height)
    }
    private static func draw(id: String, extent: CGRect, faces: [VNFaceObservation], time: Double) -> CGImage? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: extent.size, format: format).image { drawing in
            let c = drawing.cgContext
            c.setAllowsAntialiasing(true); c.setShouldAntialias(true)
            for face in faces {
                guard abs(face.yaw?.doubleValue ?? 0) < 0.9 else { continue }
                let b = face.boundingBox
                let rect = CGRect(x: b.minX * extent.width, y: (1 - b.maxY) * extent.height, width: b.width * extent.width, height: b.height * extent.height)
                guard rect.width > 8 else { continue }
                let left = center(face.landmarks?.leftEye, face: face, extent: extent)
                let right = center(face.landmarks?.rightEye, face: face, extent: extent)
                var angle: CGFloat = 0
                if let left, let right {
                    let a = left.x < right.x ? left : right, z = left.x < right.x ? right : left
                    angle = atan2(-(z.y - a.y), z.x - a.x)
                }
                c.saveGState()
                if let left, let right {
                    // Anchor illustrated eyes to the measured eye line, not an assumed box position.
                    let separation = hypot(right.x - left.x, right.y - left.y)
                    c.translateBy(x: (left.x + right.x) / 2, y: extent.height - (left.y + right.y) / 2)
                    c.rotate(by: angle); c.translateBy(x: 0, y: rect.height * 0.18)
                    c.scaleBy(x: max(rect.width * 0.6, separation / 0.46), y: rect.height)
                } else {
                    c.translateBy(x: rect.midX, y: rect.midY); c.rotate(by: angle); c.scaleBy(x: rect.width, y: rect.height)
                }
                c.setLineCap(.round); c.setLineJoin(.round); c.setLineWidth(0.018)
                func ellipse(_ r: CGRect, _ color: UIColor, stroke: Bool = false) {
                    c.setFillColor(color.cgColor); c.setStrokeColor(color.cgColor)
                    if stroke { c.strokeEllipse(in: r) } else { c.fillEllipse(in: r) }
                }
                func line(_ points: [CGPoint], _ color: UIColor, width: CGFloat = 0.018, close: Bool = false, fill: Bool = false) {
                    guard let first = points.first else { return }
                    c.beginPath(); c.move(to: first)
                    for point in points.dropFirst() { c.addLine(to: point) }
                    if close { c.closePath() }
                    c.setLineWidth(width); c.setStrokeColor(color.cgColor); c.setFillColor(color.cgColor)
                    c.drawPath(using: fill ? .fill : .stroke)
                }
                func polygon(_ values: [(CGFloat, CGFloat)], _ color: UIColor) { line(values.map { CGPoint(x: $0.0, y: $0.1) }, color, close: true, fill: true) }
                let cyan = UIColor(red: 0.1, green: 0.95, blue: 1, alpha: 1)
                let pink = UIColor(red: 1, green: 0.2, blue: 0.55, alpha: 1)
                let gold = UIColor(red: 1, green: 0.8, blue: 0.18, alpha: 1)
                let dark = UIColor(red: 0.025, green: 0.035, blue: 0.07, alpha: 0.93)
                func cheek(_ x: CGFloat) { ellipse(CGRect(x: x - 0.11, y: 0.03, width: 0.22, height: 0.11), pink.withAlphaComponent(0.3)) }
                func ears(_ long: Bool, _ color: UIColor) {
                    if long {
                        ellipse(CGRect(x: -0.43, y: -1.1, width: 0.23, height: 0.68), color)
                        ellipse(CGRect(x: 0.2, y: -1.1, width: 0.23, height: 0.68), color)
                        ellipse(CGRect(x: -0.375, y: -1.02, width: 0.12, height: 0.49), pink.withAlphaComponent(0.65))
                        ellipse(CGRect(x: 0.255, y: -1.02, width: 0.12, height: 0.49), pink.withAlphaComponent(0.65))
                    } else {
                        polygon([(-0.5, -0.35), (-0.44, -0.88), (-0.12, -0.47)], color)
                        polygon([(0.5, -0.35), (0.44, -0.88), (0.12, -0.47)], color)
                        polygon([(-0.42, -0.44), (-0.4, -0.72), (-0.23, -0.47)], pink)
                        polygon([(0.42, -0.44), (0.4, -0.72), (0.23, -0.47)], pink)
                    }
                }
                switch id {
                case "sunglasses", "neonVisor":
                    let lens = id == "neonVisor" ? cyan.withAlphaComponent(0.45) : dark
                    for x in [-0.41, 0.04] {
                        let r = CGRect(x: x, y: -0.28, width: 0.37, height: 0.2)
                        let path = UIBezierPath(roundedRect: r, cornerRadius: 0.06)
                        lens.setFill(); path.fill(); (id == "neonVisor" ? cyan : UIColor.white.withAlphaComponent(0.7)).setStroke(); path.lineWidth = 0.018; path.stroke()
                        line([CGPoint(x: x + 0.06, y: -0.23), CGPoint(x: x + 0.17, y: -0.23)], .white.withAlphaComponent(0.6), width: 0.015)
                    }
                    line([CGPoint(x: -0.04, y: -0.2), CGPoint(x: 0.04, y: -0.2)], id == "neonVisor" ? cyan : dark, width: 0.035)
                case "heartEyes":
                    for x in [-0.23, 0.23] {
                        let p = UIBezierPath(); p.move(to: CGPoint(x: x, y: -0.02))
                        p.addCurve(to: CGPoint(x: x - 0.14, y: -0.23), controlPoint1: CGPoint(x: x - 0.1, y: -0.12), controlPoint2: CGPoint(x: x - 0.19, y: -0.16))
                        p.addCurve(to: CGPoint(x: x, y: -0.25), controlPoint1: CGPoint(x: x - 0.12, y: -0.34), controlPoint2: CGPoint(x: x - 0.03, y: -0.32))
                        p.addCurve(to: CGPoint(x: x + 0.14, y: -0.23), controlPoint1: CGPoint(x: x + 0.03, y: -0.32), controlPoint2: CGPoint(x: x + 0.12, y: -0.34))
                        p.addCurve(to: CGPoint(x: x, y: -0.02), controlPoint1: CGPoint(x: x + 0.19, y: -0.16), controlPoint2: CGPoint(x: x + 0.1, y: -0.12)); p.close(); pink.setFill(); p.fill()
                    }
                case "laserEyes", "alien":
                    let color = id == "alien" ? UIColor.green : UIColor.red
                    for x in [-0.22, 0.22] {
                        ellipse(CGRect(x: x - 0.14, y: -0.26, width: 0.28, height: 0.16), color.withAlphaComponent(0.25))
                        ellipse(CGRect(x: x - 0.085, y: -0.22, width: 0.17, height: 0.07), color)
                        ellipse(CGRect(x: x - 0.04, y: -0.2, width: 0.08, height: 0.03), .white)
                        if id == "laserEyes" { line([CGPoint(x: x, y: -0.18), CGPoint(x: x + (x < 0 ? -1.2 : 1.2), y: -0.12)], color.withAlphaComponent(0.6), width: 0.035) }
                    }
                case "cat", "fox", "bunny":
                    ears(id == "bunny", id == "fox" ? .systemOrange : id == "bunny" ? .white : dark)
                    ellipse(CGRect(x: -0.09, y: -0.015, width: 0.18, height: 0.08), id == "bunny" ? pink : dark)
                    for side in [-1.0, 1.0] {
                        for y in [-0.025, 0.04, 0.1] {
                            line([CGPoint(x: side * 0.13, y: 0.07), CGPoint(x: side * 0.5, y: y)], .white.withAlphaComponent(0.9), width: 0.012)
                        }
                    }
                    cheek(-0.3); cheek(0.3)
                case "devil":
                    polygon([(-0.4, -0.38), (-0.46, -0.94), (-0.14, -0.48)], .systemRed)
                    polygon([(0.4, -0.38), (0.46, -0.94), (0.14, -0.48)], .systemRed)
                case "angel":
                    c.setLineWidth(0.045); ellipse(CGRect(x: -0.4, y: -0.85, width: 0.8, height: 0.18), gold.withAlphaComponent(0.3), stroke: true)
                    c.setLineWidth(0.018); ellipse(CGRect(x: -0.4, y: -0.85, width: 0.8, height: 0.18), gold, stroke: true)
                case "crown":
                    polygon([(-0.43, -0.48), (-0.5, -0.83), (-0.25, -0.65), (0, -0.97), (0.25, -0.65), (0.5, -0.83), (0.43, -0.48)], gold)
                    for x in [-0.25, 0, 0.25] { ellipse(CGRect(x: x - 0.04, y: -0.62, width: 0.08, height: 0.08), x == 0 ? .systemPink : cyan) }
                case "pirate":
                    line([CGPoint(x: -0.53, y: -0.38), CGPoint(x: 0.52, y: -0.08)], dark, width: 0.035)
                    ellipse(CGRect(x: -0.43, y: -0.3, width: 0.39, height: 0.24), dark)
                    ellipse(CGRect(x: 0.45, y: 0.04, width: 0.12, height: 0.17), gold, stroke: true)
                case "robot", "skull":
                    let skull = id == "skull"
                    let path = UIBezierPath(roundedRect: CGRect(x: -0.45, y: -0.47, width: 0.9, height: 0.89), cornerRadius: skull ? 0.27 : 0.1)
                    (skull ? UIColor(white: 0.94, alpha: 0.9) : UIColor(red: 0.34, green: 0.4, blue: 0.5, alpha: 0.88)).setFill(); path.fill()
                    for x in [-0.38, 0.06] {
                        ellipse(CGRect(x: x, y: -0.28, width: 0.32, height: skull ? 0.2 : 0.11), skull ? dark : cyan)
                    }
                    if skull {
                        polygon([(-0.08, 0.03), (0, -0.1), (0.08, 0.03)], dark)
                        for x in stride(from: -0.25, through: 0.26, by: 0.1) { line([CGPoint(x: x, y: 0.19), CGPoint(x: x, y: 0.34)], dark, width: 0.025) }
                        line([CGPoint(x: -0.28, y: 0.26), CGPoint(x: 0.28, y: 0.26)], dark, width: 0.025)
                    } else {
                        line([CGPoint(x: -0.24, y: 0.22), CGPoint(x: 0.24, y: 0.22)], cyan, width: 0.035)
                        for x in [-0.36, 0.36] { ellipse(CGRect(x: x - 0.025, y: -0.41, width: 0.05, height: 0.05), .white) }
                    }
                case "clown":
                    ellipse(CGRect(x: -0.12, y: -0.06, width: 0.24, height: 0.17), .systemRed)
                    for x in [-0.23, 0.23] { polygon([(x - 0.12, -0.27), (x, -0.52), (x + 0.12, -0.27)], cyan) }
                    let p = UIBezierPath(); p.move(to: CGPoint(x: -0.28, y: 0.15)); p.addQuadCurve(to: CGPoint(x: 0.28, y: 0.15), controlPoint: CGPoint(x: 0, y: 0.48)); p.lineWidth = 0.06; UIColor.red.setStroke(); p.stroke()
                case "blush", "glam", "doll":
                    cheek(-0.3); cheek(0.3)
                    if id == "glam" {
                        ellipse(CGRect(x: -0.18, y: 0.19, width: 0.36, height: 0.09), pink.withAlphaComponent(0.65))
                        for x in [-0.23, 0.23] { line([CGPoint(x: x - 0.14, y: -0.22), CGPoint(x: x + 0.12, y: -0.23)], .black, width: 0.025) }
                    }
                case "neonMask":
                    let p = UIBezierPath(ovalIn: CGRect(x: -0.46, y: -0.48, width: 0.92, height: 0.95)); p.lineWidth = 0.018; cyan.setStroke(); p.stroke()
                    for x in [-0.23, 0.23] { line([CGPoint(x: x - 0.09, y: -0.27), CGPoint(x: x + 0.09, y: -0.1)], pink, width: 0.026); line([CGPoint(x: x + 0.09, y: -0.27), CGPoint(x: x - 0.09, y: -0.1)], pink, width: 0.026) }
                    line([CGPoint(x: -0.25, y: 0.23), CGPoint(x: 0.25, y: 0.23)], cyan, width: 0.025)
                    for x in stride(from: -0.2, through: 0.21, by: 0.1) { line([CGPoint(x: x, y: 0.17), CGPoint(x: x, y: 0.29)], cyan, width: 0.018) }
                default: break
                }
                c.restoreGState()
            }
        }.cgImage
    }
}
