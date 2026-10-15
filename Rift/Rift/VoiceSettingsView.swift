import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @StateObject private var voice: VoiceController
    @AppStorage("rift.voiceActivationSound") private var activationSound = true
    @AppStorage("rift.voiceHaptics") private var haptics = true
    @State private var downloadConsent = false
    @Environment(\.scenePhase) private var scenePhase
    init(model: AppModel) { _voice = StateObject(wrappedValue: VoiceController(model: model)) }
    var body: some View {
        Form {
            Section("Orb") {
                Toggle("Voice mode sounds", isOn: $activationSound).accessibilityIdentifier("voiceActivationSound")
                Toggle("Soft haptics", isOn: $haptics).accessibilityIdentifier("voiceHaptics")
                Text("Resonant glass tones and a soft fading vibration when the orb opens and closes. Sound respects Silent Mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Conversation & speech") {
                Toggle("Hands-free turns", isOn: $voice.handsFree).accessibilityIdentifier("voiceHandsFree")
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
                Text("The orb responds to your voice while the microphone is active. Closing the orb or leaving the app stops it. Short recordings are deleted after transcription. Your conversation stays in this chat.")
                    .font(.caption).foregroundStyle(.secondary)

            }
            Section("On-device speech") {
                if let error = voice.error { Text(error).foregroundStyle(.secondary) }
                switch voice.assets {
                case .checking: ProgressView("Checking speech language")
                case .ready: Label("Speech language ready", systemImage: "checkmark.circle")
                case .unsupported: Text("On-device speech is unavailable for this language or device.")
                case .needsDownload:
                    Button("Prepare speech language") { downloadConsent = true }.disabled(voice.active)
                }
            }
        }.tint(RiftTheme.accent)
            .navigationTitle("Voice & sound").navigationBarTitleDisplayMode(.inline)
            .task { await voice.load() }
            .onDisappear { voice.pause() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { voice.pause() } }
            .confirmationDialog("Prepare on-device speech?", isPresented: $downloadConsent, titleVisibility: .visible) {
                Button("Download speech language") { voice.prepareLanguage() }
            } message: {
                Text("Apple may download a language model. Transcription stays on your device.")
            }
    }
    private func quality(_ voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: return "Premium"
        case .enhanced: return "Enhanced"
        default: return "Standard"
        }
    }
}
