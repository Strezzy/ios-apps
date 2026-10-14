import SwiftUI
import AVFoundation

struct VoiceConversationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var voice: VoiceController
    @ObservedObject private var model: AppModel
    @State private var downloadConsent = false
    init(model: AppModel) {
        self.model = model
        _voice = StateObject(wrappedValue: VoiceController(model: model))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 8) {
                        Text("A voice, right here.").font(.system(.title2, design: .rounded, weight: .semibold))
                        Text(model.selectedModel?.name ?? "Choose a chat model first").font(.caption).foregroundStyle(.secondary)
                    }
                    VoiceOrb(level: voice.level, active: voice.phase == .listening || voice.phase == .speaking, reduceMotion: reduceMotion)
                        .frame(width: 140, height: 140).padding(.vertical, 4)
                    VStack(spacing: 7) {
                        Text(voice.phase.title).font(.headline).contentTransition(.numericText()).accessibilityIdentifier("voiceStatus")
                        Text(voice.phase == .listening ? "Tap Send when you finish speaking." : "Apple speech. Your local AI. No cloud replies.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if let error = voice.error {
                        Text(error).font(.callout).foregroundStyle(RiftTheme.accent).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    assetNotice
                    controls
                    if !voice.heard.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("YOU SAID").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                            Text(voice.heard).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(RiftTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                    }
                    if voice.phase == .thinking, let reply = model.activeChat?.messages.last, reply.role == "assistant" {
                        MarkdownMessage(text: ReplyParts.parse(reply.content).answer, isStreaming: model.generating)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !voice.answer.isEmpty {
                        Text(voice.answer).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    voiceOptions
                    Text("The microphone is only active while Listening. Tap Pause or close this screen to stop. Short recordings are deleted after transcription; the resulting conversation is saved locally like text chat.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(24)
            }.background { RiftBackground() }
                .navigationTitle("Voice mode").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { voice.close(); dismiss() } } }
                .task { await voice.load() }
                .onDisappear { voice.close() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { voice.pause() } }
                .confirmationDialog("Prepare on-device speech?", isPresented: $downloadConsent, titleVisibility: .visible) {
                    Button("Download speech language") { voice.prepareLanguage() }
                } message: {
                    Text("Apple may download a language model. After setup, audio transcription stays on-device. This does not upload a recording or change your selected chat model.")
                }
        }.background { RiftBackground() }
    }
    @ViewBuilder private var assetNotice: some View {
        switch voice.assets {
        case .checking:
            ProgressView("Checking on-device speech").font(.caption)
        case .unsupported:
            Text("Apple's on-device speech is unavailable for this device or language. No cloud fallback is used. Text chat still works.")
                .font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("voiceUnavailable")
        case .needsDownload:
            Button { downloadConsent = true } label: { Label("Prepare speech language", systemImage: "arrow.down.circle") }
                .buttonStyle(.glass).disabled(voice.active).accessibilityIdentifier("prepareVoiceLanguage")
        case .ready:
            Label("Speech language ready offline", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var controls: some View {
        HStack(spacing: 14) {
            if voice.phase == .listening {
                Button { voice.sendRecording() } label: { Label("Send", systemImage: "arrow.up").frame(maxWidth: .infinity).padding(.vertical, 10) }.buttonStyle(.glassProminent)
            } else {
                Button { voice.talk() } label: { Label(voice.phase == .speaking ? "Interrupt & talk" : "Talk", systemImage: "mic.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }
                    .buttonStyle(.glassProminent)
                    .disabled(voice.assets != .ready || (voice.phase != .idle && voice.phase != .speaking))
                    .accessibilityIdentifier("startVoice")
            }
            if voice.active {
                Button { voice.pause() } label: { Image(systemName: "pause.fill").frame(width: 44, height: 44) }
                    .buttonStyle(.glass).accessibilityLabel("Pause voice chat")
            }
        }
    }
    private var voiceOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Hands-free turns", isOn: $voice.handsFree)
                .accessibilityHint("Sends after a pause and listens again after the spoken reply. Only while this screen is open.")
            Text("When enabled, a pause ends your turn. Listening resumes after the reply. No wake word or background listening.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Voice & language") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Speech language", selection: $voice.language) {
                        if !voice.languages.contains(voice.language) { Text(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language).tag(voice.language) }
                        ForEach(voice.languages, id: \.self) { language in
                            Text(Locale.current.localizedString(forIdentifier: language) ?? language).tag(language)
                        }
                    }.disabled(voice.active).onChange(of: voice.language) { _, _ in Task { await voice.languageChanged() } }
                    Picker("Speaking voice", selection: $voice.voiceID) {
                        Text("Automatic · installed Apple voice").tag("")
                        ForEach(voice.voices, id: \.identifier) { item in
                            Text("\(item.name) · \(item.language)").tag(item.identifier)
                        }
                    }.disabled(voice.active).accessibilityIdentifier("speakingVoicePicker")
                    HStack { Text("Speed"); Slider(value: $voice.rate, in: 0.35...0.65, step: 0.01).accessibilityLabel("Speaking speed") }.disabled(voice.active)
                    HStack { Text("Pitch"); Slider(value: $voice.pitch, in: 0.75...1.25, step: 0.05).accessibilityLabel("Voice pitch") }.disabled(voice.active)
                    Button { voice.previewVoice() } label: { Label("Preview voice", systemImage: "speaker.wave.2") }
                        .disabled(voice.active || voice.voices.isEmpty).accessibilityIdentifier("previewVoice")
                    Text("Uses installed Apple voices. More voices can be downloaded in iPhone Settings → Accessibility → Read & Speak → Voices. Voice downloads are managed by iOS. This version does not clone a voice from an audio clip.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.accessibilityIdentifier("voiceOptions")
        }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct VoiceOrb: View {
    let level: Double
    let active: Bool
    let reduceMotion: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { time in
            let t = reduceMotion ? 0 : time.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(RiftTheme.accent.opacity(0.07)).scaleEffect(1.08)
                Circle().fill(LinearGradient(colors: [RiftTheme.rose.opacity(0.95), RiftTheme.wine], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: RiftTheme.accent.opacity(0.18), radius: 18, y: 8)
                Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1)
                HStack(spacing: 5) {
                    ForEach(0..<7) { index in
                        let wave = active ? abs(sin(t * 3 + Double(index) * 0.6)) : 0.1
                        Capsule().fill(.white.opacity(0.9)).frame(width: 5, height: 12 + (12 + 35 * level) * wave)
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}
