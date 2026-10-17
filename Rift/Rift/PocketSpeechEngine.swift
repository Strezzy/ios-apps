import Foundation
import Combine
import FluidAudio

/// The only owner of the neural models. Ordinary speech and cloning are offline;
/// only the explicit settings download may open the dependency's network gate.
actor PocketSpeechEngine {
    static let shared = PocketSpeechEngine()
    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RiftPocketTTS", isDirectory: true)
    static var marker: URL { directory.appendingPathComponent("installed-v1") }
    nonisolated static var installed: Bool { FileManager.default.fileExists(atPath: marker.path) }
    private var manager: PocketTtsManager?
    private var loading: Task<PocketTtsManager, Error>?
    private var installing = false

    init() {
        ModelRegistry.revisionOverrides = ["FluidInference/pocket-tts-coreml": "91748676fe3c8b2eb3007b3125253bcd898202c3"]
        ModelHub.offlineMode = true
    }

    func install() async throws {
        guard !installing else { throw RiftFailure("The voice pack is already downloading.") }
        installing = true
        ModelHub.offlineMode = false
        defer { installing = false; ModelHub.offlineMode = true }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        var directory = Self.directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        _ = try await PocketTtsResourceDownloader.ensureModels(language: .english, directory: directory, precision: .int8)
        try Task.checkCancellation()
        // Include the encoder in setup so importing a personal recording stays offline.
        _ = try await PocketTtsResourceDownloader.ensureMimiEncoder(directory: directory)
        try Task.checkCancellation()
        let model = Self.makeManager()
        try await model.initialize()
        try Task.checkCancellation()
        try Data("Pocket TTS English + personal voice encoder".utf8).write(to: Self.marker, options: .atomic)
        manager = model
    }
    private static func makeManager() -> PocketTtsManager {
        // Avoid known ANE compilation aborts in current converted models. Mimi
        // remains on CPU; transformer work uses Core ML's CPU/GPU placement.
        PocketTtsManager(directory: directory, precision: .int8, computeUnits: .avoidNeuralEngine)
    }
    private func ready() async throws -> PocketTtsManager {
        guard !installing, Self.installed else { throw RiftFailure("Download the Pocket voice pack in Voice & sound settings first.") }
        if let manager { return manager }
        if let loading { return try await loading.value }
        let task = Task {
            let model = Self.makeManager()
            try await model.initialize()
            try Task.checkCancellation()
            return model
        }
        loading = task
        do {
            let model = try await task.value
            manager = model; loading = nil
            return model
        } catch { loading = nil; throw error }
    }
    func warm() async { _ = try? await ready() }
    func session(profile: URL?) async throws -> PocketTtsSession {
        let model = try await ready()
        try Task.checkCancellation()
        if let profile {
            let data = try model.loadClonedVoice(from: profile)
            return try await model.makeSession(voiceData: data)
        }
        return try await model.makeSession(voice: "alba")
    }
    func clone(recording: URL, name: String, library: PersonalVoiceLibrary) async throws -> PersonalVoice {
        try PersonalVoiceLibrary.validateRecording(recording)
        let model = try await ready()
        let data = try await model.cloneVoice(from: recording)
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bin")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try model.saveClonedVoice(data, to: temporary)
        return try library.save(profile: Data(contentsOf: temporary), name: name)
    }
    func unload() {
        loading?.cancel(); loading = nil; manager = nil
    }
}

@MainActor final class PocketVoiceSettings: ObservableObject {
    static let shared = PocketVoiceSettings()
    @Published var enabled = (UserDefaults.standard.object(forKey: "rift.pocketEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "rift.pocketEnabled") }
    }
    @Published var selected = UserDefaults.standard.string(forKey: "rift.personalVoiceID") ?? "" {
        didSet { UserDefaults.standard.set(selected, forKey: "rift.personalVoiceID") }
    }
    @Published private(set) var installed = PocketSpeechEngine.installed
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    @Published private(set) var personal: [PersonalVoice] = []
    @Published var error: String?
    let library = PersonalVoiceLibrary()
    private var operation: Task<Void, Never>?
    init() { reload() }
    var selectedProfile: URL? {
        guard let voice = personal.first(where: { $0.id.uuidString == selected }) else { return nil }
        return library.profileURL(voice.id)
    }
    func canUse(language: String) -> Bool {
        enabled && installed && language.lowercased().hasPrefix("en") && !busy
    }
    func reload() {
        do { personal = try library.entries() } catch { self.error = error.localizedDescription }
        if !selected.isEmpty && !personal.contains(where: { $0.id.uuidString == selected }) { selected = "" }
    }
    func install() {
        guard !busy else { return }
        busy = true; error = nil; status = "Downloading voice pack and personal voice encoder…"
        operation = Task {
            defer { busy = false; operation = nil }
            do {
                try await PocketSpeechEngine.shared.install()
                try Task.checkCancellation()
                installed = true; enabled = true; status = "Ready · works offline"
            } catch { if !Task.isCancelled { self.error = error.localizedDescription }; status = "" }
        }
    }
    func importVoice(_ url: URL, name: String) {
        guard !busy else { return }
        busy = true; error = nil; status = "Creating your personal voice on this device…"
        operation = Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; busy = false; operation = nil }
            do {
                let voice = try await PocketSpeechEngine.shared.clone(recording: url, name: name, library: library)
                reload(); selected = voice.id.uuidString; enabled = true; status = "Personal voice saved"
            } catch { if !Task.isCancelled { self.error = error.localizedDescription }; status = "" }
        }
    }
    func cancel() { operation?.cancel() }
    func delete(_ voice: PersonalVoice) {
        do { try library.delete(voice); reload() } catch { self.error = error.localizedDescription }
    }
}
