import Foundation

/// Presentation timing only: this never alters model output or delays inference.
struct RevealSchedule: Equatable {
    private(set) var characters: [Character] = []
    private(set) var arrivals: [TimeInterval] = []
    static let maximumLead: TimeInterval = 0.18
    static let settleDuration: TimeInterval = 0.34
    var text: String { String(characters) }
    var completion: TimeInterval { (arrivals.last ?? -.infinity) + Self.settleDuration }

    mutating func ingest(_ snapshot: String, now: TimeInterval, animate: Bool) {
        let incoming = Array(snapshot)
        guard animate else {
            characters = incoming
            arrivals = Array(repeating: now - 1, count: incoming.count)
            return
        }
        var common = 0
        while common < min(characters.count, incoming.count), characters[common] == incoming[common] { common += 1 }
        arrivals = Array(arrivals.prefix(common))
        characters = incoming
        let newCount = incoming.count - common
        guard newCount > 0 else { return }
        // Keep completed letters fixed. Compress only the unrevealed queue if a
        // backend delivers a large burst, with a hard 180 ms presentation lead.
        let pendingStart = arrivals.firstIndex(where: { $0 > now }) ?? common
        let pendingCount = incoming.count - pendingStart
        let step = min(0.011, Self.maximumLead / Double(max(1, pendingCount)))
        arrivals = Array(arrivals.prefix(pendingStart))
        for index in 0..<pendingCount { arrivals.append(now + Double(index) * step) }
    }
    mutating func finishImmediately(now: TimeInterval) {
        arrivals = Array(repeating: now - 1, count: characters.count)
    }
}
