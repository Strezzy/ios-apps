import SwiftUI

private struct VoiceSceneProgressKey: EnvironmentKey {
    static let defaultValue: Double = 1
}
private struct VoiceTextScatterAmountKey: EnvironmentKey {
    static let defaultValue: Double = 0
}
extension EnvironmentValues {
    var voiceSceneProgress: Double {
        get { self[VoiceSceneProgressKey.self] }
        set { self[VoiceSceneProgressKey.self] = newValue }
    }
    var voiceTextScatterAmount: Double {
        get { self[VoiceTextScatterAmountKey.self] }
        set { self[VoiceTextScatterAmountKey.self] = newValue }
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

/// Animate a value through the transcript, never a shader over its ScrollView.
/// Filtering the container can prevent UIKit-backed content from rendering.
struct VoiceTextScatter: ViewModifier, Animatable {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content.environment(\.voiceTextScatterAmount, amount)
    }
}

/// The row keeps its identity when the effect finishes, avoiding a second
/// Markdown/layout rebuild. This never wraps the ScrollView or navigation UI.
struct VoiceFragmentSurface: ViewModifier {
    @Environment(\.voiceTextScatterAmount) private var amount
    func body(content: Content) -> some View {
        content.visualEffect { surface, _ in
            surface.layerEffect(ShaderLibrary.voiceTextScatter(.float(Float(amount))),
                                maxSampleOffset: CGSize(width: 24, height: 24),
                                isEnabled: amount > 0.001)
        }
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
    private struct Particle {
        let a: Double
        let b: Double
        let depth: Double
        let phase: Double
        let behindGlass: Bool
    }
    // Precompute the seeds once. Groups of four form local constellations, so
    // links need only a few fixed neighbors rather than an all-pairs search.
    private static let particles: [Particle] = (0..<224).map { index in
        let group = index / 4
        let offset = Double(index % 4) - 1.5
        return Particle(a: min(1, max(0, seed(group, 1) + offset * 0.018)),
                        b: min(1, max(0, seed(group, 2) + offset * 0.024)),
                        depth: seed(index, 3),
                        phase: seed(group, 4) * .pi * 2 + offset * 0.12,
                        behindGlass: group % 3 == 0)
    }
    var body: some View {
        Canvas { context, size in
            let p = min(1, max(0, progress))
            let spread = p * p * (3 - 2 * p)
            let reveal = min(1, max(0, (p - 0.18) / 0.65))
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let t = quiet ? 0 : time
            let count = quiet ? 64 : Self.particles.count
            var points: [CGPoint] = []
            points.reserveCapacity(count)
            for node in Self.particles.prefix(count) {
                let a = node.a, b = node.b, phase = node.phase
                let origin = CGPoint(x: 20 + a * max(0, size.width - 40),
                                     y: 20 + floor(b * max(1, (size.height - 40) / 24)) * 24)
                let angle = phase + t * (0.055 + node.depth * 0.035)
                let radius = orbSize * 0.6 + a * max(20, size.width * 0.45 - orbSize * 0.6)
                let verticalRadius = orbSize * 0.57 + b * max(20, size.height * 0.47 - orbSize * 0.57)
                var x = center.x + cos(angle) * radius + sin(t * 0.7 + phase) * 10
                var y = center.y + sin(angle) * verticalRadius + cos(t * 0.55 + phase) * 9
                if node.behindGlass {
                    // Keep this depth plane inside the orb's translucent center.
                    x = center.x + cos(angle * 1.1) * orbSize * (0.16 + a * 0.22) + sin(t * 0.6 + phase) * 5
                    y = center.y + sin(angle * 0.9) * orbSize * (0.12 + b * 0.24) + cos(t * 0.5 + phase) * 5
                }
                let dx = x - center.x, dy = y - center.y
                let distance = max(1, hypot(dx, dy))
                let influence = max(0, 1 - abs(distance - orbSize * 0.55) / (orbSize * 0.9))
                let push = quiet ? 0 : energy * influence * (12 + node.depth * 14) * (node.behindGlass ? 0.35 : 1)
                x += dx / distance * push; y += dy / distance * push
                points.append(CGPoint(x: origin.x + (x - origin.x) * spread,
                                      y: origin.y + (y - origin.y) * spread))
            }
            if !quiet {
                var remainingLinks = 8
                for index in 0..<24 where remainingLinks > 0 {
                    let first = index * 8
                    let second = first + 2
                    let wave = sin(t * 0.65 + Self.particles[first].phase)
                    let pulse = max(0, (wave - 0.55) / 0.45)
                    guard pulse > 0 else { continue }
                    let start = points[first], end = points[second]
                    let distance = hypot(end.x - start.x, end.y - start.y)
                    guard distance > 4, distance < 110 else { continue }
                    remainingLinks -= 1
                    var line = Path(); line.move(to: start); line.addLine(to: end)
                    var connection = context
                    connection.opacity = reveal * spread * pulse * pulse * 0.28
                    connection.stroke(line, with: .color(RiftTheme.rose), lineWidth: 0.65)
                }
            }
            for index in 0..<count {
                let node = Self.particles[index], point = points[index]
                let side = 1.2 + node.depth * 2.0
                var particle = context
                particle.translateBy(x: point.x, y: point.y)
                particle.rotate(by: .radians(node.phase + sin(t * 0.8 + node.phase) * 0.8 * spread))
                let color = index % 9 == 0 ? Color.white : (index % 5 == 0 ? ArrivalEffects.amber : RiftTheme.rose)
                let alpha = reveal * (0.24 + node.depth * 0.48) * (node.behindGlass ? 0.75 : 1)
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
