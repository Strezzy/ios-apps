import SwiftUI
import UIKit
import AVFoundation
import Combine

@MainActor final class VoiceController: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var phase: VoicePhase = .idle
    @Published private(set) var assets: SpeechAssetState = .checking
    @Published private(set) var languages: [String] = []
    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []
    @Published private(set) var level: Double = 0
    @Published private(set) var heard = ""
    @Published private(set) var answer = ""
    @Published var error: String?
    @Published var handsFree = false
    @Published var language = UserDefaults.standard.string(forKey: "rift.voiceLanguage") ?? Locale.current.identifier { didSet { UserDefaults.standard.set(language, forKey: "rift.voiceLanguage") } }
    @Published var voiceID = UserDefaults.standard.string(forKey: "rift.voiceID") ?? "" { didSet { UserDefaults.standard.set(voiceID, forKey: "rift.voiceID") } }
    @Published var rate = (UserDefaults.standard.object(forKey: "rift.voiceRate") as? Double) ?? 0.48 { didSet { UserDefaults.standard.set(rate, forKey: "rift.voiceRate") } }
    @Published var pitch = (UserDefaults.standard.object(forKey: "rift.voicePitch") as? Double) ?? 1.0 { didSet { UserDefaults.standard.set(pitch, forKey: "rift.voicePitch") } }
    let model: AppModel
    private let speech = LocalSpeechService()
    private let synthesizer = AVSpeechSynthesizer()
    private var recorder: AVAudioRecorder?
    private var captureURL: URL?
    private var clock: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var token = VoiceTurnToken()
    private var subscriptions = Set<AnyCancellable>()
    private var awaitedReply: UUID?
    private var awaitedChat: UUID?
    private var ownsGeneration = false
    private var queuedUtterances = Set<ObjectIdentifier>()
    private var previewing = false
    private var opened = true
    private var captureDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RiftVoiceTurns", isDirectory: true)
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        synthesizer.delegate = self
        model.$generating.removeDuplicates().sink { [weak self] value in
            guard !value else { return }
            Task { @MainActor in self?.generationFinished() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).sink { [weak self] event in
            guard let type = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause(); self?.error = "Voice chat paused for an audio interruption. Tap Talk when you are ready." }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).sink { [weak self] event in
            guard let reason = event.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.pause(); self?.error = "Your audio device disconnected. Voice chat is paused." }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification).sink { [weak self] _ in
            Task { @MainActor in self?.refreshVoices() }
        }.store(in: &subscriptions)
    }
    func load() async {
        // Clean up only Rift's own short-lived audio, including after a prior crash.
        try? FileManager.default.removeItem(at: captureDirectory)
        refreshVoices()
        languages = await speech.languages()
        guard opened else { return }
        assets = await speech.state(language: language)
        if assets == .unsupported, let first = languages.first(where: { $0.hasPrefix("en_US") || $0.hasPrefix("en-US") }) ?? languages.first {
            language = first; assets = await speech.state(language: first)
        }
    }
    func languageChanged() async {
        pause(); assets = .checking
        let chosen = language
        let result = await speech.state(language: chosen)
        guard chosen == language, opened else { return }
        assets = result
    }
    func refreshVoices() {
        // Do not select third-party voice providers, which could have their own network behavior.
        voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.identifier.hasPrefix("com.apple.") && !$0.voiceTraits.contains(.isPersonalVoice)
        }.sorted { ($0.language, $0.name, $0.identifier) < ($1.language, $1.name, $1.identifier) }
    }
    var chosenVoice: AVSpeechSynthesisVoice? {
        if let stored = voices.first(where: { $0.identifier == voiceID }) { return stored }
        let code = Locale(identifier: language).language.languageCode?.identifier ?? "en"
        return voices.first { $0.language.hasPrefix(code) } ?? voices.first
    }
    var active: Bool { phase != .idle }
    func prepareLanguage() {
        guard phase == .idle else { return }
        let id = token.renew(); phase = .preparing; error = nil
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                try await speech.install(language: language)
                guard token.accepts(id), opened, !Task.isCancelled else { return }
                assets = await speech.state(language: language)
            } catch { if token.accepts(id), !(error is CancellationError) { self.error = error.localizedDescription } }
            if token.accepts(id) { phase = .idle }
        }
    }
    func talk() {
        guard opened, phase == .idle || phase == .speaking else { return }
        guard model.ready, model.selectedModel != nil, !model.busy, !model.generating else {
            error = "Choose and download a chat model first, and finish any active reply or transfer."; return
        }
        guard assets == .ready else { error = "Prepare the on-device speech language first."; return }
        guard chosenVoice != nil else { error = "Install an Apple speech voice in Settings → Accessibility → Read & Speak → Voices, then reopen voice mode."; return }
        pause()
        error = nil; heard = ""; answer = ""; phase = .preparing
        let id = token.renew()
        operation = Task { [weak self] in
            guard let self else { return }
            let granted = await AVAudioApplication.requestRecordPermission()
            guard opened, token.accepts(id), !Task.isCancelled else { return }
            guard granted else { phase = .idle; error = "Microphone access was denied. Enable it in iPhone Settings for this app or the LiveContainer host. Nothing was recorded."; return }
            do { try startRecording(id: id) }
            catch { if token.accepts(id) { pause(); self.error = error.localizedDescription } }
        }
    }
    private func startRecording(id: UUID) throws {
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        var directory = captureDirectory
        var values = URLResourceValues(); values.isExcludedFromBackup = true; try directory.setResourceValues(values)
        let url = captureDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try audio.setActive(true)
        let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        captureURL = url; recorder = r
        r.isMeteringEnabled = true
        guard r.prepareToRecord(), r.record(forDuration: 46) else { throw RiftFailure("The microphone could not start. Close other recording apps and try again.") }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        phase = .listening
        let began = ProcessInfo.processInfo.systemUptime
        clock = Task { [weak self] in
            var gate = VoiceSilenceGate()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, self.token.accepts(id), self.phase == .listening, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let db = recorder.averagePower(forChannel: 0)
                self.level = min(1, max(0, Double(db + 55) / 50))
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                gate.observe(decibels: db, elapsed: elapsed)
                if gate.shouldFinish(elapsed: elapsed, handsFree: self.handsFree) { self.sendRecording(); return }
                if elapsed > 15 && !gate.heardSpeech {
                    self.pause(); self.error = "No speech was detected. Tap Talk to try again."; return
                }
            }
        }
    }
    func sendRecording() {
        guard phase == .listening, let url = captureURL else { return }
        recorder?.stop(); recorder = nil; captureURL = nil
        clock?.cancel(); clock = nil; level = 0; phase = .transcribing
        let id = token.id
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(40)) } catch { return }
            guard let self, self.token.accepts(id), self.phase == .transcribing else { return }
            self.pause(); self.error = "On-device transcription took too long. Tap Talk to retry." 
        }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                let text = try await speech.transcribe(file: url, language: language)
                guard token.accepts(id), opened, !Task.isCancelled else { return }
                deadline?.cancel(); deadline = nil
                guard !text.isEmpty else { throw RiftFailure("No words were recognized. Tap Talk and speak clearly, or use text chat.") }
                heard = text; phase = .thinking
                guard model.send(text), model.generating else { throw RiftFailure(model.error ?? "The local model could not begin a reply. Your transcription is shown above; you can copy it.") }
                awaitedReply = model.activeChat?.messages.last?.id; awaitedChat = model.activeChatID; ownsGeneration = true
            } catch {
                if token.accepts(id), !(error is CancellationError) { pause(); self.error = error.localizedDescription }
            }
        }
    }
    private func generationFinished() {
        guard opened, phase == .thinking, ownsGeneration, !model.generating else { return }
        ownsGeneration = false
        guard model.activeChatID == awaitedChat,
              let reply = model.activeChat?.messages.last, reply.id == awaitedReply,
              !reply.isFailedReply, !reply.interrupted else {
            phase = .idle; error = model.error ?? "The reply was stopped. Tap Talk to continue."; return
        }
        answer = ReplyParts.parse(reply.content).answer
        say(VoiceText.spoken(reply.content), preview: false)
    }
    func previewVoice() {
        guard phase == .idle || (phase == .speaking && previewing) else { return }
        pause(); error = nil
        say("Hello. This is how I will sound in Rift. Everything you hear is spoken on your device.", preview: true)
    }
    private func say(_ text: String, preview: Bool) {
        guard let voice = chosenVoice else { phase = .idle; error = "No installed Apple voice is available."; return }
        let chunks = VoiceText.chunks(text)
        guard !chunks.isEmpty else { phase = .idle; error = "There is no spoken answer yet. The model's output remains in your chat."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch { phase = .idle; self.error = error.localizedDescription; return }
        previewing = preview; phase = .speaking
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = Float(max(0.35, min(0.65, rate)))
            utterance.pitchMultiplier = Float(max(0.75, min(1.25, pitch)))
            queuedUtterances.insert(ObjectIdentifier(utterance))
            synthesizer.speak(utterance)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.queuedUtterances.remove(id) != nil,
                  self.queuedUtterances.isEmpty, self.phase == .speaking else { return }
            let again = self.handsFree && !self.previewing && self.opened
            self.phase = .idle; self.previewing = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if again {
                let turn = self.token.id
                self.operation = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                    guard let self, self.opened, self.token.accepts(turn), self.handsFree else { return }
                    self.talk()
                }
            }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.queuedUtterances.contains(id) else { return }
            self.pause(); self.error = "Speech playback was interrupted. Tap Talk to continue."
        }
    }
    func pause() {
        token.renew(); operation?.cancel(); operation = nil; deadline?.cancel(); deadline = nil
        clock?.cancel(); clock = nil; recorder?.stop(); recorder = nil
        if let captureURL { try? FileManager.default.removeItem(at: captureURL) }; captureURL = nil
        queuedUtterances.removeAll(); synthesizer.stopSpeaking(at: .immediate)
        Task { await speech.cancel() }
        if ownsGeneration { model.stop() }; ownsGeneration = false; awaitedReply = nil; awaitedChat = nil
        level = 0; phase = .idle; previewing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func close() { opened = false; handsFree = false; pause() }
}
