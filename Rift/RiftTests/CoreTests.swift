import XCTest
@testable import Rift

final class CoreTests: XCTestCase {
    func testDeviceLabelsDoNotConfuse17And18() {
        XCTAssertEqual(DeviceProfile.profileID(machine:"iPhone18,1"),"17pro")
        XCTAssertEqual(DeviceProfile.profileID(machine:"iPhone19,2"),"18pro")
        XCTAssertEqual(DeviceProfile.profileID(machine:"iPhone19,3"),"18promax")
        XCTAssertNil(DeviceProfile.profileID(machine:"iPhone99,1"))
    }
    func testPhone18ProfilesArePresent() {
        XCTAssertTrue(DeviceProfile.profiles.contains {$0.name == "iPhone 18 Pro"})
        XCTAssertTrue(DeviceProfile.profiles.contains {$0.name == "iPhone 18 Pro Max"})
    }
    func testMemoryBudgetKeepsHeadroom() {
        XCTAssertFalse(MemoryBudget.fits(required:1_000_000_000,available:1_100_000_000))
        XCTAssertFalse(MemoryBudget.fits(required:0,available:0))
        XCTAssertTrue(MemoryBudget.fits(required:1_000_000_000,available:2_000_000_000))
    }
    func testContextIncreasesMemoryEstimate() {
        XCTAssertGreaterThan(MemoryBudget.required(bytes:2_000_000_000,context:8192,workingGB:nil),MemoryBudget.required(bytes:2_000_000_000,context:2048,workingGB:nil))
    }
    func testUncensoredCatalogIsPinnedAndSmall() throws {
        let url=try XCTUnwrap(Bundle.main.url(forResource:"catalog",withExtension:"json"))
        let models=try JSONDecoder().decode([CatalogModel].self,from:Data(contentsOf:url))
        XCTAssertGreaterThanOrEqual(models.count,3); XCTAssertLessThanOrEqual(models.count,6)
        XCTAssertEqual(Set(models.map(\.id)).count,models.count)
        for model in models {
            XCTAssertTrue(model.uncensored)
            XCTAssertTrue(model.repo.lowercased().contains("uncensored"))
            XCTAssertEqual(model.sha256.count,64); XCTAssertEqual(model.revision.count,40)
            XCTAssertTrue(model.downloadURL.absoluteString.contains(model.revision))
            XCTAssertGreaterThan(model.bytes,10_000_000)
            XCTAssertFalse(model.badge.isEmpty)
        }
        for phone in DeviceProfile.profiles {
            let list=phone.models(from:models)
            for family in ["Qwen","Gemma","Liquid"] { XCTAssertLessThanOrEqual(list.filter {$0.family==family}.count,2) }
            XCTAssertTrue(list.allSatisfy {$0.minimumRAM <= phone.ram})
        }
    }
    func testReasoningIsKeptSeparate() {
        XCTAssertEqual(ReplyParts.parse("<think>reason</think>answer"),.init(thought:"reason",answer:"answer"))
        XCTAssertEqual(ReplyParts.parse("<think>partial"),.init(thought:"partial",answer:""))
        XCTAssertEqual(ReplyParts.parse("Hello 🌸"),.init(thought:"",answer:"Hello 🌸"))
    }
    func testTranscriptExportPreservesUnicode() {
        let chat=Conversation(messages:[.init(role:"user",content:"Hello 日本語"),.init(role:"assistant",content:"🌸 Reply")])
        XCTAssertTrue(chat.transcript.contains("Hello 日本語")); XCTAssertTrue(chat.transcript.contains("🌸 Reply"))
    }
    func testAtomicConversationRoundTrip() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let storage=try LocalStorage(root:root)
        let chats=[Conversation(title:"A test",messages:[.init(role:"user",content:"Private text")])]
        try storage.write(chats,name:"chats.json")
        let read: [Conversation]=try storage.read("chats.json",fallback:[])
        XCTAssertEqual(read,chats)
        XCTAssertEqual(try root.resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
    }
    func testCorruptDataIsNotDeleted() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let storage=try LocalStorage(root:root), url=root.appendingPathComponent("chats.json")
        try Data("not-json".utf8).write(to:url)
        XCTAssertThrowsError(try storage.read("chats.json",fallback:[Conversation]()))
        XCTAssertEqual(try Data(contentsOf:url),Data("not-json".utf8))
    }
    private func withFile(_ data: Data, body: (URL)throws->Void) throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".gguf")
        defer { try? FileManager.default.removeItem(at:url) }; try data.write(to:url); try body(url)
    }
    private func number<T:FixedWidthInteger>(_ value:T)->Data { var little=value.littleEndian; return withUnsafeBytes(of:&little) {Data($0)} }
    private func string(_ text:String)->Data { number(UInt64(text.utf8.count))+Data(text.utf8) }
    private func fixture(architecture:String="qwen35",template:Bool=true)->Data {
        var d=Data("GGUF".utf8)+number(UInt32(3))+number(UInt64(1))+number(UInt64(template ? 3 : 2))
        d += string("general.architecture")+number(UInt32(8))+string(architecture)
        d += string("general.name")+number(UInt32(8))+string("Fixture")
        if template { d += string("tokenizer.chat_template")+number(UInt32(8))+string("{{ messages }}") }
        d += Data(repeating:0,count:128); return d
    }
    func testGGUFMetadata() throws { try withFile(fixture()) { let info=try GGUFInspector.inspect($0); XCTAssertEqual(info.architecture,"qwen35"); XCTAssertEqual(info.name,"Fixture") } }
    func testRejectsNonGGUF() throws { try withFile(Data(repeating:0,count:200)) { XCTAssertThrowsError(try GGUFInspector.inspect($0)) } }
    func testRejectsTruncatedGGUF() throws { try withFile(Data(fixture().prefix(26))) { XCTAssertThrowsError(try GGUFInspector.inspect($0)) } }
    func testRejectsProjectors() throws { try withFile(fixture(architecture:"clip")) { XCTAssertThrowsError(try GGUFInspector.inspect($0)) } }
    func testRequiresChatTemplate() throws { try withFile(fixture(template:false)) { XCTAssertThrowsError(try GGUFInspector.inspect($0)) } }
    func testRejectsOversizedMetadataLength() throws {
        var d=Data("GGUF".utf8)+number(UInt32(3))+number(UInt64(1))+number(UInt64(1)); d += number(UInt64.max); d += Data(repeating:0,count:128)
        try withFile(d) { XCTAssertThrowsError(try GGUFInspector.inspect($0)) }
    }
    func testSHA256() throws { try withFile(Data("abc".utf8)) { XCTAssertEqual(try GGUFInspector.hash($0),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") } }
}
