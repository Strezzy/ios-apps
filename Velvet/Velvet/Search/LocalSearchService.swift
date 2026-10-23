import Foundation
#if canImport(MediaPipeTasksRetrieval)
import MediaPipeTasksRetrieval
#endif

/// Serializes inference off the UI actor. It retains no media library or query history.
actor LocalSearchService {
    static let modelName = "embeddinggemma-2-text-vision-440m"
    static let modelIdentifier = "embeddinggemma2-tv440m-92dcbea108899e5d-768"
    #if canImport(MediaPipeTasksRetrieval)
    private var embedder: UniversalEmbedder?
    #endif
    private var modelFailed = false

    nonisolated static var modelIsBundled: Bool {
        #if canImport(MediaPipeTasksRetrieval)
        return modelURL != nil
        #else
        return false
        #endif
    }

    nonisolated private static var modelURL: URL? {
        Bundle.main.url(forResource: modelName, withExtension: "litertlm")
            ?? Bundle.main.url(forResource: modelName, withExtension: "litertlm", subdirectory: "Models")
    }

    var capabilityDescription: String {
        if Self.modelIsBundled && !modelFailed { return "EmbeddingGemma 2 · entirely on device" }
        return "Local labels, text, colors and visual similarity"
    }

    func analyze(imageData: Data, itemID: UUID, mediaKind: String = "photo") throws -> SearchDocument {
        try Task.checkCancellation()
        var (document, analysisData) = try LocalImageAnalyzer.analyze(imageData: imageData, itemID: itemID, mediaKind: mediaKind)
        defer { analysisData.resetBytes(in: analysisData.startIndex..<analysisData.endIndex) }
        try Task.checkCancellation()
        #if canImport(MediaPipeTasksRetrieval)
        if Self.modelIsBundled {
            do {
                let result = try model().embed(imageBytes: analysisData)
                document.embedding = try vector(result.embeddings.first?.floatEmbedding)
                document.modelIdentifier = Self.modelIdentifier
            } catch {
                // Preserve useful Vision indexing if local model loading or inference fails.
                // Never surface underlying runtime errors that might contain private input.
                modelFailed = true
            }
        }
        #endif
        try Task.checkCancellation()
        return document
    }

    func search(query: String, documents: [SearchDocument]) throws -> [SearchMatch] {
        try Task.checkCancellation()
        let boundedQuery = String(query.prefix(1_024))
        guard !boundedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var queryVector: [Float]?
        #if canImport(MediaPipeTasksRetrieval)
        if Self.modelIsBundled && documents.contains(where: { $0.modelIdentifier == Self.modelIdentifier }) {
            do {
                let result = try model().embed(text: boundedQuery)
                queryVector = try vector(result.embeddings.first?.floatEmbedding)
            } catch { modelFailed = true }
        }
        #endif
        try Task.checkCancellation()
        return LocalSearchEngine.search(query: boundedQuery, documents: documents,
                                        queryEmbedding: queryVector, modelIdentifier: Self.modelIdentifier)
    }

    func similar(to reference: SearchDocument, in documents: [SearchDocument]) -> [SearchMatch] {
        documents.filter { $0.id != reference.id }.compactMap { candidate -> SearchMatch? in
            guard !Task.isCancelled else { return nil }
            var score: Double?
            if let lhs = reference.embedding, let rhs = candidate.embedding,
               reference.modelIdentifier != nil, reference.modelIdentifier == candidate.modelIdentifier {
                score = LocalSearchEngine.cosineSimilarity(lhs, rhs)
            }
            if score == nil, let lhs = reference.featurePrint, let rhs = candidate.featurePrint {
                score = LocalImageAnalyzer.featureSimilarity(lhs, rhs)
            }
            guard let score, score > 0 else { return nil }
            return SearchMatch(id: candidate.id, score: score, matchedTerms: [])
        }.sorted { $0.score > $1.score }.prefix(100).map { $0 }
    }

    /// Call on vault lock/background. A completed inference's result must still be session-checked by its caller.
    func reset() {
        #if canImport(MediaPipeTasksRetrieval)
        embedder = nil
        #endif
        modelFailed = false
    }

    #if canImport(MediaPipeTasksRetrieval)
    private func model() throws -> UniversalEmbedder {
        if let embedder { return embedder }
        guard let url = Self.modelURL else {
            throw LocalSearchError.unavailableModel
        }
        let options = UniversalEmbedderOptions()
        options.baseOptions.modelAssetPath = url.path
        options.l2Normalize = true
        options.maxInputLength = 256
        options.visionTokensPerImage = 70
        // LiteRT-LM's documented no-cache sentinel, also used by its MediaPipe WASM adapter.
        options.cacheDirectory = ":nocache"
        let loaded = try UniversalEmbedder(options: options)
        embedder = loaded
        modelFailed = false
        return loaded
    }

    private func vector(_ numbers: [NSNumber]?) throws -> [Float] {
        guard let numbers, numbers.count == 768 else { throw LocalSearchError.invalidEmbedding }
        let values = numbers.map(\.floatValue)
        guard values.allSatisfy(\.isFinite), values.contains(where: { $0 != 0 }) else { throw LocalSearchError.invalidEmbedding }
        return values
    }
    #endif
}
