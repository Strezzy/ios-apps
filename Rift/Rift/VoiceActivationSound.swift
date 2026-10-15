import AVFoundation
import UIKit

@MainActor protocol VoiceActivationPlaying {
    func play() async
    func stop()
}

/// An original, short, low glass bloom. Generated locally; no bundled or remote recording.
enum VoiceActivationTone {
    static let sampleRate = 48_000
    static let duration = 0.36
    static func waveData() -> Data {
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
            let envelope = (1 - exp(-t * 100)) * exp(-t * 12) * pow(max(0, 1 - t / duration), 2)
            let body = sin(2 * .pi * 246.94 * t) * 0.55 + sin(2 * .pi * 370.41 * t) * 0.25
            let glint = sin(2 * .pi * 740.82 * t) * exp(-t * 18) * 0.12
            let drop = sin(2 * .pi * (180 * t + 190 * t * t)) * 0.18
            number(Int16((body + glint + drop) * envelope * 18_000))
        }
        return data
    }
}

@MainActor final class VoiceActivationSound: VoiceActivationPlaying {
    private var player: AVAudioPlayer?
    func play() async {
        stop()
        do {
            let current = try AVAudioPlayer(data: VoiceActivationTone.waveData())
            let session = AVAudioSession.sharedInstance()
            // Respect the silent switch; finish before enabling the microphone.
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            player = current
            guard current.play() else { stop(); return }
            try? await Task.sleep(for: .seconds(VoiceActivationTone.duration))
            if player === current { stop() }
        } catch { stop() }
    }
    func stop() {
        guard let player else { return }
        player.stop(); self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor enum VoiceOrbFeedback {
    static func play(appearing: Bool) {
        guard UserDefaults.standard.object(forKey: "rift.voiceHaptics") as? Bool ?? true else { return }
        let feedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        feedback.impactOccurred(intensity: appearing ? 0.65 : 0.4)
    }
}
