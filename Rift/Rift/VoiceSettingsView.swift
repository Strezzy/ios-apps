import SwiftUI
import AVFoundation

struct VoiceSettingsView: View {
    @StateObject private var voice: VoiceController
    @AppStorage("rift.voiceActivationSound") private var activationSound = true
    @AppStorage("rift.voiceHaptics") private var haptics = true
    @State private var downloadConsent = false
    @State private var pocketConsent = false
    @State private var voiceTab = "Pocket TTS"
    @ObservedObject private var pocket = PocketVoiceSettings.shared
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
                Text("The orb responds to your voice while the microphone is active. Closing the orb or leaving the app stops it. Short recordings are deleted after transcription. Your conversation stays in this chat.")
                    .font(.caption).foregroundStyle(.secondary)

            }
            Section("Speaking voice") {
                Picker("Voice type", selection: $voiceTab) {
                    Text("Pocket TTS").tag("Pocket TTS")
                    Text("Personal Voice").tag("Personal Voice")
                    Text("Apple").tag("Apple")
                }.pickerStyle(.segmented).accessibilityIdentifier("voiceTypeTabs")
                    .disabled(pocket.busy || voice.active)
                if voice.phase == .speaking { Button("Stop preview") { voice.pause() } }
                if pocket.busy {
                    ProgressView(pocket.status)
                    Button("Cancel") { pocket.cancel() }
                }
                if let error = pocket.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            if voiceTab == "Pocket TTS" {
                Section("Pocket TTS") {
                    Toggle("Use Pocket TTS", isOn: $pocket.enabled).disabled(voice.active || pocket.busy)
                        .accessibilityIdentifier("pocketEnabled")
                    Text("Natural English speech, generated on your device as replies arrive. Apple voices remain available for other languages, before setup, or if Pocket speech fails.")
                        .font(.caption).foregroundStyle(.secondary)
                    if pocket.installed {
                        Label("Voice pack ready · offline", systemImage: "checkmark.circle")
                        Button("Use built-in voice · Alba") { voice.pause(); pocket.selected = ""; pocket.enabled = true }
                            .disabled(pocket.busy || voice.active)
                        if let selected = pocket.personal.first(where: { $0.id.uuidString == pocket.selected }) {
                            Text("Selected: \(selected.name)").font(.caption)
                        }
                        Button { voice.previewVoice() } label: { Label("Preview voice", systemImage: "speaker.wave.2") }
                            .disabled(voice.active || pocket.busy || !pocket.enabled)
                    } else {
                        Button("Download voice pack") { pocketConsent = true }.disabled(pocket.busy || voice.active)
                            .accessibilityIdentifier("downloadPocketVoice")
                    }
                    Text("Pocket TTS by Kyutai · Core ML conversion by FluidInference. Personal Voice lets you import or record your own voice.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if voiceTab == "Personal Voice" {
                PersonalVoiceView(settings: pocket, voice: voice)
            } else {
                Section("Apple voice · fallback") {
                    Button("Use Apple speech") { pocket.enabled = false }.disabled(voice.active || pocket.busy)
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
                Button { voice.previewVoice(appleOnly: true) } label: { Label("Preview voice", systemImage: "speaker.wave.2") }
                    .disabled(voice.active || voice.voices.isEmpty).accessibilityIdentifier("previewVoice")
                Text("For the most natural speech, download a Premium or Enhanced voice in iPhone Settings → Accessibility → Read & Speak → Voices. Automatic uses the best installed voice in your language. Your voice, speed and pitch choices are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                }
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
            .onDisappear { voice.pause(); pocket.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { voice.pause() } }
            .confirmationDialog("Download Pocket TTS?", isPresented: $pocketConsent, titleVisibility: .visible) {
                Button("Download voice pack") { pocket.install() }
            } message: {
                Text("Downloads the English speech model and personal voice encoder from Hugging Face. Allow about 1 GB of storage and use Wi-Fi. After setup, speech and voice cloning work offline. Your recordings are never uploaded.")
            }
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
