import AVFoundation
import UIKit
import CoreHaptics

@MainActor protocol VoiceActivationPlaying {
    func play() async
    func stop()
}

/// An original, short, low glass bloom. Generated locally; no bundled or remote recording.
enum VoiceActivationTone {
    static let sampleRate = 48_000
    static let duration = 0.95
    static let closingDuration = 0.8
    static func waveData(appearing: Bool = true) -> Data {
        let duration = appearing ? Self.duration : Self.closingDuration
        let fundamental = appearing ? 246.94 : 196.0
        let count = Int(Double(sampleRate) * duration)
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); number(UInt32(36 + count * 2)); text("WAVEfmt ")
        number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(sampleRate)); number(UInt32(sampleRate * 2))
        number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(count * 2))
        for index in 0..<count {
            let t = Double(index) / Double(sampleRate)
            let envelope = (1 - exp(-t * 70)) * exp(-t * 2.4) * pow(max(0, 1 - t / duration), 0.8)
            let body = sin(2 * .pi * fundamental * t) * 0.55 + sin(2 * .pi * fundamental * 1.5 * t) * 0.25
            let glint = sin(2 * .pi * fundamental * 3 * t) * exp(-t * 5) * 0.12
            let drop = sin(2 * .pi * (appearing ? 180 * t + 65 * t * t : 245 * t - 55 * t * t)) * 0.18
            number(Int16((body + glint + drop) * envelope * 18_000))
        }
        return data
    }
}

@MainActor final class VoiceActivationSound: VoiceActivationPlaying {
    private var player: AVAudioPlayer?
    func play() async { await play(appearing: true) }
    func play(appearing: Bool) async {
        guard !Task.isCancelled else { return }
        stop()
        do {
            let current = try AVAudioPlayer(data: VoiceActivationTone.waveData(appearing: appearing))
            let session = AVAudioSession.sharedInstance()
            // Respect the silent switch; finish before enabling the microphone.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            player = current
            guard current.play() else { stop(); return }
            try? await Task.sleep(for: .seconds(appearing ? VoiceActivationTone.duration : VoiceActivationTone.closingDuration))
            if player === current { stop() }
        } catch { stop() }
    }
    func stop() {
        guard let player else { return }
        player.stop(); self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// A continuous soft pulse with a fading tail, independent of microphone audio.
@MainActor enum VoiceOrbFeedback {
    private static var engine: CHHapticEngine?
    private static var player: (any CHHapticPatternPlayer)?
    private static var closingSound: VoiceActivationSound?
    private static var closingTask: Task<Void, Never>?
    static func play(appearing: Bool) {
        // A rapid reopen cancels the previous close cue before a new microphone session.
        closingTask?.cancel(); closingTask = nil
        closingSound?.stop(); closingSound = nil
        if !appearing, UserDefaults.standard.object(forKey: "rift.voiceActivationSound") as? Bool ?? true {
            let sound = VoiceActivationSound(); closingSound = sound
            closingTask = Task { await sound.play(appearing: false) }
        }
        guard UserDefaults.standard.object(forKey: "rift.voiceHaptics") as? Bool ?? true else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.isAutoShutdownEnabled = true
                engine = created
            }
            guard let engine else { return }
            try engine.start()
            try? player?.stop(atTime: CHHapticTimeImmediate)
            let duration = appearing ? 0.58 : 0.48
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                .init(parameterID: .hapticIntensity, value: appearing ? 0.8 : 0.65),
                .init(parameterID: .hapticSharpness, value: 0.12)
            ], relativeTime: 0, duration: duration)
            let curve = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 0), .init(relativeTime: 0.04, value: 1),
                .init(relativeTime: 0.16, value: 0.7), .init(relativeTime: duration, value: 0)
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [event], parameterCurves: [curve])
            player = try engine.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
        }
    }
}
