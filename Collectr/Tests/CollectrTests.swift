import XCTest
import UIKit
import CoreImage
import Metal
@testable import Collectr

@MainActor
final class CollectrTests: XCTestCase {
    private func fresh() throws -> CollectionStore {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: path) }
        return CollectionStore(root: path)
    }
    private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 100,height: 140)).image { ctx in
            UIColor.cyan.setFill(); ctx.fill(CGRect(x: 0,y: 0,width: 100,height: 140))
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 30,y: 50,width: 40,height: 80))
        }.jpegData(compressionQuality: 0.95)!
    }
    @discardableResult private func mint(_ store: CollectionStore,count: Int = 3) throws -> CollectorCard {
        let bytes = photo()
        try store.saveDraft(DraftRecord(editionID: UUID(),title: "A moment",rarity: .rare,count: count,depthAmount: 0,palette: RGB.defaults,imageHash: CollectionStore.hash(bytes),depthHash: nil,sourceIdentifier: "test-original",deletionConfirmed: false),photo: bytes,depth: nil)
        XCTAssertThrowsError(try store.finalizeDraft())
        try store.confirmDeletion(); return try store.finalizeDraft()
    }
    func testEditionCapAndDeletionGatePersist() throws {
        let store = try fresh(); let card = try mint(store)
        XCTAssertEqual(store.cards.map(\.serial),[1,2,3]); XCTAssertEqual(Set(store.cards.map(\.editionID)).count,1)
        XCTAssertEqual(card.stamp,"1 OF 3"); XCTAssertNil(store.draft)
        let restored = CollectionStore(root: store.root)
        XCTAssertEqual(restored.cards,store.cards); XCTAssertEqual(restored.identity,store.identity)
    }
    func testInvalidDraftDoesNotDeleteOrMint() throws {
        let store = try fresh(); let bytes = photo()
        let draft = DraftRecord(editionID: UUID(),title: "Bad cap",rarity: .rare,count: 0,depthAmount: 0,palette: RGB.defaults,imageHash: CollectionStore.hash(bytes),depthHash: nil,sourceIdentifier: "test",deletionConfirmed: false)
        XCTAssertThrowsError(try store.saveDraft(draft,photo: bytes,depth: nil)); XCTAssertTrue(store.cards.isEmpty); XCTAssertNil(store.draft)
    }
    func testDraftSurvivesRestartBeforeDeletion() throws {
        let store = try fresh(); let bytes = photo()
        try store.saveDraft(DraftRecord(editionID: UUID(),title: "Saved",rarity: .original,count: 1,depthAmount: 0,palette: RGB.defaults,imageHash: CollectionStore.hash(bytes),depthHash: nil,sourceIdentifier: "test",deletionConfirmed: false),photo: bytes,depth: nil)
        let restored = CollectionStore(root: store.root)
        XCTAssertNotNil(restored.draft); XCTAssertThrowsError(try restored.finalizeDraft())
        try restored.confirmDeletion(); _ = try restored.finalizeDraft(); XCTAssertEqual(restored.cards.count,1)
    }
    func testTradeCrashRecoveryAndReplayNeverDuplicateOwnership() throws {
        let sender = try fresh(), receiver = try fresh(); let card = try mint(sender)
        let transfer = try sender.offer(card,to: receiver.identity)
        try receiver.stage(sender.payload(card),id: transfer.id,from: sender.identity)
        XCTAssertTrue(sender.isLocked(card)); XCTAssertTrue(receiver.cards.isEmpty)
        try receiver.accept(transfer.id); try sender.commitOutgoing(transfer.id,peer: receiver.identity)
        XCTAssertFalse(sender.cards.contains { $0.id == card.id }); XCTAssertTrue(receiver.cards.isEmpty)
        let restartedSender = CollectionStore(root: sender.root), restartedReceiver = CollectionStore(root: receiver.root)
        XCTAssertEqual(restartedSender.transfers[0].phase,.committed)
        try restartedReceiver.receiveCommit(transfer.id,peer: sender.identity)
        try restartedReceiver.receiveCommit(transfer.id,peer: sender.identity)
        try restartedSender.acknowledge(transfer.id,peer: receiver.identity)
        XCTAssertEqual(restartedReceiver.cards.count,1); XCTAssertEqual(restartedSender.cards.count,2)
        let received = restartedReceiver.cards[0]
        XCTAssertEqual(received.serial,card.serial); XCTAssertEqual(received.editionSize,card.editionSize)
        XCTAssertEqual(received.history.count,1); XCTAssertEqual(received.owner,receiver.identity); try received.validate()
        XCTAssertThrowsError(try restartedReceiver.stage(sender.payload(card),id: UUID(),from: sender.identity))
    }
    func testCancelledOfferUnlocksSenderAndCannotCommit() throws {
        let sender = try fresh(), receiver = try fresh(); let card = try mint(sender)
        let t = try sender.offer(card,to: receiver.identity)
        try sender.decline(t.id)
        XCTAssertFalse(sender.isLocked(card)); XCTAssertEqual(sender.cards.count,3)
        XCTAssertThrowsError(try sender.commitOutgoing(t.id,peer: receiver.identity))
    }
    func testRecipientMustAcceptAndCannotCancelAfterCommit() throws {
        let sender = try fresh(), receiver = try fresh(); let card = try mint(sender)
        let t = try sender.offer(card,to: receiver.identity)
        try receiver.stage(sender.payload(card),id: t.id,from: sender.identity)
        XCTAssertThrowsError(try receiver.receiveCommit(t.id,peer: sender.identity))
        try receiver.accept(t.id); try sender.commitOutgoing(t.id,peer: receiver.identity)
        try sender.decline(t.id); XCTAssertEqual(sender.transfers[0].phase,.committed)
        try receiver.receiveCommit(t.id,peer: sender.identity)
        try receiver.cancelFromPeer(t.id,peer: sender.identity); XCTAssertEqual(receiver.cards.count,1)
    }
    func testTamperedImageAndEditionRejected() throws {
        let sender = try fresh(), receiver = try fresh(); let card = try mint(sender)
        var payload = try sender.payload(card); payload.photo.append(0)
        XCTAssertThrowsError(try receiver.stage(payload,id: UUID(),from: sender.identity))
        payload = try sender.payload(card); payload.card.serial = 4
        XCTAssertThrowsError(try receiver.stage(payload,id: UUID(),from: sender.identity))
        payload = try sender.payload(card); payload.card.owner = UUID()
        XCTAssertThrowsError(try receiver.stage(payload,id: UUID(),from: sender.identity))
    }
    func testDepthNormalizationHandlesDA3Distance() throws {
        let result = try DepthNormalization().normalize([1,2,4,8],isInverseDepth: false,luma: [],temporal: false)
        XCTAssertGreaterThan(result[0],result[3]); XCTAssertTrue(result.allSatisfy { (0...1).contains($0) })
    }
    func testPhotoCropPaletteAndMetalShader() throws {
        let image = try PhotoPipeline().render(photo(),edits: PhotoEdits())
        XCTAssertEqual(image.size.width/image.size.height,5.0/7.0,accuracy: 0.01)
        let palette = PhotoPipeline.palette(image); XCTAssertEqual(palette.count,3)
        XCTAssertTrue(palette.contains { $0.g > 0.4 })
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        XCTAssertNotNil(library.makeFunction(name: "cardVertex")); XCTAssertNotNil(library.makeFunction(name: "cardFragment"))
    }
    func testBundledDA3ProducesFiniteDepth() async throws {
        let image = try PhotoPipeline().render(photo(),edits: PhotoEdits())
        let depth = try await PhotoPipeline().depth(image)
        XCTAssertGreaterThan(depth.size.width,0); XCTAssertGreaterThan(depth.size.height,0)
        XCTAssertLessThanOrEqual(depth.size.width,504); XCTAssertNotNil(depth.pngData())
    }
}
