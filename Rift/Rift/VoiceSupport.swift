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
        }
    }
    func shouldFinish(elapsed: TimeInterval, handsFree: Bool) -> Bool {
        elapsed >= 45 || (handsFree && heardSpeech && elapsed >= 1.5 && elapsed - lastVoice > 1.3)
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
            if end != remainder.endIndex, let boundary = remainder[..<end].lastIndex(where: { $0.isWhitespace || ".!?。！？".contains($0) }) {
                if remainder.distance(from: remainder.startIndex, to: boundary) > limit / 2 { cut = remainder.index(after: boundary) }
            }
            let piece = String(remainder[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { result.append(piece) }
            remainder = remainder[cut...]
        }
        return result
    }
}
