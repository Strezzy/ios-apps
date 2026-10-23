import Foundation

enum VaultMediaKind: String, Codable, Sendable {
    case photo, video
}

struct VaultItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: VaultMediaKind
    let createdAt: Date
    var title: String
    var note: String
    var isFavorite: Bool
    var albumIDs: Set<UUID>
    var trashedAt: Date?
    let byteCount: Int64
    let fileExtension: String
    let width: Int?
    let height: Int?
    let duration: Double?
    let contentHash: String

    var isTrashed: Bool { trashedAt != nil }
}

struct VaultAlbum: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
}

enum VaultError: Error, LocalizedError, Equatable {
    case locked
    case authenticationUnavailable
    case missingKey
    case invalidKey
    case unsupportedVersion
    case corruptCatalog
    case rollbackDetected
    case itemNotFound
    case invalidMedia
    case invalidVideo
    case invalidRange
    case integrityFailure
    case storageFull
    case operationCancelled
    case transactionFailed
    case backupTooLarge
    case invalidRecoveryKey

    var errorDescription: String? {
        switch self {
        case .locked: return "Unlock Velvet to access your vault."
        case .authenticationUnavailable: return "Set a device passcode and enable device-owner authentication to use Velvet."
        case .missingKey: return "The vault key is unavailable. Existing encrypted files have been preserved."
        case .invalidKey: return "The vault key could not be read. Existing encrypted files have been preserved."
        case .unsupportedVersion: return "This vault was created with an unsupported format."
        case .corruptCatalog: return "The vault catalogue failed validation. No existing files were changed."
        case .rollbackDetected: return "The vault catalogue does not match its protected integrity record. No existing files were changed."
        case .itemNotFound: return "This item is no longer available."
        case .invalidMedia: return "This image is unsupported, damaged, or larger than the 128 MB import limit."
        case .invalidVideo: return "The recording is incomplete or its segment order is invalid."
        case .invalidRange: return "The requested media range is invalid."
        case .integrityFailure: return "The encrypted file failed authentication. Playback or viewing was stopped."
        case .storageFull: return "There is not enough free space to safely save this item."
        case .operationCancelled: return "The operation was cancelled when the vault locked."
        case .transactionFailed: return "The save could not be confirmed. Unlock the vault again to recover its last authenticated state."
        case .backupTooLarge: return "This backup has more metadata than this version can safely process."
        case .invalidRecoveryKey: return "The recovery key or encrypted backup is invalid."
        }
    }
}

struct VaultBlobReference: Codable, Equatable, Sendable {
    let filename: String
    let ciphertextHash: String
}

struct VaultRecord: Codable, Sendable {
    var item: VaultItem
    let wrappedKey: Data
    var original: VaultBlobReference?
    var thumbnail: VaultBlobReference?
    var videoManifest: VaultBlobReference?
    var searchDocument: VaultBlobReference?
}

struct VaultCatalog: Codable, Sendable {
    var format = 1
    var revision: UInt64 = 0
    var records: [VaultRecord] = []
    var albums: [VaultAlbum] = []
}

struct VaultSnapshot: Sendable {
    let items: [VaultItem]
    let albums: [VaultAlbum]
}

struct VaultVideoSegment: Codable, Sendable {
    let sequence: Int
    let byteCount: Int
    let isInitialization: Bool
    let ciphertextHash: String
}

struct VaultVideoManifest: Codable, Sendable {
    let format: Int
    let assetID: UUID
    let segments: [VaultVideoSegment]
    let totalByteCount: Int64

    func validate(expectedID: UUID) throws {
        guard format == 1, assetID == expectedID,
              segments.count >= 2, segments.count <= 1_000_000 else { throw VaultError.invalidVideo }
        var total: Int64 = 0
        for (index, segment) in segments.enumerated() {
            guard segment.sequence == index,
                  segment.isInitialization == (index == 0),
                  segment.byteCount > 0,
                  segment.byteCount <= VaultVideoWriter.maximumSegmentBytes,
                  segment.ciphertextHash.count == 64 else { throw VaultError.invalidVideo }
            let addition = total.addingReportingOverflow(Int64(segment.byteCount))
            guard !addition.overflow else { throw VaultError.invalidVideo }
            total = addition.partialValue
        }
        guard total == totalByteCount else { throw VaultError.invalidVideo }
    }
}
