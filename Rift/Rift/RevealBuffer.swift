import Foundation

/// Presentation-only scheduling. The original reply remains the source of truth.
struct RevealBuffer: Sendable {
    struct Glyph: Sendable, Equatable {
        let character: Character
        var birth: TimeInterval
    }
    private(set) var glyphs: [Glyph] = []
    static let settlingDuration: TimeInterval = 0.32
    static let maximumLead: TimeInterval = 0.18
    mutating func ingest(_ text: String, at now: TimeInterval, animated: Bool) {
        let incoming = Array(text)
        var common = 0
        while common < min(incoming.count, glyphs.count), incoming[common] == glyphs[common].character { common += 1 }
        if common < glyphs.count { glyphs.removeSubrange(common...) }
        glyphs.append(contentsOf: incoming.dropFirst(common).map { Glyph(character: $0, birth: now) })
        guard animated else { revealImmediately(at: now); return }
        // Preserve visible glyphs; rebalance only the unrevealed tail to bound visual latency.
        let pendingStart = min(common, glyphs.firstIndex(where: { $0.birth > now }) ?? common)
        guard pendingStart < glyphs.count else { return }
        let count = glyphs.count - pendingStart
        let step = min(1.0 / 75.0, Self.maximumLead / Double(max(1, count)))
        for index in pendingStart..<glyphs.count { glyphs[index].birth = now + Double(index - pendingStart) * step }
    }
    mutating func revealImmediately(at now: TimeInterval) {
        for index in glyphs.indices { glyphs[index].birth = now - Self.settlingDuration - 1 }
    }
    func visibleCount(at now: TimeInterval) -> Int {
        var low = 0, high = glyphs.count
        while low < high { let middle = (low + high) / 2; if glyphs[middle].birth <= now { low = middle + 1 } else { high = middle } }
        return low
    }
    func settledCount(at now: TimeInterval) -> Int {
        var low = 0, high = glyphs.count
        while low < high { let middle = (low + high) / 2; if glyphs[middle].birth + Self.settlingDuration <= now { low = middle + 1 } else { high = middle } }
        return low
    }
    func isSettled(at now: TimeInterval) -> Bool {
        guard let last = glyphs.last else { return true }
        return now >= last.birth + Self.settlingDuration
    }
    var plainText: String { String(glyphs.map(\.character)) }
}
