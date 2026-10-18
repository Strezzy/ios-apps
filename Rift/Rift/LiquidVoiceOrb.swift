import SwiftUI

/// The glass boundary itself flows; the center remains clear enough to see the chat.
struct LiquidOrbShape: Shape {
    var time: Double
    var energy: Double
    var inward: Double = 0
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { .init(time, .init(energy, inward)) }
        set { time = newValue.first; energy = newValue.second.first; inward = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.43
        let strength = 0.035 + min(1, max(0, energy)) * 0.035
        for step in 0...120 {
            let angle = Double(step) / 120 * .pi * 2
            let wave = sin(angle * 3 + time * 1.3) * strength
                + sin(angle * 2 - time * 0.85) * 0.045
                + cos(angle * 5 + time * 0.65) * 0.016
            // Listening folds the glass inward; speaking keeps the outward wave.
            let fold = pow(max(0, sin(angle * 3 - time * 1.4)), 2)
            let r = radius * (1 + wave - inward * (0.045 + fold * 0.085))
            let point = CGPoint(x: rect.midX + cos(angle) * r, y: rect.midY + sin(angle) * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct LiquidOrbEntrance {
    let scale: Double
    let squash: Double
    init(age: Double, reduced: Bool) {
        let t = max(0, age)
        scale = reduced ? 1 : min(1.16, max(0.04, 1 - exp(-8 * t) * cos(13 * t)))
        squash = reduced ? 0 : sin(t * 19) * exp(-7 * t) * 0.22
    }
}

struct LiquidVoiceOrb: View {
    let phase: VoicePhase
    let level: Double
    let speechBeat: Date
    var animationDate: Date? = nil
    var animationEpoch: Date? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var epoch = Date()

    var body: some View {
        let quiet = reduceMotion || lowPower || scenePhase != .active
        Group {
            if let animationDate {
                surface(at: animationDate, quiet: quiet)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quiet)) { tick in
                    surface(at: tick.date, quiet: quiet)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.12), value: level)
    }
    private func surface(at date: Date, quiet: Bool) -> some View {
        let age = max(0, date.timeIntervalSince(animationEpoch ?? epoch))
        let t = quiet ? 0 : age
        let speaking = phase == .speaking
        let energy = quiet ? 0 : min(1, max(0, speaking ? level * exp(-max(0, date.timeIntervalSince(speechBeat)) * 4) : level))
        let inward = phase == .listening ? max(0, (energy - 0.15) / 0.85) : 0
        let shape = LiquidOrbShape(time: t * (speaking ? 1.2 : 1), energy: energy, inward: inward)
        let entrance = LiquidOrbEntrance(age: age, reduced: quiet)
        return ZStack {
            // A ring of light behind the glass, never an opaque painted sphere.
            shape.stroke(ArrivalEffects.amber.opacity(speaking ? 0.42 + energy * 0.18 : 0.08), lineWidth: speaking ? 12 : 5)
                .blur(radius: speaking ? 15 : 9).scaleEffect(speaking ? 1.12 : 1.04)
            if reduceTransparency {
                shape.fill(.regularMaterial)
            } else {
                shape.fill(.clear)
                    .glassEffect(.clear.tint(RiftTheme.wine.opacity(0.06)), in: shape)
            }
            shape.stroke(AngularGradient(colors: [
                .white.opacity(0.85), ArrivalEffects.amber.opacity(0.18),
                RiftTheme.rose.opacity(0.65), .white.opacity(0.08),
                ArrivalEffects.amber.opacity(0.8), .white.opacity(0.85)
            ], center: .center, angle: .degrees(quiet ? 0 : sin(t * 0.6) * 32)), lineWidth: 1.1)
            shape.trim(from: 0.53, to: 0.79)
                .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .blur(radius: 1.5).scaleEffect(0.96)
            shape.trim(from: 0.04, to: 0.28)
                .stroke(ArrivalEffects.amber.opacity(0.48), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .blur(radius: 2.5).scaleEffect(0.97)
        }
        .scaleEffect(x: entrance.scale * (1 + entrance.squash + (speaking ? energy * 0.035 : -inward * 0.04)),
                     y: entrance.scale * (1 - entrance.squash + (speaking ? energy * 0.035 : -inward * 0.04)))
        .rotationEffect(.degrees(quiet ? 0 : sin(t * 0.7) * 4))
        .shadow(color: RiftTheme.wine.opacity(0.12), radius: 10, y: 7)
    }
}
