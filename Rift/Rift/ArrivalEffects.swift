import SwiftUI

/// Decorations never change the string, its layout, selection, or accessibility.
/// A shared per-frame budget bounds work even when inference arrives in bursts.
enum ArrivalEffects {
    static let amber = Color(red: 1, green: 0.56, blue: 0.19)

    static func embers(in context: GraphicsContext, bounds: CGRect, progress p: Double,
                       seed: Int, budget: inout Int) {
        guard p > 0, p < 1, seed % 2 == 0 else { return }
        for index in 0..<3 where budget > 0 {
            budget -= 1
            let depth = Double((seed + index * 3) % 7) / 6
            let life = min(1, max(0, (p - Double(index) * 0.055) / 0.85))
            let glow = sin(.pi * life) * (1 - life * 0.45)
            let drift = sin(life * 5 + Double(seed % 9)) * (3 + depth * 5)
            let x = bounds.midX + drift + Double(index - 1) * 3
            let y = bounds.minY + bounds.height * 0.5 - life * (17 + depth * 22)
            let radius = (0.8 + depth * 1.1) * (1 - life * 0.4)
            let spark = Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                width: radius * 2, height: radius * (2.5 + life)))
            var halo = context
            halo.opacity = glow * 0.55
            halo.addFilter(.blur(radius: 2.2 + depth))
            halo.fill(spark, with: .color(amber))
            var core = context
            core.opacity = glow * 0.95
            core.fill(spark, with: .color(index == 0 ? .init(red: 1, green: 0.86, blue: 0.53) : amber))
            // A short cooling trail makes the different depth planes legible.
            var trail = Path()
            trail.move(to: CGPoint(x: x, y: y + radius))
            trail.addQuadCurve(to: CGPoint(x: x - drift * 0.18, y: y + 5 + depth * 3),
                control: CGPoint(x: x + 2, y: y + 3))
            core.opacity *= 0.35
            core.stroke(trail, with: .color(RiftTheme.rose), lineWidth: radius * 0.65)
        }
    }

    static func portal(in context: GraphicsContext, bounds: CGRect, progress p: Double,
                       seed: Int, budget: inout Int) {
        guard p > 0, p < 0.94, seed % 2 == 0, budget >= 2 else { return }
        budget -= 2
        let envelope = pow(sin(.pi * p), 1.4)
        let opening = 0.3 + 0.7 * sin(.pi * min(1, p * 1.4))
        let width = max(10, bounds.width * 1.3) * opening
        let height = bounds.height * (0.3 + 0.75 * opening)
        let ring = Path(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        var portal = context
        portal.translateBy(x: bounds.midX, y: bounds.midY)
        portal.rotate(by: .radians(-0.4 + p * 0.9))
        portal.opacity = envelope * 0.8
        var halo = portal
        halo.addFilter(.blur(radius: 3))
        halo.stroke(ring, with: .color(RiftTheme.rose), lineWidth: 3.5)
        portal.stroke(ring, with: .linearGradient(Gradient(colors: [amber, RiftTheme.rose, .white.opacity(0.8), RiftTheme.wine]),
            startPoint: CGPoint(x: -width, y: -height / 2), endPoint: CGPoint(x: width, y: height / 2)), lineWidth: 1)
        portal.scaleBy(x: 1.25 + p * 0.4, y: 1.12 + p * 0.25)
        portal.opacity *= 0.3 * (1 - p)
        portal.stroke(ring, with: .color(amber), lineWidth: 0.7)
    }

    static func cipher(in context: GraphicsContext, bounds: CGRect, progress p: Double,
                       seed: Int, budget: inout Int) {
        guard p > 0, p < 0.72, budget > 0 else { return }
        budget -= 1
        let strength = min(1, p * 12) * (1 - min(1, max(0, (p - 0.48) / 0.24)))
        let glyph = CipherGlyph.symbol(seed: seed, progress: p)
        let label = Text(glyph).font(.system(size: bounds.height * 0.72, weight: .medium, design: .monospaced))
            .foregroundStyle(amber)
        var scrambled = context
        scrambled.opacity = strength
        // Clip only decorative glyphs, preserving text wrapping and line height.
        scrambled.clip(to: Path(bounds.insetBy(dx: -2, dy: -4)))
        let point = CGPoint(x: bounds.midX + sin(p * 55 + Double(seed)) * (1 - p) * 2,
            y: bounds.midY - (1 - p) * 3)
        var ghost = scrambled
        ghost.opacity *= 0.3
        ghost.addFilter(.blur(radius: 1.5))
        ghost.draw(label, at: CGPoint(x: point.x + 2, y: point.y - 2))
        scrambled.draw(label, at: point)
    }
}

enum CipherGlyph {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789∆+×≋")
    static func canScramble(_ character: Character?) -> Bool {
        guard let character, character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first, scalar.isASCII else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
    }
    static func symbol(seed: Int, progress: Double) -> String {
        let tick = Int(min(1, max(0, progress)) * 24)
        return String(alphabet[(abs(seed % alphabet.count) * 13 + tick * 7) % alphabet.count])
    }
}
