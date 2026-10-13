import XCTest
import UIKit
import CoreImage
import MetalKit
import ImageIO
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
    func testDuplicateIncomingSerialIsReserved() throws {
        let sender = try fresh(), receiver = try fresh(); let card = try mint(sender)
        let payload = try sender.payload(card), id = UUID()
        try receiver.stage(payload,id: id,from: sender.identity)
        try receiver.stage(payload,id: id,from: sender.identity)
        XCTAssertThrowsError(try receiver.stage(payload,id: UUID(),from: sender.identity))
        var altered = payload; altered.card.id = UUID()
        XCTAssertThrowsError(try receiver.stage(altered,id: UUID(),from: sender.identity))
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
    func testMetalDepthActuallyMovesPhotoAndFlatCardsStayStill() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "cardVertex")
        desc.fragmentFunction = library.makeFunction(name: "cardFragment")
        desc.colorAttachments[0].pixelFormat = .rgba8Unorm
        let pipeline = try device.makeRenderPipelineState(descriptor: desc)
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,width: 96,height: 96,mipmapped: false)
        textureDesc.storageMode = .shared; textureDesc.usage = [.shaderRead,.renderTarget]
        let source = try XCTUnwrap(device.makeTexture(descriptor: textureDesc))
        let depth = try XCTUnwrap(device.makeTexture(descriptor: textureDesc))
        var pixels = [UInt8](repeating: 255,count: 96*96*4)
        var depths = pixels
        for y in 0..<96 { for x in 0..<96 {
            let i = (y*96+x)*4
            pixels[i] = UInt8(x*255/95); pixels[i+1] = UInt8(y*255/95); pixels[i+2] = UInt8((x/8+y/8)%2*255)
            depths[i] = UInt8(x<48 ? 240 : 30)
        } }
        pixels.withUnsafeBytes { source.replace(region: MTLRegionMake2D(0,0,96,96),mipmapLevel: 0,withBytes: $0.baseAddress!,bytesPerRow: 96*4) }
        depths.withUnsafeBytes { depth.replace(region: MTLRegionMake2D(0,0,96,96),mipmapLevel: 0,withBytes: $0.baseAddress!,bytesPerRow: 96*4) }
        func render(_ tilt: SIMD2<Float>,amount: Float,hasDepth: Float) throws -> [UInt8] {
            let target = try XCTUnwrap(device.makeTexture(descriptor: textureDesc))
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            let command = try XCTUnwrap(device.makeCommandQueue()?.makeCommandBuffer())
            let enc = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
            var u = DepthPhoto.Renderer.Uniforms(tilt: tilt,amount: amount,hasDepth: hasDepth)
            enc.setRenderPipelineState(pipeline); enc.setFragmentTexture(source,index: 0); enc.setFragmentTexture(depth,index: 1)
            enc.setFragmentBytes(&u,length: MemoryLayout<DepthPhoto.Renderer.Uniforms>.stride,index: 0)
            enc.drawPrimitives(type: .triangleStrip,vertexStart: 0,vertexCount: 4); enc.endEncoding()
            command.commit(); command.waitUntilCompleted(); XCTAssertNil(command.error)
            var result = [UInt8](repeating: 0,count: pixels.count)
            result.withUnsafeMutableBytes { target.getBytes($0.baseAddress!,bytesPerRow: 96*4,from: MTLRegionMake2D(0,0,96,96),mipmapLevel: 0) }
            return result
        }
        let centered = try render(.zero,amount: 1,hasDepth: 1)
        let tilted = try render(SIMD2(1,0.5),amount: 1,hasDepth: 1)
        XCTAssertNotEqual(centered,tilted)
        XCTAssertEqual(try render(.zero,amount: 1,hasDepth: 0),try render(SIMD2(1,1),amount: 1,hasDepth: 0))
        XCTAssertEqual(try render(.zero,amount: 0,hasDepth: 1),try render(SIMD2(1,1),amount: 0,hasDepth: 1))
    }
    func testReloadedJPEGTextureKeepsColorsAndOrientation() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let bytes = photo()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData,nil))
        let cg = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true,kCGImageSourceThumbnailMaxPixelSize: 2200,kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary))
        let renderer = DepthPhoto.Renderer()
        let view = MTKView(frame: CGRect(x: 0,y: 0,width: 100,height: 140),device: device)
        try renderer.configure(view)
        try renderer.update(image: UIImage(cgImage: cg),depth: nil,tilt: .zero,amount: 0)
        let texture = try XCTUnwrap(renderer.photo)
        XCTAssertEqual(texture.pixelFormat,.rgba8Unorm)
        func pixel(_ x: Int,_ y: Int) -> [UInt8] {
            var p = [UInt8](repeating: 0,count: 4)
            p.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow: 4,from: MTLRegionMake2D(x,y,1,1),mipmapLevel: 0) }
            return p
        }
        let top = pixel(texture.width/2,texture.height/14), bottom = pixel(texture.width/2,texture.height*11/14)
        XCTAssertLessThan(top[0],25); XCTAssertGreaterThan(top[1],220); XCTAssertGreaterThan(top[2],220)
        XCTAssertGreaterThan(bottom[0],220); XCTAssertGreaterThan(bottom[1],90); XCTAssertLessThan(bottom[1],180); XCTAssertLessThan(bottom[2],25)
    }
    func testBundledDA3ProducesFiniteDepth() async throws {
        let image = try PhotoPipeline().render(photo(),edits: PhotoEdits())
        let depth = try await PhotoPipeline().depth(image)
        XCTAssertGreaterThan(depth.size.width,0); XCTAssertGreaterThan(depth.size.height,0)
        XCTAssertLessThanOrEqual(depth.size.width,504); XCTAssertNotNil(depth.pngData())
    }
}
