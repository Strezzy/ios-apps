import Foundation

/// Private, media-derived information. Persist only through VaultStore encryption.
struct SearchDocument: Codable, Identifiable, Sendable {
    static let currentSchemaVersion = 1
    let id: UUID
    var labels: [SearchLabel]
    var recognizedText: String
    var colors: [String]
    var featurePrint: Data?
    var embedding: [Float]?
    var modelIdentifier: String?
    var mediaKind: String
    var analyzedAt: Date
    var schemaVersion: Int

    init(id: UUID, labels: [SearchLabel] = [], recognizedText: String = "",
         colors: [String] = [], featurePrint: Data? = nil, embedding: [Float]? = nil,
         modelIdentifier: String? = nil, mediaKind: String = "photo",
         analyzedAt: Date = Date(), schemaVersion: Int = currentSchemaVersion) {
        self.id = id
        self.labels = labels
        self.recognizedText = recognizedText
        self.colors = colors
        self.featurePrint = featurePrint
        self.embedding = embedding
        self.modelIdentifier = modelIdentifier
        self.mediaKind = mediaKind
        self.analyzedAt = analyzedAt
        self.schemaVersion = schemaVersion
    }
}

struct SearchLabel: Codable, Hashable, Sendable {
    let name: String
    let confidence: Float
}

struct SearchMatch: Identifiable, Sendable {
    let id: UUID
    /// Ranking score, not a probability or confidence in a factual description.
    let score: Double
    let matchedTerms: [String]
}

enum LocalSearchError: LocalizedError {
    case invalidImage, unavailableModel, invalidEmbedding, imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This image could not be analyzed. The original remains in your vault."
        case .unavailableModel: return "The bundled semantic model is unavailable. Local labels and colors remain searchable."
        case .invalidEmbedding: return "The local model returned an unsupported result."
        case .imageTooLarge: return "This image exceeds the safe analysis size. The original remains in your vault."
        }
    }
}
