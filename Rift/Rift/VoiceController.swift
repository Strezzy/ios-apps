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
    @Published var handsFree = (UserDefaults.standard.object(forKey: "rift.voiceHandsFree") as? Bool) ?? true { didSet { UserDefaults.standard.set(handsFree, forKey: "rift.voiceHandsFree") } }
    @Published private(set) var speechBeat = Date.distantPast
    @Published var language = UserDefaults.standard.string(forKey: "rift.voiceLanguage") ?? Locale.current.identifier { didSet { UserDefaults.standard.set(language, forKey: "rift.voiceLanguage") } }
    @Published var voiceID = UserDefaults.standard.string(forKey: "rift.voiceID") ?? "" { didSet { UserDefaults.standard.set(voiceID, forKey: "rift.voiceID") } }
    @Published var rate = (UserDefaults.standard.object(forKey: "rift.voiceRate") as? Double) ?? 0.47 { didSet { UserDefaults.standard.set(rate, forKey: "rift.voiceRate") } }
    @Published var pitch = (UserDefaults.standard.object(forKey: "rift.voicePitch") as? Double) ?? 1.0 { didSet { UserDefaults.standard.set(pitch, forKey: "rift.voicePitch") } }
    let model: AppModel
    private let speech: any VoiceSpeechService
    private let activationSound: any VoiceActivationPlaying
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
    private var replyStream = VoiceReplyStream()
    private var queuedUtterances = Set<ObjectIdentifier>()
    private var previewing = false
    private var opened = true
    private var wantsListening = false
    private var speechCancellation: Task<Void, Never>?
    private var captureDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("RiftVoiceTurns", isDirectory: true)
    }

    init(model: AppModel, speech: any VoiceSpeechService = LocalSpeechService(), activationSound: (any VoiceActivationPlaying)? = nil) {
        self.model = model
        self.speech = speech
        self.activationSound = activationSound ?? VoiceActivationSound()
        super.init()
        synthesizer.delegate = self
        model.$generating.removeDuplicates().sink { [weak self] value in
            guard !value else { return }
            Task { @MainActor in self?.generationFinished() }
        }.store(in: &subscriptions)
        model.$conversations.sink { [weak self] _ in
            // Published emits before assignment; read the completed snapshot on the actor.
            Task { @MainActor in self?.replyChanged() }
        }.store(in: &subscriptions)
        model.$status.removeDuplicates().sink { [weak self] status in
            guard status == "Stopping", self?.ownsGeneration == true else { return }
            self?.pause(stopGeneration: false)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).sink { [weak self] event in
            guard let type = event.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause(); self?.error = "Voice chat paused for an audio interruption. Tap the orb when you are ready." }
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
    /// Opening the orb is the user's microphone action; constructing a controller is not.
    func open(playActivationSound: Bool = false) async {
        guard opened else { return }
        wantsListening = true
        let id = token.renew()
        if playActivationSound && (UserDefaults.standard.object(forKey: "rift.voiceActivationSound") as? Bool ?? true) {
            await activationSound.play()
        }
        guard opened, token.accepts(id), wantsListening, !Task.isCancelled else { return }
        await load()
        guard opened, token.accepts(id), wantsListening, !Task.isCancelled else { return }
        if assets == .ready { talk() }
    }
    func load() async {
        let requestedLanguage = language
        // Clean up only Rift's own short-lived audio, including after a prior crash.
        try? FileManager.default.removeItem(at: captureDirectory)
        refreshVoices()
        let supported = await speech.languages()
        guard opened, !Task.isCancelled else { return }
        languages = supported
        let state = await speech.state(language: requestedLanguage)
        // Pausing automatic startup must not strand the language check in .checking.
        // open() separately checks its turn token before starting the microphone.
        guard opened, language == requestedLanguage, !Task.isCancelled else { return }
        assets = state
        if state == .unsupported, let first = languages.first(where: { $0.hasPrefix("en_US") || $0.hasPrefix("en-US") }) ?? languages.first {
            language = first
            let fallback = await speech.state(language: first)
            guard opened, language == first, !Task.isCancelled else { return }
            assets = fallback
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
        let candidates = voices.map {
            VoiceChoice(id: $0.identifier, language: $0.language, quality: Int($0.quality.rawValue),
                novelty: $0.voiceTraits.contains(.isNoveltyVoice) || $0.identifier.contains(".eloquence."))
        }
        guard let id = VoiceChoice.preferred(in: candidates, language: language) else { return nil }
        return voices.first { $0.identifier == id }
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
                let state = await speech.state(language: language)
                guard token.accepts(id), opened, !Task.isCancelled else { return }
                assets = state
            } catch { if token.accepts(id), !(error is CancellationError) { self.error = error.localizedDescription } }
            if token.accepts(id) {
                phase = .idle
                if assets == .ready && wantsListening { talk() }
            }
        }
    }
    func talk() {
        guard opened, phase == .idle || phase == .speaking else { return }
        // Interrupting spoken output also cancels its still-generating text turn.
        if phase == .speaking && ownsGeneration {
            pause()
            wantsListening = true
            let turn = token.id
            operation = Task { [weak self] in
                while let self, self.model.generating {
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    guard self.opened, self.token.accepts(turn) else { return }
                }
                guard let self, self.opened, self.token.accepts(turn), self.wantsListening else { return }
                self.talk()
            }
            return
        }
        guard model.ready, model.selectedModel != nil, !model.busy, !model.generating else {
            error = "Choose and download a chat model first, and finish any active reply or transfer."; return
        }
        guard assets == .ready else { error = "Prepare the on-device speech language first."; return }
        guard chosenVoice != nil else { error = "Install an Apple speech voice in Settings → Accessibility → Read & Speak → Voices, then reopen voice mode."; return }
        pause()
        wantsListening = true
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
                // Silence always submits a spoken turn. Hands-free controls only relistening.
                if gate.shouldFinish(elapsed: elapsed, handsFree: true) {
                    if gate.heardSpeech { self.sendRecording() }
                    else { self.pause(); self.talk() } // Rotate the bounded file while waiting quietly.
                    return
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
            self.pause(); self.error = "On-device transcription took too long. Tap the orb to retry."
        }
        operation = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                await speechCancellation?.value
                try Task.checkCancellation()
                let text = try await speech.transcribe(file: url, language: language)
                guard token.accepts(id), opened, !Task.isCancelled else { return }
                deadline?.cancel(); deadline = nil
                guard !text.isEmpty else { throw RiftFailure("No words were recognized. Tap the orb and speak clearly, or use text chat.") }
                heard = text; phase = .thinking
                guard model.send(text), model.generating else { throw RiftFailure(model.error ?? "The local model could not begin a reply. Your transcription is shown in the chat; you can copy it.") }
                awaitedReply = model.activeChat?.messages.last?.id; awaitedChat = model.activeChatID; ownsGeneration = true
                replyStream = VoiceReplyStream()
                replyChanged()
            } catch {
                if token.accepts(id), !(error is CancellationError) { pause(); self.error = error.localizedDescription }
            }
        }
    }
    private func replyChanged() {
        guard opened, ownsGeneration, model.activeChatID == awaitedChat,
              let reply = model.activeChat?.messages.last, reply.id == awaitedReply else { return }
        guard !reply.isFailedReply, !reply.interrupted else { return }
        answer = ReplyParts.parse(reply.content).answer
        let chunks = replyStream.take(reply.content, final: false)
        if replyStream.diverged {
            pause(); error = "The reply changed while it was being spoken. Its text remains in your chat."; return
        }
        if !chunks.isEmpty { enqueue(chunks, preview: false) }
    }
    private func generationFinished() {
        guard opened, ownsGeneration, !model.generating else { return }
        guard model.activeChatID == awaitedChat,
              let reply = model.activeChat?.messages.last, reply.id == awaitedReply,
              !reply.isFailedReply, !reply.interrupted else {
            pause(); error = model.error ?? "The reply was stopped. Tap the orb to continue."; return
        }
        answer = ReplyParts.parse(reply.content).answer
        let tail = replyStream.take(reply.content, final: true)
        ownsGeneration = false
        if replyStream.diverged { pause(); error = "The reply changed while it was being spoken."; return }
        if !tail.isEmpty { enqueue(tail, preview: false) }
        if queuedUtterances.isEmpty {
            if replyStream.hasSpoken { playbackDrained() }
            else { phase = .idle; error = "There is no spoken answer yet. The model's output remains in your chat." }
        }
    }
    func previewVoice() {
        guard phase == .idle || (phase == .speaking && previewing) else { return }
        pause(); error = nil
        say("Hello. This is how I will sound in Rift. Everything you hear is spoken on your device.", preview: true)
    }
    private func say(_ text: String, preview: Bool) {
        let chunks = VoiceText.chunks(text)
        guard !chunks.isEmpty else { phase = .idle; error = "There is no spoken answer yet. The model's output remains in your chat."; return }
        enqueue(chunks, preview: preview)
    }
    private func enqueue(_ chunks: [String], preview: Bool) {
        guard let voice = chosenVoice else { pause(); error = "No installed Apple voice is available."; return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch { pause(); self.error = error.localizedDescription; return }
        previewing = preview; phase = .speaking
        for chunk in chunks {
            let utterance = AVSpeechUtterance(string: chunk)
            utterance.voice = voice
            utterance.rate = Float(max(0.35, min(0.65, rate)))
            utterance.pitchMultiplier = Float(max(0.75, min(1.25, pitch)))
            utterance.postUtteranceDelay = VoiceText.pause(after: chunk)
            queuedUtterances.insert(ObjectIdentifier(utterance))
            synthesizer.speak(utterance)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let energy = min(1, 0.35 + Double(characterRange.length) * 0.065)
        Task { @MainActor [weak self] in
            guard let self, self.opened, self.phase == .speaking,
                  self.queuedUtterances.contains(id) else { return }
            self.level = energy; self.speechBeat = Date()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.queuedUtterances.remove(id) != nil,
                  self.queuedUtterances.isEmpty, self.phase == .speaking else { return }
            self.playbackDrained()
        }
    }
    private func playbackDrained() {
        guard queuedUtterances.isEmpty else { return }
        level = 0
        if ownsGeneration { phase = .thinking; return }
        let again = handsFree && wantsListening && !previewing && opened
            && replyStream.canResumeListening(queued: queuedUtterances.count, generating: model.generating)
        phase = .idle; previewing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if again {
            let turn = token.id
            operation = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                guard let self, self.opened, self.token.accepts(turn), self.handsFree, self.wantsListening else { return }
                self.talk()
            }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.queuedUtterances.contains(id) else { return }
            self.pause(); self.error = "Speech playback was interrupted. Tap the orb to continue."
        }
    }
    func pause(stopGeneration: Bool = true) {
        activationSound.stop()
        wantsListening = false
        token.renew(); operation?.cancel(); operation = nil; deadline?.cancel(); deadline = nil
        clock?.cancel(); clock = nil; recorder?.stop(); recorder = nil
        if let captureURL { try? FileManager.default.removeItem(at: captureURL) }; captureURL = nil
        queuedUtterances.removeAll(); synthesizer.stopSpeaking(at: .immediate)
        speechCancellation = Task { await speech.cancel() }
        let cancelGeneration = ownsGeneration
        ownsGeneration = false; awaitedReply = nil; awaitedChat = nil
        if cancelGeneration && stopGeneration { model.stop() }
        replyStream = VoiceReplyStream()
        level = 0; phase = .idle; previewing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func close() {
        guard opened else { return }
        opened = false; pause()
    }
}
