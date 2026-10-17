import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct PersonalVoiceView: View {
    @ObservedObject var settings: PocketVoiceSettings
    @ObservedObject var voice: VoiceController
    @StateObject private var capture = PersonalVoiceCapture()
    @State private var importing = false
    @State private var name = "My Voice"
    @State private var deleting: PersonalVoice?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
        Section("Personal Voice") {
            Text("Create a voice from 3–10 seconds of your speech. Five to ten seconds of clear speech with no music works best. The recording stays on this device.")
                .font(.caption).foregroundStyle(.secondary)
            if !settings.installed {
                Text("Download the Pocket voice pack in the Pocket TTS tab first.").font(.caption)
            }
            TextField("Voice name", text: $name).accessibilityIdentifier("personalVoiceName")
                .disabled(settings.busy)
            Button { importing = true } label: { Label("Import audio file", systemImage: "square.and.arrow.down") }
                .disabled(!settings.installed || settings.busy || voice.active || capture.recording || capture.requesting)
                .accessibilityIdentifier("importPersonalVoice")
            Button {
                if capture.recording { capture.stop() } else { voice.pause(); capture.record() }
            } label: {
                Label(capture.recording ? "Stop recording · \(capture.seconds)s" : "Record my voice", systemImage: capture.recording ? "stop.circle" : "mic.circle")
            }.disabled(!settings.installed || settings.busy || capture.requesting)
                .accessibilityIdentifier("recordPersonalVoice")
            if capture.recording { Text("Speak naturally. Recording stops after 10 seconds.").font(.caption) }
            if capture.file != nil && !capture.recording {
                Button("Preview recording") { voice.pause(); capture.previewRecording() }.disabled(settings.busy)
                Button("Save personal voice") {
                    guard let file = capture.file else { return }
                    voice.pause(); settings.importVoice(file, name: name)
                }.disabled(settings.busy).accessibilityIdentifier("savePersonalVoice")
                Button("Discard recording", role: .destructive) { capture.clear() }.disabled(settings.busy)
            }
            if let error = capture.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        Section("Saved voices") {
            if settings.personal.isEmpty { Text("Your saved voices will appear here.").foregroundStyle(.secondary) }
            ForEach(settings.personal) { item in
                HStack {
                    Button {
                        voice.pause(); settings.selected = item.id.uuidString; settings.enabled = true
                    } label: {
                        Label(item.name, systemImage: settings.selected == item.id.uuidString ? "checkmark.circle.fill" : "person.wave.2")
                    }.buttonStyle(.borderless).disabled(settings.busy)
                    Spacer()
                    Button { deleting = item } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).accessibilityLabel("Delete \(item.name)").disabled(settings.busy || voice.active)
                }
            }
            Button { capture.clear(); voice.previewVoice() } label: { Label("Preview selected voice", systemImage: "speaker.wave.2") }
                .disabled(settings.busy || settings.selectedProfile == nil || voice.active || capture.recording)
        }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            do { capture.importFile(try result.get()) } catch { capture.error = error.localizedDescription }
        }
        .confirmationDialog("Delete this personal voice?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete voice", role: .destructive) { if let deleting { settings.delete(deleting) }; deleting = nil }
        }
        .onChange(of: settings.busy) { old, new in
            if old && !new && settings.error == nil { capture.clear() }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { capture.clear(); settings.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in capture.clear() }
        .onDisappear { settings.cancel(); capture.clear() }
    }
}
