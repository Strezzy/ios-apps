import Combine
import Foundation
import LocalAuthentication

@MainActor
final class VaultStore: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var isUnlocking = false
    @Published private(set) var items: [VaultItem] = []
    @Published private(set) var albums: [VaultAlbum] = []
    private let engine: VaultEngine
    private var session: VaultSession?
    private var authenticationContext: LAContext?
    private var generation: UInt64 = 0

    init(engine: VaultEngine = VaultEngine()) { self.engine = engine }

    func unlock() async throws {
        if isUnlocked { return }
        guard !isUnlocking else { return }
        isUnlocking = true
        generation &+= 1
        let expected = generation
        let context = LAContext()
        context.localizedFallbackTitle = "Use device passcode"
        context.localizedCancelTitle = "Cancel"
        authenticationContext = context
        defer {
            if generation == expected { isUnlocking = false }
        }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw VaultError.authenticationUnavailable
        }
        let authenticated = try await context.evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: "Unlock your private Velvet vault")
        guard authenticated, generation == expected else { throw VaultError.operationCancelled }
        let (snapshot, activeSession) = try await engine.open(context: context)
        guard generation == expected else {
            activeSession.revoke()
            await engine.lock(matching: activeSession.id)
            throw VaultError.operationCancelled
        }
        session = activeSession
        items = snapshot.items
        albums = snapshot.albums
        isUnlocked = true
    }

    func lock() {
        generation &+= 1
        let previousID = session?.id
        session?.revoke()
        session = nil
        authenticationContext?.invalidate()
        authenticationContext = nil
        isUnlocked = false
        isUnlocking = false
        items.removeAll()
        albums.removeAll()
        if let previousID {
            Task { await engine.lock(matching: previousID) }
        }
    }

    func savePhoto(data: Data, fileExtension: String, thumbnail: Data? = nil, width: Int? = nil, height: Int? = nil) async throws -> VaultItem {
        try await perform(refresh: true) {
            try await $0.savePhoto(data: data, fileExtension: fileExtension, thumbnail: thumbnail, width: width, height: height)
        }
    }

    func thumbnail(for id: UUID) async throws -> Data? {
        try await perform { try await $0.thumbnail(for: id) }
    }

    func original(for id: UUID) async throws -> Data {
        try await perform { try await $0.original(for: id) }
    }

    func beginVideo(fileExtension: String = "mp4", width: Int? = nil, height: Int? = nil) async throws -> VaultVideoWriter {
        try await perform { try await $0.beginVideo(fileExtension: fileExtension, width: width, height: height) }
    }

    func finishVideo(_ writer: VaultVideoWriter, duration: Double, thumbnail: Data? = nil) async throws -> VaultItem {
        try await perform(refresh: true) { try await $0.finishVideo(writer, duration: duration, thumbnail: thumbnail) }
    }

    func videoReader(for id: UUID) async throws -> VaultVideoReader {
        try await perform { try await $0.videoReader(for: id) }
    }

    func setFavorite(_ favorite: Bool, for ids: Set<UUID>) async throws {
        try await perform(refresh: true) { try await $0.setFavorite(favorite, for: ids) }
    }

    func setFavorite(_ favorite: Bool, for id: UUID) async throws {
        try await setFavorite(favorite, for: [id])
    }

    func rename(_ title: String, note: String, for id: UUID) async throws {
        try await perform(refresh: true) { try await $0.rename(title, note: note, for: id) }
    }

    @discardableResult
    func createAlbum(name: String) async throws -> VaultAlbum {
        try await perform(refresh: true) { try await $0.createAlbum(name: name) }
    }

    func deleteAlbum(_ id: UUID) async throws {
        try await perform(refresh: true) { try await $0.deleteAlbum(id) }
    }

    func setAlbums(_ albums: Set<UUID>, for ids: Set<UUID>) async throws {
        try await perform(refresh: true) { try await $0.setAlbums(albums, for: ids) }
    }

    func setAlbums(_ albums: Set<UUID>, for id: UUID) async throws {
        try await setAlbums(albums, for: [id])
    }

    func moveToTrash(_ ids: Set<UUID>) async throws {
        try await perform(refresh: true) { try await $0.moveToTrash(ids) }
    }

    func moveToTrash(_ id: UUID) async throws { try await moveToTrash([id]) }

    func restoreFromTrash(_ ids: Set<UUID>) async throws {
        try await perform(refresh: true) { try await $0.restoreFromTrash(ids) }
    }

    func restoreFromTrash(_ id: UUID) async throws { try await restoreFromTrash([id]) }

    func permanentlyDelete(_ ids: Set<UUID>) async throws {
        try await perform(refresh: true) { try await $0.permanentlyDelete(ids) }
    }

    func permanentlyDelete(_ id: UUID) async throws { try await permanentlyDelete([id]) }

    func emptyTrash() async throws {
        try await perform(refresh: true) { try await $0.emptyTrash() }
    }

    func duplicateGroups() -> [[VaultItem]] {
        Dictionary(grouping: items.filter { !$0.isTrashed }, by: \.contentHash)
            .values.filter { $0.count > 1 }.map { $0.sorted { $0.createdAt > $1.createdAt } }
            .sorted { ($0.first?.createdAt ?? .distantPast) > ($1.first?.createdAt ?? .distantPast) }
    }

    func saveSearchDocument(_ document: SearchDocument) async throws {
        try await perform { try await $0.saveSearchDocument(document) }
    }

    func searchDocuments() async throws -> [SearchDocument] {
        try await perform { try await $0.searchDocuments() }
    }

    func createEncryptedBackup() async throws -> VaultBackupExport {
        try await perform { try await $0.createEncryptedBackup() }
    }

    func restoreEncryptedBackup(from url: URL, recoveryKey: String) async throws {
        try await perform(refresh: true) { try await $0.restoreEncryptedBackup(from: url, recoveryKey: recoveryKey) }
    }

    private func perform<T>(refresh: Bool = false, _ operation: (VaultEngine) async throws -> T) async throws -> T {
        guard isUnlocked, let session else { throw VaultError.locked }
        let expected = generation
        try session.requireActive()
        do {
            let result = try await operation(engine)
            guard generation == expected else { throw VaultError.operationCancelled }
            try session.requireActive()
            if refresh {
                let snapshot = try await engine.snapshot()
                guard generation == expected else { throw VaultError.operationCancelled }
                try session.requireActive()
                items = snapshot.items
                albums = snapshot.albums
            }
            return result
        } catch {
            if generation == expected,
               let failure = error as? VaultError,
               failure == .locked || failure == .transactionFailed {
                lock()
            }
            throw error
        }
    }
}
