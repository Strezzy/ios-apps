import AVFoundation
import FluidAudio

/// Text stays queued during session creation; completion means audio was heard,
/// not merely synthesized. A generation identity rejects every stale callback.
@MainActor final class PocketReplyPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
    private var session: PocketTtsSession?
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var identity = UUID()
    private var chunks: [String] = []
    private var sent = 0
    private var finished = false
    private var generated = false
    private var buffers = 0
    private var completedUtterance = -1
    private var lastActivity = Date()
    private var lastEnqueued = Date()
    private var playedUtterance = -1
    private(set) var active = false
    var onLevel: ((Double) -> Void)?
    var onDrained: (() -> Void)?
    var onFailure: (([String], String) -> Void)?

    private let makeSession: @Sendable (URL?) async throws -> PocketTtsSession
    init(makeSession: @escaping @Sendable (URL?) async throws -> PocketTtsSession = { try await PocketSpeechEngine.shared.session(profile: $0) }) {
        self.makeSession = makeSession
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
    }
    func enqueue(_ texts: [String], profile: URL?) {
        if !active { start(profile: profile) }
        chunks += texts; lastEnqueued = Date()
        flush()
    }
    func finish() { finished = true; session?.finish() }
    private func flush() {
        guard let session else { return }
        while sent < chunks.count { session.enqueue(chunks[sent]); sent += 1 }
        if finished { session.finish() }
    }
    private func start(profile: URL?) {
        stop(); active = true
        let id = identity
        lastActivity = Date(); lastEnqueued = Date()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let newSession = try await self.makeSession(profile)
                guard self.identity == id, !Task.isCancelled else { await newSession.cancel(); return }
                self.session = newSession; self.flush()
                var hadAudio = false
                for try await frame in newSession.frames {
                    try Task.checkCancellation()
                    guard self.identity == id else { return }
                    guard !frame.samples.isEmpty, frame.samples.allSatisfy({ $0.isFinite }) else {
                        throw RiftFailure("The neural voice produced invalid audio.")
                    }
                    // Bound queued playback to roughly 1.6 seconds. This also
                    // keeps stop/interrupt independent of synthesis throughput.
                    while self.buffers >= 20 {
                        try await Task.sleep(for: .milliseconds(20))
                        guard self.identity == id else { return }
                    }
                    try self.schedule(frame.samples, utterance: frame.utteranceIndex ?? 0, id: id)
                    hadAudio = true; self.lastActivity = Date()
                }
                guard self.identity == id, !Task.isCancelled else { return }
                guard hadAudio else { throw RiftFailure("The neural voice returned no audio.") }
                self.generated = true; self.drainIfReady()
            } catch {
                guard self.identity == id, !Task.isCancelled else { return }
                self.fail(error.localizedDescription)
            }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.identity == id, self.active else { return }
                // Silence while waiting for additional LLM text is expected.
                // Queued speech with no progress falls back without trapping UI.
                let waiting = (self.playedUtterance < 0 && !self.chunks.isEmpty) || (self.finished && !self.generated)
                if waiting && self.buffers == 0 && Date().timeIntervalSince(max(self.lastActivity, self.lastEnqueued)) > 8 {
                    self.fail("Pocket speech took too long; using your Apple voice."); return
                }
            }
        }
    }
    private func schedule(_ samples: [Float], utterance: Int, id: UUID) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = buffer.floatChannelData?[0] else { throw RiftFailure("Audio playback could not allocate a buffer.") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { destination.update(from: $0.baseAddress!, count: samples.count) }
        if !engine.isRunning { engine.prepare(); try engine.start() }
        buffers += 1
        let energy = min(1, sqrt(samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)) * 5)
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.identity == id, self.active else { return }
                self.buffers -= 1
                // Once the next utterance is audible, every preceding one has played.
                self.completedUtterance = max(self.completedUtterance, utterance - 1)
                self.playedUtterance = max(self.playedUtterance, utterance)
                self.onLevel?(energy); self.drainIfReady()
            }
        }
        if !player.isPlaying { player.play() }
    }
    private func drainIfReady() {
        guard active, generated, buffers == 0 else { return }
        stop(); onDrained?()
    }
    private func fail(_ message: String) {
        let remaining = Array(chunks.dropFirst(completedUtterance + 1))
        stop(); onFailure?(remaining, message)
    }
    func stop() {
        identity = UUID(); active = false
        task?.cancel(); task = nil; watchdog?.cancel(); watchdog = nil
        let oldSession = session; session = nil
        if let oldSession { Task { await oldSession.cancel() } }
        player.stop(); engine.stop()
        chunks = []; sent = 0; finished = false; generated = false; buffers = 0
        completedUtterance = -1; playedUtterance = -1
    }
}
