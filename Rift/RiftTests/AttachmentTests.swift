import XCTest
import UIKit
import PDFKit
@testable import Rift

final class AttachmentTests: XCTestCase {
    private func store() throws -> (LocalStorage, AttachmentStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try LocalStorage(root: root)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (storage, try AttachmentStore(storage: storage))
    }
    func testExistingChatDataStillDecodesWithoutAttachments() throws {
        let json = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"role\":\"user\",\"content\":\"Hey\",\"interrupted\":false}"
        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        XCTAssertNil(message.attachments)
        XCTAssertEqual(message.content, "Hey")
    }
    func testTextAttachmentPreservesContentAndRoundTripsWithChat() throws {
        let (storage, files) = try store()
        let url = storage.root.appendingPathComponent("notes.txt")
        try "Local document: RIFT 42".write(to: url, atomically: true, encoding: .utf8)
        let attachment = try files.importFile(url)
        XCTAssertEqual(attachment.text, "Local document: RIFT 42")
        XCTAssertFalse(attachment.isImage)
        let message = ChatMessage(role: "user", content: "Read this", attachments: [attachment])
        XCTAssertEqual(try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message)), message)
    }
    @MainActor func testPDFTextExtractionAndScannedPDFFailure() throws {
        let (storage, files) = try store()
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
        let url = storage.root.appendingPathComponent("sample.pdf")
        try pdf.writePDF(to: url) { context in context.beginPage(); ("Rift local PDF 42" as NSString).draw(at: CGPoint(x: 20, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)]) }
        XCTAssertTrue(try XCTUnwrap(files.importFile(url).text).contains("Rift local PDF 42"))
        try pdf.writePDF(to: url) { context in context.beginPage() }
        XCTAssertThrowsError(try files.importFile(url))
    }
    @MainActor func testImageIsNormalizedBoundedSavedAndRemoved() throws {
        let (storage, files) = try store()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900))
        let url = storage.root.appendingPathComponent("input.png")
        try renderer.pngData { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900)) }.write(to: url)
        let attachment = try files.importFile(url)
        let saved = try XCTUnwrap(files.imageURL(attachment))
        let image = try XCTUnwrap(UIImage(contentsOfFile: saved.path)?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), 768)
        XCTAssertTrue(attachment.isImage)
        XCTAssertNil(attachment.text)
        files.remove(attachment)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        var invalid = attachment; invalid.imageFile = "../outside.jpg"
        XCTAssertNil(files.imageURL(invalid))
    }
    func testOversizedTextAndUnsupportedFilesFailExplicitly() throws {
        let (storage, files) = try store()
        let url = storage.root.appendingPathComponent("long.txt")
        try String(repeating: "a", count: 24_001).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try files.importFile(url))
        let binary = storage.root.appendingPathComponent("archive.zip")
        try Data([0, 1, 2, 3]).write(to: binary)
        XCTAssertThrowsError(try files.importFile(binary))
    }
}
