import SwiftUI

/// Floating glass in the current chat; its close control lives in the composer.
struct VoiceConversationView: View {
    @ObservedObject var voice: VoiceController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var downloadConsent = false
    private var compact: Bool { verticalSizeClass == .compact }
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let error = voice.error {
                Text(error).font(.caption).foregroundStyle(.primary)
                    .padding(12).frame(maxWidth: 280)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("voiceError")
            }
            assetNotice
            Button {
                if voice.phase == .listening { voice.pause() }
                else if voice.phase == .idle || voice.phase == .speaking { voice.talk() }
            } label: {
                LiquidVoiceOrb(phase: voice.phase, level: voice.level, speechBeat: voice.speechBeat)
                    .frame(width: compact ? 112 : 152, height: compact ? 112 : 152)
                    .contentShape(Circle())
            }.buttonStyle(.plain)
                .disabled(voice.phase == .preparing || voice.phase == .thinking || voice.phase == .transcribing || voice.assets != .ready)
                .accessibilityLabel(voice.phase == .listening ? "Pause voice chat" : voice.phase == .speaking ? "Interrupt and talk" : "Resume voice chat")
                .accessibilityValue(voice.phase.title)
                .accessibilityIdentifier("voiceOrb")
        }
        .padding(.trailing, 12).padding(.bottom, 10)
        .accessibilityElement(children: .contain).accessibilityIdentifier("voiceOverlay")
        .task { await voice.open(playActivationSound: true) }
        .onDisappear { voice.close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { voice.pause() }
        }
        .confirmationDialog("Prepare on-device speech?", isPresented: $downloadConsent, titleVisibility: .visible) {
            Button("Download speech language") { voice.prepareLanguage() }
        } message: {
            Text("Apple may download a language model. After setup, the orb starts listening. Transcription and replies stay on your device.")
        }
    }
    @ViewBuilder private var assetNotice: some View {
        switch voice.assets {
        case .checking:
            ProgressView("Preparing voice").font(.caption).padding(12)
                .background(.regularMaterial, in: Capsule())
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
