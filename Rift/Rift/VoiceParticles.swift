import SwiftUI

private struct VoiceSceneProgressKey: EnvironmentKey {
    static let defaultValue: Double = 1
}
extension EnvironmentValues {
    var voiceSceneProgress: Double {
        get { self[VoiceSceneProgressKey.self] }
        set { self[VoiceSceneProgressKey.self] = newValue }
    }
}

/// Both insertion and removal use the same trajectory in opposite directions.
struct VoiceSceneTransition: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content.environment(\.voiceSceneProgress, progress)
    }
}

/// Samples actual chat pixels only during the brief transition. The transcript
/// and its per-message renderers leave the view tree once voice mode is open.
struct VoiceTextScatter: ViewModifier, Animatable {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content.layerEffect(ShaderLibrary.voiceTextScatter(.float(Float(amount))),
                            maxSampleOffset: CGSize(width: 24, height: 24),
                            isEnabled: amount > 0.001)
    }
}

/// One bounded canvas, driven by the orb's clock. No retained text textures,
/// per-particle views, physics simulation, or full-screen blur pass.
struct VoiceParticleField: View {
    let time: Double
    let energy: Double
    let progress: Double
    let orbSize: Double
    let quiet: Bool

    private static func seed(_ index: Int, _ salt: Int) -> Double {
        let n = UInt64(index + 1) &* 2_654_435_761 &+ UInt64(salt) &* 2_246_822_519
        return Double((n ^ (n >> 13)) % 10_007) / 10_007
    }
    var body: some View {
        Canvas { context, size in
            let p = min(1, max(0, progress))
            let spread = p * p * (3 - 2 * p)
            let reveal = min(1, max(0, (p - 0.18) / 0.65))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let t = quiet ? 0 : time
            for index in 0..<(quiet ? 64 : 160) {
                let a = Self.seed(index, 1), b = Self.seed(index, 2)
                let depth = Self.seed(index, 3)
                let phase = Self.seed(index, 4) * .pi * 2
                // The seed positions resemble fragments on the chat's lines.
                let origin = CGPoint(x: 20 + a * max(0, size.width - 40),
                                     y: 20 + floor(b * max(1, (size.height - 40) / 24)) * 24)
                let angle = phase + t * (0.055 + depth * 0.035)
                let radius = orbSize * 0.6 + a * max(20, size.width * 0.45 - orbSize * 0.6)
                let verticalRadius = orbSize * 0.57 + b * max(20, size.height * 0.47 - orbSize * 0.57)
                var x = center.x + cos(angle) * radius + sin(t * 0.7 + phase) * 10
                var y = center.y + sin(angle) * verticalRadius + cos(t * 0.55 + phase) * 9
                // Some distant fragments pass behind the translucent glass.
                if index % 7 == 0 {
                    x = 16 + a * max(0, size.width - 32) + sin(t * 0.4 + phase) * 18
                    y = 16 + b * max(0, size.height - 32) + cos(t * 0.35 + phase) * 16
                }
                let dx = x - center.x, dy = y - center.y
                let distance = max(1, hypot(dx, dy))
                let influence = max(0, 1 - abs(distance - orbSize * 0.55) / (orbSize * 0.9))
                let push = quiet ? 0 : energy * influence * (12 + depth * 14)
                x += dx / distance * push; y += dy / distance * push
                x = origin.x + (x - origin.x) * spread
                y = origin.y + (y - origin.y) * spread
                let side = 1.2 + depth * 2.0
                var particle = context
                particle.translateBy(x: x, y: y)
                particle.rotate(by: .radians(phase + sin(t * 0.8 + phase) * 0.8 * spread))
                let color = index % 5 == 0 ? ArrivalEffects.amber : RiftTheme.accent
                let alpha = reveal * (0.24 + depth * 0.48)
                particle.opacity = alpha * 0.12
                particle.fill(Path(roundedRect: CGRect(x: -side - 1, y: -side - 1,
                    width: side * 2 + 2, height: side * 2 + 2), cornerRadius: 1.5), with: .color(color))
                particle.opacity = alpha
                particle.fill(Path(roundedRect: CGRect(x: -side / 2, y: -side * 0.35,
                    width: side, height: side * 0.7), cornerRadius: 0.35), with: .color(color))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
