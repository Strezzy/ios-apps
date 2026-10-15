import SwiftUI

struct LiquidVoiceOrb: View {
    let phase: VoicePhase
    let level: Double
    let speechBeat: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var epoch = Date()

    var body: some View {
        let quiet = reduceMotion || lowPower || scenePhase != .active
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quiet || phase == .idle)) { tick in
            let t = quiet ? 0 : tick.date.timeIntervalSince(epoch)
            let speaking = phase == .speaking
            let energy = speaking ? level * exp(-max(0, tick.date.timeIntervalSince(speechBeat)) * 4) : level
            let pulse = quiet ? 1 : 1 + energy * 0.065 + (speaking ? sin(t * 2.6) * 0.018 : 0)
            ZStack {
                Circle().fill(RadialGradient(colors: [ArrivalEffects.amber.opacity(speaking ? 0.65 : 0.15), RiftTheme.rose.opacity(0.2), .clear],
                    center: .center, startRadius: 8, endRadius: 80))
                    .blur(radius: speaking ? 18 : 10).scaleEffect(speaking ? 1.42 + energy * 0.18 : 1.08)
                Circle().fill(.clear)
                    .glassEffect(.regular.tint(RiftTheme.wine.opacity(0.15)), in: Circle())
                if quiet {
                    Circle().fill(LinearGradient(colors: [ArrivalEffects.amber.opacity(0.7), RiftTheme.rose.opacity(0.75), RiftTheme.wine],
                        startPoint: .topLeading, endPoint: .bottomTrailing)).opacity(0.85)
                } else {
                    GeometryReader { geometry in
                        Circle().fill(.white)
                            .colorEffect(ShaderLibrary.riftLiquidOrb(
                                .float2(Float(geometry.size.width), Float(geometry.size.height)),
                                .float(Float(t)), .float(Float(energy)),
                                .float(speaking ? 1 : phase == .thinking || phase == .transcribing || phase == .preparing ? 2 : 0)))
                    }.clipShape(Circle()).opacity(0.92)
                }
                Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.05), ArrivalEffects.amber.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                Ellipse().fill(.white.opacity(0.32)).frame(width: 40, height: 12)
                    .blur(radius: 5).rotationEffect(.degrees(-28)).offset(x: -21, y: -39)
            }
            .scaleEffect(pulse)
            .shadow(color: RiftTheme.wine.opacity(0.25), radius: 12, y: 9)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
    }
}
