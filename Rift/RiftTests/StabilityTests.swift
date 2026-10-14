import XCTest
@testable import Rift

final class StabilityTests: XCTestCase {
    func testCreatingInferenceServiceDoesNotInitializeBackend() {
        let before = RiftBackendInitializationCount()
        let service = InferenceService()
        XCTAssertEqual(RiftBackendInitializationCount(), before)
        service.unload()
    }
    @MainActor func testAppModelConstructionDoesNotInitializeBackend() {
        let before = RiftBackendInitializationCount()
        let app = AppModel()
        XCTAssertFalse(app.ready)
        XCTAssertEqual(RiftBackendInitializationCount(), before)
    }
    func test4BUsesReducedContextInsteadOfFixedFourGigabyteThreshold() throws {
        let plan = try XCTUnwrap(MemoryBudget.plan(bytes: 2_707_513_696, requested: 4096, available: 3_260_000_000, architecture: "qwen35"))
        XCTAssertLessThan(plan.context, 4096)
        XCTAssertTrue(plan.reduced)
        XCTAssertLessThanOrEqual(plan.required + MemoryBudget.headroom, 3_260_000_000)
    }
    func testInsufficientAllowanceStillBlocksInsteadOfKillingApp() {
        XCTAssertNil(MemoryBudget.plan(bytes: 5_627_044_224, requested: 2048, available: 3_300_000_000, architecture: "qwen35"))
        XCTAssertNil(MemoryBudget.plan(bytes: 2_707_513_696, requested: 2048, available: 0, architecture: "qwen35"))
    }
    func testContextCanGoDownTo512() throws {
        let need = MemoryBudget.required(bytes: 2_707_513_696, context: 512, architecture: "qwen35")
        let plan = try XCTUnwrap(MemoryBudget.plan(bytes: 2_707_513_696, requested: 2048, available: need + MemoryBudget.headroom + 1, architecture: "qwen35"))
        XCTAssertEqual(plan.context, 512)
    }
    func testMetadataChangesEstimatedKVCacheRatherThanMarketingRAM() {
        let small = MemoryBudget.required(bytes: 2_700_000_000, context: 2048, architecture: "qwen35", dimensions: ["block_count":32,"attention.head_count_kv":2,"attention.key_length":128])
        let large = MemoryBudget.required(bytes: 2_700_000_000, context: 2048, architecture: "qwen35", dimensions: ["block_count":32,"attention.head_count_kv":8,"attention.key_length":256])
        XCTAssertLessThan(small, large)
    }
    func testOldFailureMessagesDoNotPoisonNextPrompt() {
        let old = ChatMessage(role: "assistant", content: "No reply was generated. Try again or choose another model.", interrupted: true)
        XCTAssertFalse(old.canSendToModel)
        let current = ChatMessage(role: "assistant", content: "", failureDescription: "Memory is unavailable")
        XCTAssertFalse(current.canSendToModel)
        XCTAssertTrue(ChatMessage(role: "user", content: "Hello").canSendToModel)
    }
    func testOldConversationDecodesWithoutNewErrorField() throws {
        let message = ChatMessage(role: "user", content: "Preserve this conversation")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String:Any])
        json.removeValue(forKey: "failureDescription")
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.content, message.content)
        XCTAssertNil(decoded.failureDescription)
    }
    func testHereticSizesAndTwo14BQuantizationsAreVisibleFor18Pro() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "catalog", withExtension: "json"))
        let catalog = try JSONDecoder().decode([CatalogModel].self, from: Data(contentsOf: url))
        let phone = try XCTUnwrap(DeviceProfile.profiles.first { $0.id == "18pro" })
        let heretic = phone.models(from: catalog).filter { $0.libraryGroup == "Heretic" }
        XCTAssertTrue(heretic.contains { $0.id == "heretic-qwen3-8b" })
        XCTAssertTrue(heretic.contains { $0.id == "heretic-qwen35-9b" })
        XCTAssertEqual(heretic.filter { $0.name.contains("14B") }.count, 2)
        XCTAssertEqual(DeviceProfile.featured(heretic).count, 2)
        XCTAssertTrue(DeviceProfile.featured(heretic).contains { $0.name.contains("14B") })
        XCTAssertTrue(heretic.allSatisfy { $0.uncensored })
    }
    func testHashBufferIsBoundedIndependentlyOfModelSize() {
        XCTAssertLessThanOrEqual(GGUFInspector.hashBufferBytes, 1_048_576)
    }
    func testSixGiBHashUsesBoundedMemory() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(6) * 1024 * 1024 * 1024); try handle.close()
        let baseline = RiftMemoryFootprint()
        let peak = MemoryPeak()
        let hash = try await Task.detached { try GGUFInspector.hash(url) { _ in peak.sample() } }.value
        XCTAssertEqual(hash, "5c32c2b28999325bc5ad39d6530bcb46fbdf1f86375a991b7269764c50b0d109")
        let growth = peak.value > baseline ? peak.value - baseline : 0
        XCTAssertLessThan(growth, 96 * 1_048_576, "Large-file hashing must not retain model-sized temporary data")
        let report = XCTAttachment(string: "6 GiB SHA-256 verified; peak incremental footprint: \(growth) bytes")
        report.lifetime = .keepAlways; add(report)
    }
}
private final class MemoryPeak: @unchecked Sendable {
    private let lock = NSLock()
    private var highest: UInt64 = 0
    func sample() { let amount=RiftMemoryFootprint(); lock.lock(); highest=max(highest,amount); lock.unlock() }
    var value: UInt64 { lock.lock(); defer { lock.unlock() }; return highest }
}
