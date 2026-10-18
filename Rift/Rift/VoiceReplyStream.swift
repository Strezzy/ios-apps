import Foundation

/// Emits stable, speakable phrases once. It never waits for the whole answer.
struct VoiceReplyStream {
    private var emittedPrefix = ""
    private(set) var finished = false
    private(set) var diverged = false
    private(set) var hasSpoken = false
    mutating func take(_ raw: String, final: Bool) -> [String] {
        guard !finished, !diverged else { return [] }
        let text = Self.stableText(raw, final: final)
        guard text.hasPrefix(emittedPrefix) else { diverged = true; return [] }
        var remainder = text.dropFirst(emittedPrefix.count)
        var result: [String] = []
        while !remainder.isEmpty {
            let cut: String.SubSequence.Index
            if final { cut = remainder.endIndex }
            // Start with a shorter, complete-word phrase; keep later chunks
            // long enough for natural prosody and efficient neural synthesis.
            else if let boundary = Self.phraseEnd(remainder, target: hasSpoken ? 180 : 56) { cut = boundary }
            else { break }
            let rawPiece = String(remainder[..<cut])
            let piece = rawPiece.trimmingCharacters(in: .whitespacesAndNewlines)
            emittedPrefix += rawPiece
            if !piece.isEmpty {
                result += VoiceText.chunks(piece)
                hasSpoken = true
            }
            remainder = remainder[cut...]
        }
        if final { finished = true }
        return result
    }
    func canResumeListening(queued: Int, generating: Bool) -> Bool {
        finished && !diverged && queued == 0 && !generating
    }
    static func stableText(_ raw: String, final: Bool) -> String {
        var safe = raw
        // Hold split reasoning tags until their meaning is known.
        if let start = safe.lastIndex(of: "<") {
            let suffix = String(safe[start...])
            if ["<think>", "</think>"].contains(where: { $0.hasPrefix(suffix) && $0 != suffix }) {
                safe = String(safe[..<start])
            }
        }
        safe = safe.replacingOccurrences(of: "(?s)<think>.*?(?:</think>|$)", with: "", options: .regularExpression)
        // Do not release a half-written Markdown link or its destination.
        var cursor = safe.startIndex
        while cursor < safe.endIndex, let start = safe[cursor...].firstIndex(of: "[") {
            guard let close = safe[start...].firstIndex(of: "]") else {
                if !final { safe = String(safe[..<start]) }
                break
            }
            let next = safe.index(after: close)
            if next == safe.endIndex {
                if !final { safe = String(safe[..<start]) }
                break
            }
            if safe[next] == "(" {
                guard let end = safe[next...].firstIndex(of: ")") else { safe = String(safe[..<start]); break }
                cursor = safe.index(after: end)
            } else { cursor = next }
        }
        return VoiceText.spoken(safe)
    }
    private static func phraseEnd(_ text: Substring, target: Int) -> Substring.Index? {
        for index in text.indices {
            let char = text[index], next = text.index(after: index)
            if "。！？\n".contains(char) { return next }
            guard ".!?".contains(char), next < text.endIndex, text[next].isWhitespace else { continue }
            if char == "." {
                let word = text[..<index].split(whereSeparator: { $0.isWhitespace }).last?.lowercased() ?? ""
                if ["mr", "mrs", "ms", "dr", "prof", "e.g", "i.e", "vs"].contains(word) { continue }
            }
            return next
        }
        guard text.count >= target else { return nil }
        let prefix = text.prefix(target)
        let clause = prefix.lastIndex(where: { ",;:".contains($0) })
        if let clause, text.distance(from: text.startIndex, to: clause) >= 32 { return text.index(after: clause) }
        guard let space = prefix.lastIndex(where: { $0.isWhitespace }), text.distance(from: text.startIndex, to: space) >= 32 else { return nil }
        return text.index(after: space)
    }
}
