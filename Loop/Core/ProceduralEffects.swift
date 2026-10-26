import Foundation
import CoreImage
import CoreGraphics
@preconcurrency import UIKit

/// Resolution-independent drawing and deterministic time-based particles.
/// Every frame can be rendered independently, including reverse and ping-pong exports.
enum ProceduralEffects {
    private static func random(_ index: Int, _ salt: Int = 0) -> CGFloat {
        let value = sin(Double(index * 127 + salt * 311 + 17) * 12.9898) * 43758.5453
        return CGFloat(value - floor(value))
    }
    private static func wrap(_ value: CGFloat, _ range: CGFloat) -> CGFloat {
        let v = value.truncatingRemainder(dividingBy: range)
        return v < 0 ? v + range : v
    }
    private static func canvas(_ extent: CGRect, draw: (CGContext, CGFloat, CGFloat) -> Void) -> CIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: extent.size, format: format).image { renderer in
            let c = renderer.cgContext
            c.scaleBy(x: extent.width / 1000, y: extent.width / 1000)
            draw(c, 1000, extent.height / extent.width * 1000)
        }
        return image.cgImage.map { CIImage(cgImage: $0) } ?? CIImage(color: .clear).cropped(to: extent)
    }
    private static func gradient(_ c: CGContext, colors: [UIColor], width: CGFloat, height: CGFloat) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(\.cgColor) as CFArray, locations: nil) else { return }
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    private static func glow(_ c: CGContext, center: CGPoint, radius: CGFloat, color: UIColor, aspect: CGFloat = 1) {
        c.saveGState(); c.translateBy(x: center.x, y: center.y); c.scaleBy(x: 1, y: aspect)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
        }
        c.restoreGState()
    }
    static func background(id: String, extent: CGRect, time: Double) -> CIImage {
        canvas(extent) { c, w, h in
            let t = CGFloat(time.isFinite ? time : 0)
            let dark = UIColor(red: 0.015, green: 0.02, blue: 0.07, alpha: 1)
            let palettes: [String: [UIColor]] = [
                "blackStudio": [.black, UIColor(white: 0.08, alpha: 1)],
                "whiteStudio": [.white, UIColor(white: 0.9, alpha: 1)],
                "roseStudio": [UIColor(red: 0.35, green: 0.12, blue: 0.28, alpha: 1), UIColor(red: 1, green: 0.73, blue: 0.79, alpha: 1)],
                "blueStudio": [UIColor(red: 0.02, green: 0.08, blue: 0.3, alpha: 1), UIColor(red: 0.32, green: 0.7, blue: 0.91, alpha: 1)],
                "sunsetSky": [UIColor(red: 0.21, green: 0.07, blue: 0.4, alpha: 1), UIColor(red: 0.91, green: 0.33, blue: 0.39, alpha: 1), UIColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)],
                "paperBackdrop": [UIColor(red: 0.94, green: 0.9, blue: 0.81, alpha: 1), UIColor(red: 0.8, green: 0.76, blue: 0.68, alpha: 1)],
                "warmBokeh": [UIColor(red: 0.12, green: 0.04, blue: 0.02, alpha: 1), UIColor(red: 0.34, green: 0.13, blue: 0.05, alpha: 1)],
                "coolBokeh": [dark, UIColor(red: 0.1, green: 0.15, blue: 0.33, alpha: 1)]
            ]
            gradient(c, colors: palettes[id] ?? [dark, UIColor(red: 0.06, green: 0.03, blue: 0.17, alpha: 1)], width: w, height: h)
            if id == "deepSpace" {
                glow(c, center: CGPoint(x: w * 0.32, y: h * 0.35), radius: w * 0.6, color: .systemPurple.withAlphaComponent(0.4), aspect: 0.6)
                glow(c, center: CGPoint(x: w * 0.8, y: h * 0.7), radius: w * 0.5, color: .systemBlue.withAlphaComponent(0.35))
                for i in 0..<130 {
                    let x = random(i, 1) * w, y = random(i, 2) * h, r = 0.6 + random(i, 3) * 2.5
                    let a = 0.5 + 0.4 * sin(t * 0.6 + CGFloat(i))
                    c.setFillColor(UIColor.white.withAlphaComponent(a).cgColor); c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            } else if id == "auroraSky" {
                for i in 0..<9 {
                    let x = CGFloat(i) * w / 8 + 50 * sin(t * 0.2 + CGFloat(i))
                    glow(c, center: CGPoint(x: x, y: h * (0.35 + 0.12 * sin(CGFloat(i)))), radius: w * 0.16, color: (i % 2 == 0 ? UIColor.systemTeal : .systemPurple).withAlphaComponent(0.55), aspect: 3)
                }
            } else if id == "neonGrid" {
                c.setStrokeColor(UIColor.systemPink.withAlphaComponent(0.65).cgColor); c.setLineWidth(1.5)
                for i in -12...12 {
                    c.move(to: CGPoint(x: w / 2 + CGFloat(i) * 13, y: h * 0.48)); c.addLine(to: CGPoint(x: w / 2 + CGFloat(i) * 140, y: h)); c.strokePath()
                }
                for i in 0..<14 {
                    let p = CGFloat(i) / 13
                    let y = h * 0.48 + p * p * h * 0.52
                    c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: w, y: y)); c.strokePath()
                }
                glow(c, center: CGPoint(x: w / 2, y: h * 0.48), radius: 270, color: .systemPurple.withAlphaComponent(0.6), aspect: 0.5)
            } else if id == "matrix" {
                for i in 0..<150 {
                    let x = floor(random(i, 1) * 35) * w / 35, y = wrap(random(i, 2) * h + t * (30 + random(i, 3) * 50), h)
                    let text = (i % 3 == 0 ? "1" : "0") as NSString
                    text.draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 18, weight: .medium), .foregroundColor: UIColor.systemGreen.withAlphaComponent(0.25 + random(i, 4) * 0.7)])
                }
            } else if id == "warmBokeh" || id == "coolBokeh" {
                for i in 0..<24 {
                    let x = random(i, 7) * w, y = random(i, 8) * h, r = 25 + random(i, 9) * 100
                    let color: UIColor = id == "warmBokeh" ? .systemOrange : .systemCyan
                    glow(c, center: CGPoint(x: x, y: y), radius: r, color: color.withAlphaComponent(0.25 + random(i) * 0.35))
                }
            } else if id == "spotlightBackdrop" {
                glow(c, center: CGPoint(x: w * 0.5, y: h * 0.38), radius: w * 0.68, color: UIColor(red: 0.72, green: 0.8, blue: 1, alpha: 0.65), aspect: 1.4)
            } else if id == "sunsetSky" {
                glow(c, center: CGPoint(x: w * 0.72, y: h * 0.58), radius: w * 0.18, color: UIColor(red: 1, green: 0.91, blue: 0.6, alpha: 0.8))
            } else if id == "paperBackdrop" {
                for i in 0..<1300 {
                    c.setFillColor(UIColor.black.withAlphaComponent(0.025).cgColor)
                    c.fill(CGRect(x: random(i, 1) * w, y: random(i, 2) * h, width: 1.5, height: 1))
                }
            }
        }
    }
    static func overlay(id: String, extent: CGRect, time: Double) -> CIImage {
        canvas(extent) { c, w, h in
            let t = CGFloat(time.isFinite ? time : 0)
            if id == "fog" || id == "lightLeak" {
                for i in 0..<5 {
                    let x = w * (0.2 + 0.23 * CGFloat(i)) + sin(t * 0.17 + CGFloat(i)) * 160
                    let color: UIColor = id == "fog" ? .white.withAlphaComponent(0.22) : (i % 2 == 0 ? .systemOrange : .systemPink).withAlphaComponent(0.26)
                    glow(c, center: CGPoint(x: x, y: h * (0.3 + 0.15 * CGFloat(i))), radius: w * 0.55, color: color, aspect: id == "fog" ? 0.38 : 1.8)
                }
                return
            }
            if id == "scanlines" || id == "vhs" {
                c.setFillColor(UIColor.black.withAlphaComponent(id == "vhs" ? 0.18 : 0.3).cgColor)
                for y in stride(from: CGFloat(0), to: h, by: 5) { c.fill(CGRect(x: 0, y: y, width: w, height: 1.4)) }
                if id == "vhs" {
                    let y = wrap(t * 90, h)
                    c.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor); c.fill(CGRect(x: 0, y: y, width: w, height: 15))
                    c.setFillColor(UIColor.systemCyan.withAlphaComponent(0.12).cgColor); c.fill(CGRect(x: 0, y: y + 16, width: w, height: 3))
                }
                return
            }
            let count = id == "grain" ? 1600 : id == "rain" ? 140 : id == "dust" ? 45 : 80
            let phase = id == "grain" || id == "dust" ? Int(floor(t * 24)).quotientAndRemainder(dividingBy: 10000).remainder : 0
            for i in 0..<count {
                let seed = i + phase * 1700
                let speed = id == "rain" ? 450 + random(i, 4) * 450 : 25 + random(i, 4) * 95
                let rising = ["embers", "bubbles", "fireflies"].contains(id)
                let x = wrap(random(seed, 1) * w + sin(t * 0.5 + CGFloat(i)) * (id == "rain" ? 0 : 20), w)
                let y = wrap(random(seed, 2) * h + (rising ? -t : t) * speed, h)
                let r = id == "grain" ? 1.2 : 1.5 + random(i, 3) * (id == "bubbles" ? 24 : 5)
                if id == "rain" {
                    c.setStrokeColor(UIColor(red: 0.75, green: 0.86, blue: 1, alpha: 0.2 + random(i) * 0.35).cgColor)
                    c.setLineWidth(0.7 + random(i, 5)); c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x - 8, y: y + 25 + random(i, 3) * 30)); c.strokePath()
                } else if id == "bubbles" {
                    c.setStrokeColor(UIColor.white.withAlphaComponent(0.4).cgColor); c.setLineWidth(1)
                    c.strokeEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
                    c.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor); c.fillEllipse(in: CGRect(x: x + r * 0.4, y: y + r * 0.3, width: r * 0.35, height: r * 0.35))
                } else if id == "confetti" {
                    let color = UIColor(hue: random(i, 8), saturation: 0.8, brightness: 1, alpha: 0.85)
                    c.saveGState(); c.translateBy(x: x, y: y); c.rotate(by: t + CGFloat(i)); c.setFillColor(color.cgColor); c.fill(CGRect(x: -r, y: -r / 2, width: r * 2, height: r)); c.restoreGState()
                } else if id == "sparkles" || id == "fireflies" || id == "embers" {
                    let color: UIColor = id == "embers" ? .systemOrange : id == "fireflies" ? .systemYellow : .white
                    let a = 0.35 + 0.6 * abs(sin(t + CGFloat(i)))
                    glow(c, center: CGPoint(x: x, y: y), radius: r * 4, color: color.withAlphaComponent(a * 0.6))
                    c.setFillColor(color.withAlphaComponent(a).cgColor); c.fillEllipse(in: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
                    if id == "sparkles" { c.setStrokeColor(color.withAlphaComponent(a).cgColor); c.setLineWidth(0.8); c.move(to: CGPoint(x: x - r * 2, y: y)); c.addLine(to: CGPoint(x: x + r * 2, y: y)); c.move(to: CGPoint(x: x, y: y - r * 2)); c.addLine(to: CGPoint(x: x, y: y + r * 2)); c.strokePath() }
                } else {
                    let a: CGFloat = id == "grain" ? 0.13 : id == "dust" ? 0.35 : 0.4 + random(i, 8) * 0.5
                    c.setFillColor((id == "grain" && i % 2 == 0 ? UIColor.black : .white).withAlphaComponent(a).cgColor)
                    c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            }
        }
    }
}
