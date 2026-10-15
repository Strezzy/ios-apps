import SwiftUI
import AVFoundation

/// A floating part of the chat, with no sheet or navigation destination.
struct VoiceConversationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var voice: VoiceController
    @State private var downloadConsent = false
    @State private var options = false
    let onClose: () -> Void

    init(model: AppModel, onClose: @escaping () -> Void) {
        _voice = StateObject(wrappedValue: VoiceController(model: model))
        self.onClose = onClose
    }
    private var compact: Bool { verticalSizeClass == .compact }
    var body: some View {
        let layout = compact
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: 8))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 8))
        layout {
            if options {
                ScrollView { voiceOptions.padding(16) }
                    .frame(width: 300, height: compact ? 200 : 280)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
            }
            VStack(alignment: .trailing, spacing: 8) {
            if let error = voice.error {
                Text(error).font(.caption).foregroundStyle(.primary)
                    .padding(12).frame(maxWidth: 280)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("voiceError")
            }
            assetNotice
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    Button {
                        if voice.phase == .listening { voice.pause() }
                        else if voice.phase == .idle || voice.phase == .speaking { voice.talk() }
                    } label: {
                        LiquidVoiceOrb(phase: voice.phase, level: voice.level, speechBeat: voice.speechBeat)
                            .frame(width: compact ? 96 : 132, height: compact ? 96 : 132)
                            .padding(14)
                            .contentShape(Circle())
                    }.buttonStyle(.plain)
                        .disabled(voice.phase == .preparing || voice.phase == .thinking || voice.phase == .transcribing || voice.assets != .ready)
                        .accessibilityLabel(voice.phase == .listening ? "Pause voice chat" : voice.phase == .speaking ? "Interrupt and talk" : "Resume voice chat")
                        .accessibilityIdentifier("voiceOrb")
                    Button { voice.close(); onClose() } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Close voice mode").accessibilityIdentifier("closeVoiceMode")
                }
                HStack(spacing: 3) {
                    Text(voice.phase.title).font(.caption.weight(.medium)).lineLimit(1)
                        .accessibilityIdentifier("voiceStatus")
                    Button {
                        if !options { voice.pause() }
                        withAnimation(.smooth(duration: 0.25)) { options.toggle() }
                    } label: {
                        Image(systemName: options ? "chevron.down" : "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold)).frame(width: 36, height: 32)
                    }.buttonStyle(.plain).accessibilityLabel("Voice and language settings").accessibilityIdentifier("voiceOptions")
                }.padding(.leading, 12).padding(.trailing, 2)
                    .glassEffect(.regular, in: Capsule())
            }
            }
        }
        .padding(.trailing, 12).padding(.bottom, 10)
        .accessibilityElement(children: .contain).accessibilityIdentifier("voiceOverlay")
        .task { await voice.open() }
        .onDisappear { voice.close() }
        .onChange(of: scenePhase) { _, phase in
            // Never resume a microphone automatically after leaving the chat/app.
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
    private var voiceOptions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Voice & language").font(.headline)
            Toggle("Hands-free turns", isOn: $voice.handsFree).font(.callout)
            Text("Pause naturally to send. Hands-free keeps listening after each reply. Tap the orb to resume, pause, or interrupt a reply.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Speech language", selection: $voice.language) {
                if !voice.languages.contains(voice.language) { Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language).tag(voice.language) }
                ForEach(voice.languages, id: \.self) { language in
                    Text(Locale.current.localizedString(forIdentifier: language) ?? language).tag(language)
                }
            }.disabled(voice.active).onChange(of: voice.language) { _, _ in Task { await voice.languageChanged() } }
            Picker("Speaking voice", selection: $voice.voiceID) {
                Text("Automatic · best installed").tag("")
                ForEach(voice.voices, id: \.identifier) { item in
                    Text("\(item.name) · \(item.language) · \(quality(item))").tag(item.identifier)
                }
            }.disabled(voice.active).accessibilityIdentifier("speakingVoicePicker")
            if let chosen = voice.chosenVoice {
                Text("\(chosen.name) · \(quality(chosen))").font(.caption).foregroundStyle(.secondary)
            }
            HStack { Text("Speed"); Slider(value: $voice.rate, in: 0.35...0.65, step: 0.01).accessibilityLabel("Speaking speed") }.disabled(voice.active)
            HStack { Text("Pitch"); Slider(value: $voice.pitch, in: 0.75...1.25, step: 0.05).accessibilityLabel("Voice pitch") }.disabled(voice.active)
            Button { voice.previewVoice() } label: { Label("Preview voice", systemImage: "speaker.wave.2") }
                .disabled(voice.active || voice.voices.isEmpty).accessibilityIdentifier("previewVoice")
            Text("For the most natural speech, download a Premium or Enhanced voice in iPhone Settings → Accessibility → Read & Speak → Voices. Automatic uses the best installed voice in your language. Your voice, speed and pitch choices are kept.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The microphone is active only while Listening. Closing the orb or leaving the app stops it. Short recordings are deleted after transcription. Your conversation stays in this chat.")
                .font(.caption).foregroundStyle(.secondary)
        }.tint(RiftTheme.accent)
    }
    private func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}
