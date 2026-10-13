import Foundation

struct RGB: Codable, Hashable {
    var r: Double; var g: Double; var b: Double
    static let defaults = [RGB(r: 0.26, g: 0.28, b: 0.48), RGB(r: 0.18, g: 0.42, b: 0.49), RGB(r: 0.44, g: 0.25, b: 0.39)]
}

enum Rarity: String, Codable, CaseIterable, Identifiable {
    case original, rare, epic, legendary
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .original: "circle"; case .rare: "sparkle"; case .epic: "diamond"; case .legendary: "crown" }
    }
}

struct TradeStamp: Codable, Hashable, Identifiable {
    var id: UUID
    var from: UUID
    var to: UUID
    var date: Date
}

struct CollectorCard: Codable, Identifiable, Hashable {
    var id: UUID
    var editionID: UUID
    var title: String
    var creator: UUID
    var owner: UUID
    var serial: Int
    var editionSize: Int
    var rarity: Rarity
    var created: Date
    var palette: [RGB]
    var depthAmount: Double
    var imageHash: String
    var depthHash: String?
    var history: [TradeStamp]
    var stamp: String { "\(serial) OF \(editionSize)" }
    var mediaKey: String { editionID.uuidString }
    func validate() throws {
        guard (1...1000).contains(editionSize), (1...editionSize).contains(serial),
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 80,
              depthAmount.isFinite, (0...1).contains(depthAmount),
              palette.count == 3, palette.allSatisfy({ c in [c.r,c.g,c.b].allSatisfy { $0.isFinite && (0...1).contains($0) } }),
              imageHash.count == 64, depthHash == nil || depthHash?.count == 64,
              history.count <= 1000 else { throw CollectrError.message("This card has an invalid edition stamp.") }
        var expected = creator
        var seen = Set<UUID>()
        for stamp in history {
            guard stamp.from == expected, stamp.from != stamp.to, seen.insert(stamp.id).inserted else {
                throw CollectrError.message("This card's ownership history is incomplete.")
            }
            expected = stamp.to
        }
        guard owner == expected else { throw CollectrError.message("The card's owner does not match its history.") }
    }
}

struct CardPayload: Codable {
    var card: CollectorCard
    var photo: Data
    var depth: Data?
}

enum TransferPhase: String, Codable { case offered, staged, committed, received, finished, declined }
struct Transfer: Codable, Identifiable {
    var id: UUID
    var peer: UUID
    var card: CollectorCard
    var phase: TransferPhase
    var incoming: Bool
    var date: Date
}
struct DraftRecord: Codable {
    var editionID: UUID
    var title: String
    var rarity: Rarity
    var count: Int
    var depthAmount: Double
    var palette: [RGB]
    var imageHash: String
    var depthHash: String?
    var sourceIdentifier: String
    var deletionConfirmed: Bool
}
struct CollectionDatabase: Codable {
    var version = 1
    var identity = UUID()
    var cards: [CollectorCard] = []
    var transfers: [Transfer] = []
    var draft: DraftRecord?
}

enum CollectrError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
// Interfaces retained from Depth Check's verified DA3 pipeline.
enum DepthModelChoice { case balanced, detailed; var title: String { "Depth Anything 3 Base" } }
typealias DepthCheckError = CollectrError
struct DepthMap { var width: Int; var height: Int; var values: [Float] }
