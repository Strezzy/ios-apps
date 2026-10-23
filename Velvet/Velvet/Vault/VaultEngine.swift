import CryptoKit
import Foundation
import ImageIO
import LocalAuthentication
import UniformTypeIdentifiers

actor VaultEngine {
    static let maximumPhotoBytes = 80 * 1_024 * 1_024
    static let maximumCatalogBytes = 64 * 1_024 * 1_024
    private static let initialAnchor = "uninitialized-vault-v1"
    let root: URL
    let keyStore: any VaultKeyStoring
    private var keyRecord: VaultKeyRecord?
    private var masterKey: SymmetricKey?
    private var context: LAContext?
    private var catalog: VaultCatalog?
    private var catalogHash: String?
    private var session: VaultSession?
    private var pendingVideos: [UUID: VaultVideoWriter] = [:]

    init(root: URL? = nil, keyStore: any VaultKeyStoring = KeychainKeyStore()) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VelvetVault", isDirectory: true)
        self.keyStore = keyStore
    }

    private var catalogURL: URL { root.appendingPathComponent("catalog.vlt") }
    private var assetsURL: URL { root.appendingPathComponent("assets", isDirectory: true) }

    func open(context: LAContext) throws -> (VaultSnapshot, VaultSession) {
        lock()
        let rootExisted = FileManager.default.fileExists(atPath: root.path)
        let existing = try keyStore.load(context: context)
        let persisted: VaultKeyRecord
        if let existing {
            persisted = existing
        } else {
            // A lost Keychain entry must never initialize over existing vault data.
            guard !rootExisted else { throw VaultError.missingKey }
            persisted = VaultKeyRecord(masterKey: VaultCrypto.keyData(VaultCrypto.randomKey()), authorizedCatalogs: [Self.initialAnchor])
            try keyStore.create(persisted, context: context)
        }
        let master = try VaultCrypto.key(from: persisted.masterKey)
        let activeSession = VaultSession()
        self.keyRecord = persisted
        self.masterKey = master
        self.context = context
        self.session = activeSession
        do {
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                let ciphertext = try ProtectedFiles.read(catalogURL, maximumBytes: Self.maximumCatalogBytes)
                let hash = VaultCrypto.digest(ciphertext)
                guard persisted.authorizedCatalogs.contains(hash) else { throw VaultError.rollbackDetected }
                let plaintext = try VaultCrypto.open(ciphertext, key: master, domain: "catalog")
                guard let decoded = try? JSONDecoder().decode(VaultCatalog.self, from: plaintext) else { throw VaultError.corruptCatalog }
                try validateCatalog(decoded)
                self.catalog = decoded
                self.catalogHash = hash
                // Recover an interrupted commit to the authenticated version actually
                // on disk, then close the old-version acceptance window immediately.
                var finalized = persisted
                finalized.authorizedCatalogs = [hash]
                try keyStore.update(finalized, context: context)
                self.keyRecord = finalized
            } else {
                // iOS can retain a device-only Keychain entry after uninstalling
                // an app. An authenticated key with an entirely absent container
                // may start an empty vault so explicit backup restore remains
                // usable after reinstall. A partial/existing container never does.
                guard persisted.authorizedCatalogs.contains(Self.initialAnchor) || !rootExisted else {
                    throw VaultError.corruptCatalog
                }
                if FileManager.default.fileExists(atPath: assetsURL.path) {
                    guard try FileManager.default.contentsOfDirectory(at: assetsURL, includingPropertiesForKeys: nil).isEmpty else {
                        throw VaultError.corruptCatalog
                    }
                }
                try ProtectedFiles.createDirectory(root)
                try ProtectedFiles.createDirectory(assetsURL)
                self.catalog = VaultCatalog()
                self.catalogHash = Self.initialAnchor
                try commit(VaultCatalog())
            }
            try ProtectedFiles.protect(root)
            try ProtectedFiles.createDirectory(assetsURL)
            try recoverUnreferencedCiphertext()
            return (try snapshot(), activeSession)
        } catch {
            lock()
            throw error
        }
    }

    func lock(matching sessionID: UUID? = nil) {
        if let sessionID, session?.id != sessionID { return }
        session?.revoke()
        pendingVideos.removeAll()
        session = nil
        masterKey = nil
        keyRecord = nil
        context = nil
        catalog = nil
        catalogHash = nil
    }

    func snapshot() throws -> VaultSnapshot {
        let (_, current, _) = try requireUnlocked()
        return VaultSnapshot(items: current.records.map(\.item).sorted { $0.createdAt > $1.createdAt },
            albums: current.albums.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    func savePhoto(data: Data, fileExtension: String, thumbnail: Data?, width: Int?, height: Int?) throws -> VaultItem {
        let (master, current, activeSession) = try requireUnlocked()
        let info = try Self.inspectPhoto(data)
        let id = UUID()
        let key = VaultCrypto.randomKey()
        let directory = assetDirectory(id)
        try ProtectedFiles.createDirectory(directory)
        do {
            let original = try writeBlob(data, domain: "original", id: id, key: key, filename: "original.vlt")
            let preview = try thumbnail ?? Self.makeThumbnail(data)
            guard preview.count <= 8 * 1_024 * 1_024 else { throw VaultError.invalidMedia }
            let encryptedThumbnail = try writeBlob(preview, domain: "thumbnail", id: id, key: key, filename: "thumbnail.vlt")
            let item = VaultItem(id: id, kind: .photo, createdAt: Date(), title: "Photo", note: "", isFavorite: false,
                albumIDs: [], trashedAt: nil, byteCount: Int64(data.count), fileExtension: sanitizedExtension(fileExtension),
                width: info.width, height: info.height, duration: nil, contentHash: VaultCrypto.digest(data))
            let record = VaultRecord(item: item,
                wrappedKey: try VaultCrypto.seal(VaultCrypto.keyData(key), key: master, domain: "item.key", assetID: id),
                original: original, thumbnail: encryptedThumbnail, videoManifest: nil, searchDocument: nil)
            var updated = current
            updated.records.append(record)
            try activeSession.requireActive()
            try commit(updated)
            return item
        } catch {
            // If a commit reached disk before its final anchor failed, that record
            // may already own the directory. Recovery determines ownership later.
            if let catalog, !catalog.records.contains(where: { $0.item.id == id }) {
                try? FileManager.default.removeItem(at: directory)
            }
            throw error
        }
    }

    func thumbnail(for id: UUID) throws -> Data? {
        let (record, key, activeSession) = try recordAndKey(id)
        guard let reference = record.thumbnail else { return nil }
        let result = try readBlob(reference, domain: "thumbnail", id: id, key: key, maximumBytes: 8 * 1_024 * 1_024)
        try activeSession.requireActive()
        return result
    }

    func original(for id: UUID) throws -> Data {
        let (record, key, activeSession) = try recordAndKey(id)
        guard record.item.kind == .photo, let reference = record.original else { throw VaultError.invalidMedia }
        let result = try readBlob(reference, domain: "original", id: id, key: key, maximumBytes: Self.maximumPhotoBytes)
        try activeSession.requireActive()
        return result
    }

    func beginVideo(fileExtension: String, width: Int?, height: Int?) throws -> VaultVideoWriter {
        let (master, _, activeSession) = try requireUnlocked()
        let id = UUID()
        let key = VaultCrypto.randomKey()
        let directory = assetDirectory(id)
        try ProtectedFiles.createDirectory(directory)
        let wrapped = try VaultCrypto.seal(VaultCrypto.keyData(key), key: master, domain: "item.key", assetID: id)
        let writer = VaultVideoWriter(id: id, key: key, wrappedKey: wrapped, directory: directory, session: activeSession,
            fileExtension: sanitizedExtension(fileExtension), width: width, height: height)
        pendingVideos[id] = writer
        return writer
    }

    func finishVideo(_ writer: VaultVideoWriter, duration: Double, thumbnail: Data?) throws -> VaultItem {
        let (_, current, activeSession) = try requireUnlocked()
        guard pendingVideos[writer.id] === writer, writer.session.id == activeSession.id,
              duration.isFinite, duration > 0 else { throw VaultError.invalidVideo }
        do {
            let completed = try writer.prepareToCommit()
            let preview = try thumbnail.map { try writer.encryptThumbnail($0) }
            let item = VaultItem(id: writer.id, kind: .video, createdAt: Date(), title: "Video", note: "", isFavorite: false,
                albumIDs: [], trashedAt: nil, byteCount: completed.byteCount, fileExtension: writer.fileExtension,
                width: writer.width, height: writer.height, duration: duration, contentHash: completed.contentHash)
            let record = VaultRecord(item: item, wrappedKey: writer.wrappedKey, original: nil, thumbnail: preview,
                videoManifest: completed.manifest, searchDocument: nil)
            var updated = current
            updated.records.append(record)
            try activeSession.requireActive()
            try commit(updated)
            writer.markCommitted()
            pendingVideos.removeValue(forKey: writer.id)
            return item
        } catch {
            pendingVideos.removeValue(forKey: writer.id)
            writer.cancel()
            if let catalog, !catalog.records.contains(where: { $0.item.id == writer.id }) {
                try? FileManager.default.removeItem(at: writer.directory)
            }
            throw error
        }
    }

    func videoReader(for id: UUID) throws -> VaultVideoReader {
        let (record, key, activeSession) = try recordAndKey(id)
        guard record.item.kind == .video, let reference = record.videoManifest else { throw VaultError.invalidVideo }
        let data = try readBlob(reference, domain: "video.manifest", id: id, key: key, maximumBytes: 32 * 1_024 * 1_024)
        let manifest = try JSONDecoder().decode(VaultVideoManifest.self, from: data)
        try manifest.validate(expectedID: id)
        return try VaultVideoReader(manifest: manifest, directory: assetDirectory(id), key: key, session: activeSession)
    }

    func setFavorite(_ favorite: Bool, for ids: Set<UUID>) throws {
        try mutateItems(ids) { $0.isFavorite = favorite }
    }

    func rename(_ title: String, note: String, for id: UUID) throws {
        try mutateItems([id]) {
            $0.title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
            $0.note = String(note.prefix(10_000))
        }
    }

    func createAlbum(name: String) throws -> VaultAlbum {
        let (_, current, _) = try requireUnlocked()
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty else { throw VaultError.invalidMedia }
        let album = VaultAlbum(id: UUID(), name: name, createdAt: Date())
        var updated = current
        updated.albums.append(album)
        try commit(updated)
        return album
    }

    func deleteAlbum(_ id: UUID) throws {
        let (_, current, _) = try requireUnlocked()
        var updated = current
        updated.albums.removeAll { $0.id == id }
        for index in updated.records.indices { updated.records[index].item.albumIDs.remove(id) }
        try commit(updated)
    }

    func setAlbums(_ albums: Set<UUID>, for ids: Set<UUID>) throws {
        let (_, current, _) = try requireUnlocked()
        guard albums.isSubset(of: Set(current.albums.map(\.id))) else { throw VaultError.itemNotFound }
        try mutateItems(ids) { $0.albumIDs = albums }
    }

    func moveToTrash(_ ids: Set<UUID>) throws {
        try mutateItems(ids) { $0.trashedAt = Date() }
        // Trash is retained until explicit deletion. There is no silent expiry.
        for id in ids { session?.revokeItem(id) }
    }

    func restoreFromTrash(_ ids: Set<UUID>) throws {
        try mutateItems(ids) { $0.trashedAt = nil }
    }

    func permanentlyDelete(_ ids: Set<UUID>) throws {
        let (_, current, activeSession) = try requireUnlocked()
        guard ids.isSubset(of: Set(current.records.filter { $0.item.isTrashed }.map { $0.item.id })) else {
            throw VaultError.itemNotFound
        }
        var updated = current
        updated.records.removeAll { ids.contains($0.item.id) }
        try commit(updated)
        for id in ids {
            activeSession.revokeItem(id)
            try FileManager.default.removeItem(at: assetDirectory(id))
        }
        try clearBackupExports()
    }

    func emptyTrash() throws {
        let (_, current, _) = try requireUnlocked()
        try permanentlyDelete(Set(current.records.filter { $0.item.isTrashed }.map { $0.item.id }))
    }

    func saveSearchDocument(_ document: SearchDocument) throws {
        let (record, key, activeSession) = try recordAndKey(document.id)
        let (_, current, _) = try requireUnlocked()
        let encoded = try JSONEncoder().encode(document)
        guard encoded.count <= 4 * 1_024 * 1_024 else { throw VaultError.invalidMedia }
        let reference = try writeBlob(encoded, domain: "search.document", id: document.id, key: key,
            filename: "search-\(UUID().uuidString.lowercased()).vlt")
        var updated = current
        guard let index = updated.records.firstIndex(where: { $0.item.id == document.id }) else { throw VaultError.itemNotFound }
        updated.records[index].searchDocument = reference
        try activeSession.requireActive()
        try commit(updated)
        if let previous = record.searchDocument {
            try? FileManager.default.removeItem(at: ProtectedFiles.blobURL(previous, directory: assetDirectory(document.id)))
        }
    }

    func searchDocuments() throws -> [SearchDocument] {
        let (master, current, activeSession) = try requireUnlocked()
        var result: [SearchDocument] = []
        for record in current.records where !record.item.isTrashed {
            try activeSession.requireActive()
            guard let reference = record.searchDocument else { continue }
            let key = try unwrap(record, master: master)
            let data = try readBlob(reference, domain: "search.document", id: record.item.id, key: key, maximumBytes: 4 * 1_024 * 1_024)
            let document = try JSONDecoder().decode(SearchDocument.self, from: data)
            guard document.id == record.item.id else { throw VaultError.integrityFailure }
            result.append(document)
        }
        try activeSession.requireActive()
        return result
    }

    private func mutateItems(_ ids: Set<UUID>, mutation: (inout VaultItem) -> Void) throws {
        let (_, current, _) = try requireUnlocked()
        guard ids.isSubset(of: Set(current.records.map { $0.item.id })) else { throw VaultError.itemNotFound }
        var updated = current
        for index in updated.records.indices where ids.contains(updated.records[index].item.id) {
            mutation(&updated.records[index].item)
        }
        try commit(updated)
    }

    private func commit(_ candidate: VaultCatalog) throws {
        let (master, current, activeSession) = try requireUnlocked()
        guard var record = keyRecord, let context, let previousHash = catalogHash else { throw VaultError.locked }
        var updated = candidate
        guard current.revision < UInt64.max else { throw VaultError.corruptCatalog }
        updated.revision = current.revision + 1
        try validateCatalog(updated)
        let ciphertext = try VaultCrypto.seal(JSONEncoder().encode(updated), key: master, domain: "catalog")
        guard ciphertext.count <= Self.maximumCatalogBytes else { throw VaultError.storageFull }
        let nextHash = VaultCrypto.digest(ciphertext)
        try activeSession.requireActive()
        do {
            record.authorizedCatalogs = [previousHash, nextHash]
            try keyStore.update(record, context: context)
            try ProtectedFiles.write(ciphertext, to: catalogURL)
            record.authorizedCatalogs = [nextHash]
            try keyStore.update(record, context: context)
            keyRecord = record
            catalogHash = nextHash
            catalog = updated
        } catch {
            // Never keep using an uncertain in-memory revision. The next unlock
            // authenticates the disk version against the transaction anchors.
            lock()
            throw VaultError.transactionFailed
        }
        // A concurrent synchronous session revocation may have occurred during IO.
        // The encrypted commit remains valid, but no private result is returned.
        try activeSession.requireActive()
    }

    private func requireUnlocked() throws -> (SymmetricKey, VaultCatalog, VaultSession) {
        guard let masterKey, let catalog, let session else { throw VaultError.locked }
        try session.requireActive()
        return (masterKey, catalog, session)
    }

    private func recordAndKey(_ id: UUID) throws -> (VaultRecord, SymmetricKey, VaultSession) {
        let (master, current, activeSession) = try requireUnlocked()
        guard let record = current.records.first(where: { $0.item.id == id }) else { throw VaultError.itemNotFound }
        return (record, try unwrap(record, master: master), activeSession)
    }

    private func unwrap(_ record: VaultRecord, master: SymmetricKey) throws -> SymmetricKey {
        try VaultCrypto.key(from: VaultCrypto.open(record.wrappedKey, key: master, domain: "item.key", assetID: record.item.id))
    }

    private func assetDirectory(_ id: UUID) -> URL {
        assetsURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    private func writeBlob(_ data: Data, domain: String, id: UUID, key: SymmetricKey, filename: String) throws -> VaultBlobReference {
        let ciphertext = try VaultCrypto.seal(data, key: key, domain: domain, assetID: id)
        let reference = VaultBlobReference(filename: filename, ciphertextHash: VaultCrypto.digest(ciphertext))
        try ProtectedFiles.write(ciphertext, to: ProtectedFiles.blobURL(reference, directory: assetDirectory(id)))
        return reference
    }

    private func readBlob(_ reference: VaultBlobReference, domain: String, id: UUID, key: SymmetricKey, maximumBytes: Int) throws -> Data {
        let ciphertext = try ProtectedFiles.read(ProtectedFiles.blobURL(reference, directory: assetDirectory(id)), maximumBytes: maximumBytes + 64)
        try VaultCrypto.verify(ciphertext, reference: reference)
        return try VaultCrypto.open(ciphertext, key: key, domain: domain, assetID: id)
    }

    private func validateCatalog(_ catalog: VaultCatalog) throws {
        guard catalog.format == 1 else { throw VaultError.unsupportedVersion }
        let ids = catalog.records.map { $0.item.id }
        let albums = catalog.albums.map(\.id)
        guard Set(ids).count == ids.count, Set(albums).count == albums.count else { throw VaultError.corruptCatalog }
        for record in catalog.records {
            guard record.wrappedKey.count == 61, record.item.byteCount > 0,
                  record.item.contentHash.count == 64,
                  record.item.albumIDs.isSubset(of: Set(albums)),
                  (record.item.kind == .photo) == (record.original != nil),
                  (record.item.kind == .video) == (record.videoManifest != nil) else { throw VaultError.corruptCatalog }
            for reference in [record.original, record.thumbnail, record.videoManifest, record.searchDocument].compactMap({ $0 }) {
                _ = try ProtectedFiles.blobURL(reference, directory: assetDirectory(record.item.id))
                guard reference.ciphertextHash.count == 64 else { throw VaultError.corruptCatalog }
            }
        }
    }

    private func recoverUnreferencedCiphertext() throws {
        let (_, current, _) = try requireUnlocked()
        let known = Set(current.records.map { $0.item.id.uuidString.lowercased() })
        for directory in try FileManager.default.contentsOfDirectory(at: assetsURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true,
                  UUID(uuidString: directory.lastPathComponent) != nil else { throw VaultError.corruptCatalog }
            if !known.contains(directory.lastPathComponent) { try FileManager.default.removeItem(at: directory) }
        }
        try clearBackupExports()
    }

    private func clearBackupExports() throws {
        let exports = root.appendingPathComponent("exports", isDirectory: true)
        if FileManager.default.fileExists(atPath: exports.path) { try FileManager.default.removeItem(at: exports) }
    }

    private func sanitizedExtension(_ value: String) -> String {
        let normalized = value.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return String(normalized.prefix(12))
    }

    private static func inspectPhoto(_ data: Data) throws -> (width: Int, height: Int) {
        guard !data.isEmpty, data.count <= maximumPhotoBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 40_000, height <= 40_000,
              Int64(width) * Int64(height) <= 200_000_000 else { throw VaultError.invalidMedia }
        return (width, height)
    }

    private static func makeThumbnail(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw VaultError.invalidMedia }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VaultError.invalidMedia
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw VaultError.invalidMedia }
        return output as Data
    }
}

extension VaultEngine {
    func createEncryptedBackup() throws -> VaultBackupExport {
        let (master, current, activeSession) = try requireUnlocked()
        var files: [VaultBackupFile] = []
        for record in current.records {
            try activeSession.requireActive()
            let key = try unwrap(record, master: master)
            var references = [record.original, record.thumbnail, record.searchDocument, record.videoManifest].compactMap { $0 }
            if let reference = record.videoManifest {
                let data = try readBlob(reference, domain: "video.manifest", id: record.item.id, key: key, maximumBytes: 32 * 1_024 * 1_024)
                let video = try JSONDecoder().decode(VaultVideoManifest.self, from: data)
                try video.validate(expectedID: record.item.id)
                references += video.segments.map {
                    VaultBlobReference(filename: VaultVideoWriter.segmentURL(directory: assetDirectory(record.item.id), index: $0.sequence).lastPathComponent,
                        ciphertextHash: $0.ciphertextHash)
                }
            }
            for reference in references {
                let url = try ProtectedFiles.blobURL(reference, directory: assetDirectory(record.item.id))
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size > 0, size <= Self.maximumPhotoBytes + 64 else { throw VaultError.integrityFailure }
                files.append(VaultBackupFile(assetID: record.item.id, filename: reference.filename, byteCount: size,
                    ciphertextHash: reference.ciphertextHash))
            }
        }
        let encryptedCatalog = try ProtectedFiles.read(catalogURL, maximumBytes: Self.maximumCatalogBytes)
        guard VaultCrypto.digest(encryptedCatalog) == catalogHash else { throw VaultError.integrityFailure }
        let manifest = VaultBackupManifest(format: 1, sourceMasterKey: VaultCrypto.keyData(master), encryptedCatalog: encryptedCatalog, files: files)
        let encodedManifest = try JSONEncoder().encode(manifest)
        guard encodedManifest.count <= VaultBackupFormat.maximumManifestBytes - 64 else { throw VaultError.backupTooLarge }
        let recoveryKey = VaultCrypto.randomKey()
        let encryptedManifest = try VaultCrypto.seal(encodedManifest, key: recoveryKey, domain: "backup.manifest")
        let exports = root.appendingPathComponent("exports", isDirectory: true)
        try ProtectedFiles.createDirectory(exports)
        let outputURL = exports.appendingPathComponent("Velvet-\(UUID().uuidString.lowercased()).velvetbackup")
        do {
            try ProtectedFiles.write(VaultBackupFormat.header(manifestLength: encryptedManifest.count) + encryptedManifest, to: outputURL)
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try output.seekToEnd()
            for descriptor in files {
                try activeSession.requireActive()
                let reference = VaultBlobReference(filename: descriptor.filename, ciphertextHash: descriptor.ciphertextHash)
                let input = try FileHandle(forReadingFrom: ProtectedFiles.blobURL(reference, directory: assetDirectory(descriptor.assetID)))
                defer { try? input.close() }
                var remaining = descriptor.byteCount
                var digest = SHA256()
                while remaining > 0 {
                    try activeSession.requireActive()
                    let part = try VaultBackupFormat.readExactly(input, count: min(remaining, 1_024 * 1_024))
                    try ProtectedFiles.requireCapacity(for: part.count, at: exports)
                    try output.write(contentsOf: part)
                    digest.update(data: part)
                    remaining -= part.count
                }
                guard digest.finalize().map({ String(format: "%02x", $0) }).joined() == descriptor.ciphertextHash else {
                    throw VaultError.integrityFailure
                }
            }
            try output.synchronize()
            try activeSession.requireActive()
            return VaultBackupExport(fileURL: outputURL, recoveryKey: VaultBackupFormat.encodeKey(recoveryKey))
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    func restoreEncryptedBackup(from url: URL, recoveryKey: String) throws {
        let (master, current, activeSession) = try requireUnlocked()
        let key = try VaultBackupFormat.decodeKey(recoveryKey)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let header = try VaultBackupFormat.readExactly(input, count: 16)
        let manifestLength = try VaultBackupFormat.manifestLength(from: header)
        let encryptedManifest = try VaultBackupFormat.readExactly(input, count: manifestLength)
        let manifestData: Data
        do { manifestData = try VaultCrypto.open(encryptedManifest, key: key, domain: "backup.manifest") }
        catch { throw VaultError.invalidRecoveryKey }
        let manifest = try JSONDecoder().decode(VaultBackupManifest.self, from: manifestData)
        guard manifest.format == 1, manifest.encryptedCatalog.count <= Self.maximumCatalogBytes else { throw VaultError.unsupportedVersion }
        let sourceMaster = try VaultCrypto.key(from: manifest.sourceMasterKey)
        let sourceCatalog = try JSONDecoder().decode(VaultCatalog.self,
            from: VaultCrypto.open(manifest.encryptedCatalog, key: sourceMaster, domain: "catalog"))
        try validateCatalog(sourceCatalog)
        let sourceIDs = Set(sourceCatalog.records.map { $0.item.id })
        var offsets: [String: UInt64] = [:]
        var descriptors: [String: VaultBackupFile] = [:]
        var position = UInt64(16 + manifestLength)
        for file in manifest.files {
            guard file.byteCount >= 30, file.byteCount <= Self.maximumPhotoBytes + 64,
                  sourceIDs.contains(file.assetID), descriptors[file.identity] == nil,
                  file.ciphertextHash.count == 64 else { throw VaultError.integrityFailure }
            _ = try ProtectedFiles.blobURL(VaultBlobReference(filename: file.filename, ciphertextHash: file.ciphertextHash), directory: root)
            let next = position.addingReportingOverflow(UInt64(file.byteCount))
            guard !next.overflow else { throw VaultError.integrityFailure }
            offsets[file.identity] = position
            descriptors[file.identity] = file
            position = next.partialValue
        }
        let actualLength = try input.seekToEnd()
        guard actualLength == position else { throw VaultError.integrityFailure }

        func readArchiveFile(_ descriptor: VaultBackupFile) throws -> Data {
            try activeSession.requireActive()
            guard let offset = offsets[descriptor.identity] else { throw VaultError.integrityFailure }
            try input.seek(toOffset: offset)
            let bytes = try VaultBackupFormat.readExactly(input, count: descriptor.byteCount)
            guard VaultCrypto.digest(bytes) == descriptor.ciphertextHash else { throw VaultError.integrityFailure }
            return bytes
        }

        func expectedFile(_ reference: VaultBlobReference, id: UUID) throws -> VaultBackupFile {
            let identity = id.uuidString.lowercased() + "/" + reference.filename
            guard let file = descriptors[identity], file.ciphertextHash == reference.ciphertextHash else { throw VaultError.integrityFailure }
            return file
        }

        var plans: [UUID: [VaultBackupBlobPlan]] = [:]
        var expectedIdentities = Set<String>()
        for record in sourceCatalog.records {
            let itemKey = try unwrap(record, master: sourceMaster)
            var plan: [VaultBackupBlobPlan] = []
            for (reference, domain) in [(record.original, "original"), (record.thumbnail, "thumbnail"),
                                        (record.searchDocument, "search.document"), (record.videoManifest, "video.manifest")] {
                guard let reference else { continue }
                let file = try expectedFile(reference, id: record.item.id)
                plan.append(VaultBackupBlobPlan(file: file, domain: domain, sequence: 0))
            }
            if let reference = record.videoManifest {
                let encrypted = try readArchiveFile(expectedFile(reference, id: record.item.id))
                let decoded = try JSONDecoder().decode(VaultVideoManifest.self,
                    from: VaultCrypto.open(encrypted, key: itemKey, domain: "video.manifest", assetID: record.item.id))
                try decoded.validate(expectedID: record.item.id)
                for segment in decoded.segments {
                    let reference = VaultBlobReference(filename: VaultVideoWriter.segmentURL(directory: root, index: segment.sequence).lastPathComponent,
                        ciphertextHash: segment.ciphertextHash)
                    let file = try expectedFile(reference, id: record.item.id)
                    guard file.byteCount == segment.byteCount + 29 else { throw VaultError.integrityFailure }
                    plan.append(VaultBackupBlobPlan(file: file, domain: "video.segment", sequence: UInt64(segment.sequence)))
                }
            }
            for entry in plan {
                guard expectedIdentities.insert(entry.file.identity).inserted else { throw VaultError.integrityFailure }
            }
            plans[record.item.id] = plan
        }
        guard expectedIdentities == Set(descriptors.keys) else { throw VaultError.integrityFailure }
        var candidate = current
        let existingIDs = Set(current.records.map { $0.item.id })
        var createdIDs = Set<UUID>()
        do {
            for sourceRecord in sourceCatalog.records {
                try activeSession.requireActive()
                let id = sourceRecord.item.id
                let itemKey = try unwrap(sourceRecord, master: sourceMaster)
                let isNew = !existingIDs.contains(id)
                if !isNew {
                    guard let existing = current.records.first(where: { $0.item.id == id }),
                          existing.item.kind == sourceRecord.item.kind,
                          existing.item.contentHash == sourceRecord.item.contentHash else { throw VaultError.integrityFailure }
                } else {
                    guard !FileManager.default.fileExists(atPath: assetDirectory(id).path) else { throw VaultError.integrityFailure }
                    try ProtectedFiles.createDirectory(assetDirectory(id))
                    createdIDs.insert(id)
                }
                var videoHash = SHA256()
                var originalBytes: Int64 = 0
                for entry in plans[id] ?? [] {
                    let encrypted = try readArchiveFile(entry.file)
                    let plaintext = try VaultCrypto.open(encrypted, key: itemKey, domain: entry.domain, assetID: id, sequence: entry.sequence)
                    if entry.domain == "original" {
                        _ = try Self.inspectPhoto(plaintext)
                        guard VaultCrypto.digest(plaintext) == sourceRecord.item.contentHash else { throw VaultError.integrityFailure }
                        originalBytes = Int64(plaintext.count)
                    } else if entry.domain == "video.segment" {
                        videoHash.update(data: plaintext)
                        originalBytes += Int64(plaintext.count)
                    } else if entry.domain == "search.document" {
                        let document = try JSONDecoder().decode(SearchDocument.self, from: plaintext)
                        guard document.id == id else { throw VaultError.integrityFailure }
                    }
                    if isNew {
                        let reference = VaultBlobReference(filename: entry.file.filename, ciphertextHash: entry.file.ciphertextHash)
                        try ProtectedFiles.write(encrypted, to: ProtectedFiles.blobURL(reference, directory: assetDirectory(id)))
                    }
                }
                guard originalBytes == sourceRecord.item.byteCount else { throw VaultError.integrityFailure }
                if sourceRecord.item.kind == .video {
                    guard videoHash.finalize().map({ String(format: "%02x", $0) }).joined() == sourceRecord.item.contentHash else {
                        throw VaultError.integrityFailure
                    }
                }
                if isNew {
                    candidate.records.append(VaultRecord(item: sourceRecord.item,
                        wrappedKey: try VaultCrypto.seal(VaultCrypto.keyData(itemKey), key: master, domain: "item.key", assetID: id),
                        original: sourceRecord.original, thumbnail: sourceRecord.thumbnail,
                        videoManifest: sourceRecord.videoManifest, searchDocument: sourceRecord.searchDocument))
                }
            }
            let existingAlbums = Set(candidate.albums.map(\.id))
            candidate.albums += sourceCatalog.albums.filter { !existingAlbums.contains($0.id) }
            try activeSession.requireActive()
            try commit(candidate)
        } catch {
            if let catalog {
                let referenced = Set(catalog.records.map { $0.item.id })
                for id in createdIDs where !referenced.contains(id) { try? FileManager.default.removeItem(at: assetDirectory(id)) }
            }
            throw error
        }
    }
}
