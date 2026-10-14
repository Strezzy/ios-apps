import XCTest
@testable import Rift

final class CancellationTests: XCTestCase {
    private var missingModel: InstalledModel {
        .init(id: "cancel-test", name: "Cancellation test", filename: "missing.gguf", bytes: 128,
              sha256: String(repeating: "0", count: 64), architecture: "llama", catalogID: nil, importedAt: Date())
    }
    func testStopBeforeGenerationTaskCannotBeResetByTheQueue() async {
        let service = InferenceService()
        service.prepare()
        service.stop()
        do {
            _ = try await service.run(model: missingModel, url: URL(fileURLWithPath: "/rift-test-does-not-exist.gguf"),
                messages: [["role": "user", "content": "Hello"]], context: 1024, maxTokens: 16,
                temperature: 0.7, thinking: false, workingGB: nil, text: { _ in }, status: { _ in })
            XCTFail("A stopped request must not generate a reply")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Stopped.")
        }
        service.unload()
    }
    func testOnlyNewRequestPreparationClearsCancellation() async {
        let service = InferenceService()
        service.prepare()
        service.stop()
        service.prepare()
        do {
            _ = try await service.run(model: missingModel, url: URL(fileURLWithPath: "/rift-test-does-not-exist.gguf"),
                messages: [["role": "user", "content": "Hello"]], context: 1024, maxTokens: 16,
                temperature: 0.7, thinking: false, workingGB: nil, text: { _ in }, status: { _ in })
            XCTFail("The intentionally absent test model must not load")
        } catch {
            XCTAssertNotEqual(error.localizedDescription, "Stopped.")
            XCTAssertTrue(error.localizedDescription.contains("could not load"))
        }
        service.unload()
    }
}
