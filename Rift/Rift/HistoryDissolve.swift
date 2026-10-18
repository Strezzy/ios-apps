import SwiftUI

/// A render-only treatment. Scroll geometry, message identity, selection and
/// accessibility stay on the original views; no message snapshots are retained.
struct HistoryDissolve: ViewModifier {
    let viewportHeight: Double
    let readingHistory: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @State private var intersectsBand = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var epoch = Date()

    func body(content: Content) -> some View {
        let available = !reduceMotion && !voiceOver && !lowPower && scenePhase == .active
        let dissolving = available && !readingHistory
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !dissolving || !intersectsBand)) { tick in
            content.modifier(HistoryDissolveShader(
                height: viewportHeight,
                time: tick.date.timeIntervalSince(epoch),
                strength: dissolving ? 1 : 0,
                visible: intersectsBand && available))
                .animation(reduceMotion ? nil : .easeInOut(duration: readingHistory ? 0.28 : 0.8), value: dissolving)
        }
        .onGeometryChange(for: Bool.self) { proxy in
            let frame = proxy.frame(in: .scrollView(axis: .vertical))
            return viewportHeight > 0 && frame.maxY > 0 && frame.minY < viewportHeight / 3
        } action: { intersectsBand = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

private struct HistoryDissolveShader: ViewModifier, Animatable {
    let height: Double
    let time: Double
    var strength: Double
    let visible: Bool
    var animatableData: Double {
        get { strength }
        set { strength = newValue }
    }
    func body(content: Content) -> some View {
        content.visualEffect { surface, geometry in
            surface.layerEffect(
                ShaderLibrary.historyDissolve(
                    .float(Float(geometry.frame(in: .scrollView(axis: .vertical)).minY)),
                    .float(Float(height)), .float(Float(time)), .float(Float(strength))),
                maxSampleOffset: CGSize(width: 16, height: 16),
                isEnabled: visible && strength > 0.001)
        }
    }
}
