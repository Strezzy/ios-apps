import Foundation

enum VoicePhase: String, Equatable, Sendable {
    case idle, preparing, listening, transcribing, thinking, speaking
    var title: String {
        switch self {
        case .idle: return "Ready when you are"
        case .preparing: return "Preparing voice"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing on-device"
        case .thinking: return "Thinking on-device"
        case .speaking: return "Speaking"
        }
    }
}
enum SpeechAssetState: Equatable, Sendable { case checking, unsupported, needsDownload, ready }

/// A new turn or cancellation invalidates all asynchronous callbacks from the old turn.
struct VoiceTurnToken: Equatable {
    private(set) var id = UUID()
    @discardableResult mutating func renew() -> UUID { id = UUID(); return id }
    func accepts(_ candidate: UUID) -> Bool { id == candidate }
}

struct VoiceSilenceGate {
    private(set) var heardSpeech = false
    private var voicedSamples = 0
    private var lastVoice: TimeInterval = 0
    mutating func observe(decibels: Float, elapsed: TimeInterval) {
        guard decibels.isFinite, elapsed.isFinite else { return }
        if decibels > -38 {
            voicedSamples += 1
            lastVoice = elapsed
            if voicedSamples >= 3 { heardSpeech = true }
        } else if !heardSpeech { voicedSamples = 0 }
    }
    func shouldFinish(elapsed: TimeInterval, handsFree: Bool) -> Bool {
        elapsed >= 45 || (handsFree && heardSpeech && elapsed >= 1.5 && elapsed - lastVoice > 1.0)
    }
}

/// Prefer a natural voice in the requested language, then quality, then dialect.
/// Kept independent of AVFoundation so selection is testable without installed assets.
struct VoiceChoice {
    let id: String
    let language: String
    let quality: Int
    var novelty = false
    static func preferred(in voices: [Self], language: String) -> String? {
        let locale = language.replacingOccurrences(of: "_", with: "-").lowercased()
        let code = locale.split(separator: "-").first
        let matching = voices.filter { $0.language.lowercased().split(separator: "-").first == code }
        let natural = matching.filter { !$0.novelty }
        return (natural.isEmpty ? matching : natural).sorted { left, right in
            if left.quality != right.quality { return left.quality > right.quality }
            let l = left.language.replacingOccurrences(of: "_", with: "-").lowercased() == locale
            let r = right.language.replacingOccurrences(of: "_", with: "-").lowercased() == locale
            if l != r { return l }
            return left.id < right.id
        }.first?.id
    }
}

enum VoiceText {
    /// Never speak model reasoning, fenced code, or Markdown link destinations.
    static func spoken(_ raw: String) -> String {
        var value = ReplyParts.parse(raw).answer
        value = value.replacingOccurrences(of: "(?s)```.*?(?:```|$)", with: " Code is shown in the chat. ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"!?\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^\\s{0,3}#{1,6}\\s+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[*_`~]", with: "", options: .regularExpression)
        return String(value.prefix(16_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func chunks(_ text: String, maximum: Int = 650) -> [String] {
        let limit = max(32, maximum)
        var remainder = text[...], result: [String] = []
        while !remainder.isEmpty {
            let end = remainder.index(remainder.startIndex, offsetBy: limit, limitedBy: remainder.endIndex) ?? remainder.endIndex
            var cut = end
            if end != remainder.endIndex {
                let sentence = remainder[..<end].lastIndex(where: { ".!?。！？\n".contains($0) })
                let word = remainder[..<end].lastIndex(where: { $0.isWhitespace })
                if let sentence, remainder.distance(from: remainder.startIndex, to: sentence) > limit / 3 {
                    cut = remainder.index(after: sentence)
                } else if let word, remainder.distance(from: remainder.startIndex, to: word) > limit / 2 {
                    cut = remainder.index(after: word)
                }
            }
            let piece = String(remainder[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            remainder = remainder[cut...]
        }
        return result
    }
    static func pause(after text: String) -> TimeInterval {
        guard let last = text.last else { return 0 }
        return ".!?。！？".contains(last) ? 0.12 : 0.025
    }
}
