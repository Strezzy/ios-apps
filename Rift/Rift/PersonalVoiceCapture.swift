import AVFoundation
import Combine

@MainActor final class PersonalVoiceCapture: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var recording = false
    @Published private(set) var requesting = false
    @Published private(set) var seconds = 0
    @Published private(set) var file: URL?
    @Published var error: String?
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Task<Void, Never>?
    private var identity = UUID()
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("RiftPersonalVoiceCapture", isDirectory: true)

    func record() {
        clear(); error = nil; requesting = true
        let id = identity
        Task {
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard identity == id else { return }
            requesting = false
            guard allowed else { error = "Enable microphone access in iPhone Settings to record your voice."; return }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent(UUID().uuidString + ".wav")
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
                let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 24_000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
                self.recorder = recorder; recorder.delegate = self; file = url
                guard recorder.record(forDuration: 10) else { throw RiftFailure("The microphone could not start.") }
                try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
                recording = true
                timer = Task {
                    while !Task.isCancelled, identity == id, recording {
                        do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                        seconds = Int(recorder.currentTime)
                    }
                }
            } catch { clear(); self.error = error.localizedDescription }
        }
    }
    func stop() {
        recorder?.stop(); recorder = nil; recording = false; timer?.cancel(); timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let file {
            do { try PersonalVoiceLibrary.validateRecording(file) }
            catch { self.error = error.localizedDescription; clear() }
        }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.stop()
            if !flag { self.error = "Recording was interrupted. Please record again."; self.clear() }
        }
    }
    func importFile(_ url: URL) {
        clear(); error = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try PersonalVoiceLibrary.validateRecording(url)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            file = destination
        } catch { self.error = error.localizedDescription }
    }
    func previewRecording() {
        guard let file, !recording else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: file); player?.play()
        } catch { self.error = error.localizedDescription }
    }
    func clear() {
        identity = UUID(); requesting = false; timer?.cancel(); timer = nil
        recorder?.stop(); recorder = nil; player?.stop(); player = nil
        recording = false; seconds = 0
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
