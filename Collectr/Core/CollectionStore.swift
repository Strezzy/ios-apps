import SwiftUI
import CryptoKit
import UIKit
import ImageIO

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var database: CollectionDatabase
    @Published var error: String?
    let root: URL
    private let thumbnails = NSCache<NSString, UIImage>()
    var identity: UUID { database.identity }
    var cards: [CollectorCard] { database.cards }
    var groups: [[CollectorCard]] {
        Dictionary(grouping: cards, by: \.editionID).values.map { $0.sorted { $0.serial < $1.serial } }
            .sorted { $0[0].created > $1[0].created }
    }
    var transfers: [Transfer] { database.transfers }
    var draft: DraftRecord? { database.draft }

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Collectr", isDirectory: true)
        database = CollectionDatabase()
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            let url = self.root.appendingPathComponent("collection.json")
            if FileManager.default.fileExists(atPath: url.path) {
                database = try JSONDecoder().decode(CollectionDatabase.self, from: Data(contentsOf: url))
                guard database.version == 1 else { throw CollectrError.message("This collection needs a newer version of Collectr.") }
                try database.cards.forEach { try $0.validate() }
            } else { try persist(database) }
        } catch { self.error = "Your collection could not be opened. Its files have been kept safe. \(error.localizedDescription)" }
    }

    private func persist(_ value: CollectionDatabase) throws {
        let bytes = try JSONEncoder().encode(value)
        try bytes.write(to: root.appendingPathComponent("collection.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func change(_ edit: (inout CollectionDatabase) throws -> Void) throws {
        guard error == nil else { throw CollectrError.message(error!) }
        var next = database
        try edit(&next)
        try persist(next)
        database = next
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func mediaURL(_ edition: UUID, depth: Bool = false) -> URL {
        root.appendingPathComponent(edition.uuidString, isDirectory: true).appendingPathComponent(depth ? "depth.png" : "photo.jpg")
    }
    func image(_ card: CollectorCard, thumbnail: Bool = false) -> UIImage? {
        let key = card.mediaKey as NSString
        if thumbnail, let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(mediaURL(card.editionID) as CFURL, nil) else { return nil }
        let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: thumbnail ? 560 : 2200, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts) else { return nil }
        let image = UIImage(cgImage: cg)
        if thumbnail { thumbnails.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height) }
        return image
    }
    func depthImage(_ edition: UUID) -> UIImage? { UIImage(contentsOfFile: mediaURL(edition, depth: true).path) }
    private func writeMedia(_ edition: UUID, photo: Data, depth: Data?) throws {
        let directory = root.appendingPathComponent(edition.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let photoURL = mediaURL(edition)
        if FileManager.default.fileExists(atPath: photoURL.path) {
            guard Self.hash(try Data(contentsOf: photoURL)) == Self.hash(photo) else { throw CollectrError.message("This edition's image does not match the saved original.") }
        } else { try photo.write(to: photoURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        if let depth {
            let depthURL = mediaURL(edition, depth: true)
            if FileManager.default.fileExists(atPath: depthURL.path) {
                guard Self.hash(try Data(contentsOf: depthURL)) == Self.hash(depth) else { throw CollectrError.message("This edition’s depth does not match its saved original.") }
            } else { try depth.write(to: depthURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
    }
    func saveDraft(_ draft: DraftRecord, photo: Data, depth: Data?) throws {
        guard (1...1000).contains(draft.count), !draft.title.isEmpty, draft.title.count <= 80, draft.depthAmount.isFinite, (0...1).contains(draft.depthAmount), draft.palette.count == 3, Self.hash(photo) == draft.imageHash, depth.map(Self.hash) == draft.depthHash else { throw CollectrError.message("This draft has an invalid edition or image.") }
        try writeMedia(draft.editionID, photo: photo, depth: depth)
        try change { $0.draft = draft }
    }
    func confirmDeletion() throws { try change { $0.draft?.deletionConfirmed = true } }
    func finalizeDraft() throws -> CollectorCard {
        guard let draft, draft.deletionConfirmed else { throw CollectrError.message("Remove the original from Photos before sealing this edition.") }
        guard Self.hash(try Data(contentsOf: mediaURL(draft.editionID))) == draft.imageHash else { throw CollectrError.message("The saved card could not be verified. Your draft has been kept.") }
        guard (1...1000).contains(draft.count) else { throw CollectrError.message("The edition size is invalid.") }
        var minted: [CollectorCard] = []
        for serial in 1...draft.count {
            let card = CollectorCard(id: UUID(), editionID: draft.editionID, title: draft.title, creator: identity, owner: identity, serial: serial, editionSize: draft.count, rarity: draft.rarity, created: Date(), palette: draft.palette, depthAmount: draft.depthAmount, imageHash: draft.imageHash, depthHash: draft.depthHash, history: [])
            try card.validate(); minted.append(card)
        }
        try change { $0.cards += minted; $0.draft = nil }
        return minted[0]
    }
    func discardDraft() throws { try change { $0.draft = nil } }
    func isLocked(_ card: CollectorCard) -> Bool {
        transfers.contains { !$0.incoming && $0.card.id == card.id && [.offered, .committed].contains($0.phase) }
    }
    func payload(_ card: CollectorCard) throws -> CardPayload {
        CardPayload(card: card, photo: try Data(contentsOf: mediaURL(card.editionID)), depth: card.depthHash == nil ? nil : try Data(contentsOf: mediaURL(card.editionID, depth: true)))
    }
    func offer(_ card: CollectorCard, to peer: UUID) throws -> Transfer {
        guard cards.contains(where: { $0.id == card.id }), card.owner == identity, peer != identity, !isLocked(card), card.history.count < 1000 else { throw CollectrError.message("This copy is already in a trade.") }
        let transfer = Transfer(id: UUID(), peer: peer, card: card, phase: .offered, incoming: false, date: Date())
        try change { $0.transfers.insert(transfer, at: 0) }; return transfer
    }
    static func validatePayload(_ payload: CardPayload) throws {
        try payload.card.validate()
        guard payload.photo.count <= 12_000_000, Self.hash(payload.photo) == payload.card.imageHash,
              let source = CGImageSourceCreateWithData(payload.photo as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 3000, h <= 3000 else { throw CollectrError.message("The card image failed verification.") }
        if let depth = payload.depth {
            guard depth.count <= 2_000_000, Self.hash(depth) == payload.card.depthHash,
                  let src = CGImageSourceCreateWithData(depth as CFData, nil),
                  let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let width = p[kCGImagePropertyPixelWidth] as? Int, let height = p[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 504, height <= 504 else { throw CollectrError.message("The depth image failed verification.") }
        } else if payload.card.depthHash != nil { throw CollectrError.message("This card is missing its depth image.") }
    }
    func stage(_ payload: CardPayload, id: UUID, from peer: UUID) throws {
        try Self.validatePayload(payload)
        guard payload.card.owner == peer, peer != identity, !cards.contains(where: { $0.id == payload.card.id || ($0.editionID == payload.card.editionID && $0.serial == payload.card.serial) }) else { throw CollectrError.message("This copy is already in your collection, or its sender does not own it.") }
        if let old = transfers.first(where: { $0.id == id }) {
            guard old.incoming, old.peer == peer, old.card == payload.card else { throw CollectrError.message("Trade identity mismatch.") }; return
        }
        guard !transfers.contains(where: { $0.incoming && [.offered, .staged].contains($0.phase) && ($0.card.id == payload.card.id || ($0.card.editionID == payload.card.editionID && $0.card.serial == payload.card.serial)) }) else { throw CollectrError.message("This numbered copy already has an incoming offer.") }
        if let existing = cards.first(where: { $0.editionID == payload.card.editionID }) ?? transfers.first(where: { $0.card.editionID == payload.card.editionID })?.card {
            guard existing.title == payload.card.title, existing.created == payload.card.created, existing.palette == payload.card.palette, existing.creator == payload.card.creator, existing.editionSize == payload.card.editionSize, existing.imageHash == payload.card.imageHash, existing.depthHash == payload.card.depthHash, existing.rarity == payload.card.rarity, existing.depthAmount == payload.card.depthAmount else { throw CollectrError.message("The edition does not match its existing copies.") }
        }
        try writeMedia(payload.card.editionID, photo: payload.photo, depth: payload.depth)
        try change { $0.transfers.insert(Transfer(id: id, peer: peer, card: payload.card, phase: .offered, incoming: true, date: Date()), at: 0) }
    }
    func accept(_ id: UUID) throws {
        try change { db in
            guard let i = db.transfers.firstIndex(where: { $0.id == id && $0.incoming && $0.phase == .offered }) else { return }
            db.transfers[i].phase = .staged
        }
    }
    // The sender durably removes ownership BEFORE a commit can be transmitted.
    // A lost connection leaves a retryable outbox entry, never a second owned copy.
    func commitOutgoing(_ id: UUID, peer: UUID) throws {
        try change { db in
            guard let i = db.transfers.firstIndex(where: { $0.id == id && !$0.incoming && $0.peer == peer }) else { throw CollectrError.message("Unknown outgoing trade.") }
            if [.committed, .finished].contains(db.transfers[i].phase) { return }
            guard db.transfers[i].phase == .offered, db.cards.contains(where: { $0.id == db.transfers[i].card.id }) else { throw CollectrError.message("This trade was cancelled.") }
            db.cards.removeAll { $0.id == db.transfers[i].card.id }; db.transfers[i].phase = .committed
        }
    }
    func receiveCommit(_ id: UUID, peer: UUID) throws {
        try change { db in
            guard let i = db.transfers.firstIndex(where: { $0.id == id && $0.incoming && $0.peer == peer }) else { throw CollectrError.message("Unknown incoming trade.") }
            if db.transfers[i].phase == .received { return }
            guard db.transfers[i].phase == .staged else { throw CollectrError.message("Accept this card before receiving it.") }
            var card = db.transfers[i].card
            card.history.append(TradeStamp(id: id, from: peer, to: db.identity, date: db.transfers[i].date))
            card.owner = db.identity; try card.validate()
            guard !db.cards.contains(where: { $0.id == card.id || ($0.editionID == card.editionID && $0.serial == card.serial) }) else { throw CollectrError.message("This copy is already owned.") }
            db.cards.append(card); db.transfers[i].phase = .received
        }
    }
    func acknowledge(_ id: UUID, peer: UUID) throws {
        try change { db in
            if let i = db.transfers.firstIndex(where: { $0.id == id && !$0.incoming && $0.peer == peer && $0.phase == .committed }) { db.transfers[i].phase = .finished }
        }
    }
    func cancelFromPeer(_ id: UUID, peer: UUID) throws {
        try change { db in
            if let i = db.transfers.firstIndex(where: { $0.id == id && $0.peer == peer }),
               db.transfers[i].phase == .offered || (db.transfers[i].incoming && db.transfers[i].phase == .staged) { db.transfers[i].phase = .declined }
        }
    }
    func decline(_ id: UUID) throws {
        try change { db in
            if let i = db.transfers.firstIndex(where: { $0.id == id && $0.phase == .offered }) { db.transfers[i].phase = .declined }
        }
    }
}
