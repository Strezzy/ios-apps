import SwiftUI

/// A single animation clock for the centered glass and its particle field.
struct VoiceConversationView: View {
    @ObservedObject var voice: VoiceController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.voiceSceneProgress) private var progress
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var epoch = Date()
    @State private var downloadConsent = false
    private var compact: Bool { verticalSizeClass == .compact }
    var body: some View {
        let quiet = reduceMotion || lowPower || scenePhase != .active
        let orbSize: Double = compact ? 132 : 188
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: quiet)) { tick in
            let energy = quiet ? 0 : min(1, max(0, voice.phase == .speaking
                ? voice.level * exp(-max(0, tick.date.timeIntervalSince(voice.speechBeat)) * 4) : voice.level))
            ZStack {
                VoiceParticleField(time: tick.date.timeIntervalSince(epoch), energy: voice.phase == .listening ? -energy * 0.4 : energy,
                                   progress: progress, orbSize: orbSize, quiet: quiet)
                Button {
                    if voice.phase == .listening { voice.pause() }
                    else if voice.phase == .idle || voice.phase == .speaking { voice.talk() }
                } label: {
                    LiquidVoiceOrb(phase: voice.phase, level: voice.level, speechBeat: voice.speechBeat,
                                   animationDate: tick.date, animationEpoch: epoch)
                        .frame(width: orbSize, height: orbSize)
                        .contentShape(Circle())
                }.buttonStyle(.plain)
                    .scaleEffect(reduceMotion ? 1 : 0.12 + 0.88 * progress)
                    .opacity(min(1, progress * 2))
                    .disabled(voice.phase == .preparing || voice.phase == .thinking || voice.phase == .transcribing || voice.assets != .ready)
                    .accessibilityLabel(voice.phase == .listening ? "Pause voice chat" : voice.phase == .speaking ? "Interrupt and talk" : "Resume voice chat")
                    .accessibilityValue(voice.phase.title)
                    .accessibilityIdentifier("voiceOrb")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) { notices.padding(.top, 12).opacity(min(1, progress * 2)) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("voiceOverlay")
        .task { await voice.open(playActivationSound: true) }
        .onDisappear { voice.close() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { voice.pause() }
        }
        .confirmationDialog("Prepare on-device speech?", isPresented: $downloadConsent, titleVisibility: .visible) {
            Button("Download speech language") { voice.prepareLanguage() }
        } message: {
            Text("Apple may download a language model. After setup, the orb starts listening. Transcription and replies stay on your device.")
        }
    }
    private var notices: some View {
        VStack(spacing: 8) {
            if let error = voice.error {
                Text(error).font(.caption).foregroundStyle(.primary)
                    .padding(12).frame(maxWidth: 280)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("voiceError")
            }
            assetNotice
        }
    }
    @ViewBuilder private var assetNotice: some View {
        switch voice.assets {
        case .checking: EmptyView()
        case .unsupported:
            Text("On-device speech is unavailable for this language or device. Choose a language in voice settings.")
                .font(.caption).padding(12).frame(maxWidth: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("voiceUnavailable")
        case .needsDownload:
            Button { downloadConsent = true } label: { Label("Prepare speech language", systemImage: "arrow.down.circle").font(.caption).padding(6) }
                .buttonStyle(.glass).disabled(voice.active).accessibilityIdentifier("prepareVoiceLanguage")
        case .ready: EmptyView()
        }
    }
}
