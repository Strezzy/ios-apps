import XCTest
import UIKit
@testable import Velvet

final class SearchTests: XCTestCase {
    func testNaturalLanguageRanksCombinedDescriptorsAbovePartialMatch() {
        let complete = SearchDocument(id: UUID(), labels: [.init(name: "clothing portrait", confidence: 0.9)], colors: ["red", "warm color"])
        let partial = SearchDocument(id: UUID(), colors: ["red"])
        let unrelated = SearchDocument(id: UUID(), colors: ["blue"])
        let results = LocalSearchEngine.search(query: "Photos with warm lighting and red clothing", documents: [partial, unrelated, complete])
        XCTAssertEqual(results.first?.id, complete.id)
        XCTAssertFalse(results.contains(where: { $0.id == unrelated.id }))
    }

    func testRecognizedTextAndAccentsAreSearchable() {
        let document = SearchDocument(id: UUID(), recognizedText: "CAFÉ OPEN")
        XCTAssertEqual(LocalSearchEngine.search(query: "cafe", documents: [document]).first?.id, document.id)
    }

    func testWholeTokensDoNotMatchSubstrings() {
        let document = SearchDocument(id: UUID(), recognizedText: "credit")
        XCTAssertTrue(LocalSearchEngine.search(query: "red", documents: [document]).isEmpty)
    }

    func testVideoFilterDoesNotReturnPhotos() {
        let photo = SearchDocument(id: UUID(), colors: ["blue"], mediaKind: "photo")
        let video = SearchDocument(id: UUID(), colors: ["blue"], mediaKind: "video")
        let matches = LocalSearchEngine.search(query: "Find videos with blue lighting", documents: [photo, video])
        XCTAssertEqual(matches.map(\.id), [video.id])
    }

    func testEmptyAndFillerQueriesReturnNothing() {
        let document = SearchDocument(id: UUID(), colors: ["red"])
        XCTAssertTrue(LocalSearchEngine.search(query: "  ", documents: [document]).isEmpty)
        XCTAssertTrue(LocalSearchEngine.search(query: "show me the", documents: [document]).isEmpty)
    }

    func testDifferentModelVectorsAreNeverCompared() {
        let document = SearchDocument(id: UUID(), embedding: [1, 0], modelIdentifier: "other")
        XCTAssertTrue(LocalSearchEngine.search(query: "beach", documents: [document], queryEmbedding: [1, 0], modelIdentifier: "current").isEmpty)
    }

    func testSemanticMatchWorksWithoutLabelOverlap() {
        let document = SearchDocument(id: UUID(), embedding: [1, 0], modelIdentifier: "current")
        let matches = LocalSearchEngine.search(query: "beach", documents: [document], queryEmbedding: [1, 0], modelIdentifier: "current")
        XCTAssertEqual(matches.first?.id, document.id)
        XCTAssertEqual(matches.first?.score ?? 0, 0.85, accuracy: 0.0001)
    }

    func testCosineRejectsZeroCorruptAndMismatchedVectors() {
        XCTAssertNil(LocalSearchEngine.cosineSimilarity([], []))
        XCTAssertNil(LocalSearchEngine.cosineSimilarity([0, 0], [1, 1]))
        XCTAssertNil(LocalSearchEngine.cosineSimilarity([1], [1, 2]))
        XCTAssertNil(LocalSearchEngine.cosineSimilarity([.nan], [1]))
        XCTAssertNil(LocalSearchEngine.cosineSimilarity([.infinity], [1]))
        XCTAssertEqual(LocalSearchEngine.cosineSimilarity([1, 0], [0, 1]), 0)
    }

    func testUnknownIndexSchemaIsIgnored() {
        let document = SearchDocument(id: UUID(), colors: ["red"], schemaVersion: 999)
        XCTAssertTrue(LocalSearchEngine.search(query: "red", documents: [document]).isEmpty)
    }

    func testResultLimitAndDeterministicTieOrdering() {
        let documents = (0..<8).map { _ in SearchDocument(id: UUID(), colors: ["blue"]) }
        let first = LocalSearchEngine.search(query: "blue", documents: documents, limit: 3)
        let second = LocalSearchEngine.search(query: "blue", documents: Array(documents.reversed()), limit: 3)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testDocumentRoundTripPreservesPrivateSearchData() throws {
        let original = SearchDocument(id: UUID(), labels: [.init(name: "portrait", confidence: 0.8)],
                                      recognizedText: "private text", colors: ["red"], featurePrint: Data([1, 2, 3]),
                                      embedding: [0.1, 0.2], modelIdentifier: "test")
        let decoded = try JSONDecoder().decode(SearchDocument.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.embedding, original.embedding)
        XCTAssertEqual(decoded.featurePrint, original.featurePrint)
        XCTAssertEqual(decoded.recognizedText, original.recognizedText)
    }

    func testInvalidImageFailsSafely() {
        XCTAssertThrowsError(try LocalImageAnalyzer.analyze(imageData: Data([0, 1, 2]), itemID: UUID(), mediaKind: "photo"))
    }

    func testAnalysisProducesColorAndFeaturePrintEntirelyInMemory() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        let bytes = try XCTUnwrap(image.pngData())
        let (document, _) = try LocalImageAnalyzer.analyze(imageData: bytes, itemID: UUID(), mediaKind: "photo")
        XCTAssertTrue(document.colors.contains("red"))
        XCTAssertNotNil(document.featurePrint)
        XCTAssertEqual(bytes, image.pngData())
    }

    func testSimilarityExcludesReferenceAndSortsByCloseness() async {
        let reference = SearchDocument(id: UUID(), embedding: [1, 0], modelIdentifier: "test")
        let close = SearchDocument(id: UUID(), embedding: [0.99, 0.01], modelIdentifier: "test")
        let distant = SearchDocument(id: UUID(), embedding: [0.3, 0.7], modelIdentifier: "test")
        let matches = await LocalSearchService().similar(to: reference, in: [reference, distant, close])
        XCTAssertEqual(matches.map(\.id), [close.id, distant.id])
    }

    func testBundledModelPerformsRealImageInference() async throws {
        guard LocalSearchService.modelIsBundled else { throw XCTSkip("Semantic model is not included in this test build") }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }
        let service = LocalSearchService()
        let document = try await service.analyze(imageData: XCTUnwrap(image.pngData()), itemID: UUID())
        XCTAssertEqual(document.embedding?.count, 768)
        XCTAssertEqual(document.modelIdentifier, LocalSearchService.modelIdentifier)
        await service.reset()
    }
}
