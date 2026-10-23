import Foundation

/// Pure in-memory ranking. This type never reads or writes files or retains queries.
enum LocalSearchEngine {
    static func search(query: String, documents: [SearchDocument],
                       queryEmbedding: [Float]? = nil, modelIdentifier: String? = nil,
                       limit: Int = 100) -> [SearchMatch] {
        let terms = tokens(query).filter { !stopWords.contains($0) }
        guard !terms.isEmpty else { return [] }
        var wanted = Set(terms)
        let requestedKind = wanted.contains("video") ? "video" : (wanted.contains("photo") ? "photo" : nil)
        if wanted.count > 1 { wanted.remove("photo"); wanted.remove("video") }
        return documents.compactMap { document -> SearchMatch? in
            guard document.schemaVersion == SearchDocument.currentSchemaVersion else { return nil }
            if let requestedKind, document.mediaKind != requestedKind { return nil }
            var weights: [String: Double] = [:]
            for label in document.labels {
                for token in tokens(label.name) {
                    weights[token] = max(weights[token, default: 0], Double(label.confidence))
                }
            }
            for token in tokens(document.recognizedText) { weights[token] = 1 }
            for token in tokens(document.colors.joined(separator: " ")) { weights[token] = 0.95 }
            for token in tokens(document.mediaKind) { weights[token] = 1 }
            let matched = wanted.filter { weights[$0] != nil }.sorted()
            let lexical = matched.reduce(0.0) { $0 + weights[$1, default: 0] } / Double(wanted.count)
            var score = lexical
            if let queryEmbedding, let embedding = document.embedding,
               let modelIdentifier, document.modelIdentifier == modelIdentifier,
               let cosine = cosineSimilarity(queryEmbedding, embedding), cosine >= 0.18 {
                score = max(lexical, 0.85 * max(0, cosine) + 0.15 * lexical)
            }
            guard score > 0 else { return nil }
            return SearchMatch(id: document.id, score: score, matchedTerms: matched)
        }.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.id.uuidString < rhs.id.uuidString : lhs.score > rhs.score
        }.prefix(max(0, limit)).map { $0 }
    }

    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard !lhs.isEmpty, lhs.count == rhs.count,
              lhs.allSatisfy(\.isFinite), rhs.allSatisfy(\.isFinite) else { return nil }
        var dot = 0.0, left = 0.0, right = 0.0
        for (a, b) in zip(lhs, rhs) {
            dot += Double(a) * Double(b)
            left += Double(a) * Double(a)
            right += Double(b) * Double(b)
        }
        guard left > 0, right > 0 else { return nil }
        return min(1, max(-1, dot / sqrt(left * right)))
    }

    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { synonyms[$0] ?? $0 }
    }

    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "with", "of", "on", "in", "at", "to", "me", "my", "show",
        "find", "please", "that", "are", "is", "taken", "some", "has", "have", "by", "next"
    ]
    private static let synonyms: [String: String] = [
        "photos": "photo", "photograph": "photo", "photographs": "photo", "pictures": "photo", "picture": "photo",
        "videos": "video", "movies": "video", "movie": "video", "portraits": "portrait",
        "people": "person", "persons": "person", "faces": "face", "outdoors": "outdoor", "outside": "outdoor",
        "indoors": "indoor", "inside": "indoor", "nighttime": "night", "nighttimephotography": "night",
        "windows": "window", "clothes": "clothing", "wearing": "clothing", "reddish": "red", "bluish": "blue",
        "grey": "gray", "darkness": "dark", "dim": "dark", "brightly": "bright", "lights": "light", "lighting": "light"
    ]
}
