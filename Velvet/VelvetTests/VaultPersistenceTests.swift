import CoreGraphics
import Foundation
import ImageIO
import LocalAuthentication
import UniformTypeIdentifiers
import XCTest
@testable import Velvet

final class MemoryVaultKeyStore: VaultKeyStoring, @unchecked Sendable {
    var record: VaultKeyRecord?
    var updates = 0
    var failUpdateNumber: Int?

    func load(context: LAContext) throws -> VaultKeyRecord? { record }
    func create(_ record: VaultKeyRecord, context: LAContext) throws {
        guard self.record == nil else { throw VaultError.invalidKey }
        self.record = record
    }
    func update(_ record: VaultKeyRecord, context: LAContext) throws {
        updates += 1
        if failUpdateNumber == updates { throw VaultError.invalidKey }
        self.record = record
    }
}

final class VaultPersistenceTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temporaryRoot) }

    private func photo() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.05, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func engine(_ name: String, store: MemoryVaultKeyStore = MemoryVaultKeyStore()) -> VaultEngine {
        VaultEngine(root: temporaryRoot.appendingPathComponent(name, isDirectory: true), keyStore: store)
    }

    func testOriginalThumbnailMetadataAndCatalogRemainEncrypted() async throws {
        let vault = engine("primary")
        _ = try await vault.open(context: LAContext())
        let plaintext = try photo()
        let item = try await vault.savePhoto(data: plaintext, fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        try await vault.rename("CONFIDENTIAL_TEST_TITLE_937241", note: "PRIVATE_NOTE_481397", for: item.id)
        try await vault.saveSearchDocument(SearchDocument(id: item.id,
            labels: [SearchLabel(name: "PRIVATE_INDEX_LABEL_729381", confidence: 0.9)],
            recognizedText: "PRIVATE_RECOGNIZED_TEXT_471620", featurePrint: Data([9, 8, 7]), embedding: [0.1, 0.2]))
        let original = try await vault.original(for: item.id)
        let thumbnail = try await vault.thumbnail(for: item.id)
        XCTAssertEqual(original, plaintext)
        XCTAssertNotNil(thumbnail)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: temporaryRoot, includingPropertiesForKeys: [.isRegularFileKey]))
        for case let url as URL in files {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let bytes = try Data(contentsOf: url)
                XCTAssertNil(bytes.range(of: plaintext), url.lastPathComponent)
                XCTAssertNil(bytes.range(of: Data("CONFIDENTIAL_TEST_TITLE_937241".utf8)))
                XCTAssertNil(bytes.range(of: Data("PRIVATE_NOTE_481397".utf8)))
                XCTAssertNil(bytes.range(of: Data("PRIVATE_INDEX_LABEL_729381".utf8)))
                XCTAssertNil(bytes.range(of: Data("PRIVATE_RECOGNIZED_TEXT_471620".utf8)))
                XCTAssertTrue(url.lastPathComponent.hasSuffix(".vlt"))
            }
        }
        await vault.lock()
        do { _ = try await vault.original(for: item.id); XCTFail("Locked vault returned plaintext") }
        catch { XCTAssertEqual(error as? VaultError, .locked) }
    }

    func testLostKeyCannotInitializeOverExistingVault() async throws {
        let store = MemoryVaultKeyStore()
        let vault = engine("primary", store: store)
        _ = try await vault.open(context: LAContext())
        await vault.lock()
        store.record = nil
        do { _ = try await vault.open(context: LAContext()); XCTFail("Missing key was recreated") }
        catch { XCTAssertEqual(error as? VaultError, .missingKey) }
        XCTAssertNil(store.record)
    }

    func testCommittedCatalogueRollbackIsRejected() async throws {
        let store = MemoryVaultKeyStore()
        let vault = engine("primary", store: store)
        _ = try await vault.open(context: LAContext())
        let catalogURL = temporaryRoot.appendingPathComponent("primary/catalog.vlt")
        let previous = try Data(contentsOf: catalogURL)
        _ = try await vault.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        await vault.lock()
        try previous.write(to: catalogURL)
        do { _ = try await vault.open(context: LAContext()); XCTFail("Old catalogue was accepted") }
        catch { XCTAssertEqual(error as? VaultError, .rollbackDetected) }
    }

    func testReinstallWithRetainedKeychainCanRestoreExplicitBackup() async throws {
        let store = MemoryVaultKeyStore()
        let vault = engine("primary", store: store)
        _ = try await vault.open(context: LAContext())
        let item = try await vault.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        let backup = try await vault.createEncryptedBackup()
        let externalBackup = temporaryRoot.appendingPathComponent("user-saved.velvetbackup")
        try FileManager.default.copyItem(at: backup.fileURL, to: externalBackup)
        await vault.lock()
        try FileManager.default.removeItem(at: temporaryRoot.appendingPathComponent("primary"))
        let (empty, _) = try await vault.open(context: LAContext())
        XCTAssertTrue(empty.items.isEmpty)
        try await vault.restoreEncryptedBackup(from: externalBackup, recoveryKey: backup.recoveryKey)
        let restored = try await vault.original(for: item.id)
        XCTAssertEqual(restored, try photo())
    }

    func testMissingCatalogInExistingContainerDoesNotReinitialize() async throws {
        let vault = engine("primary")
        _ = try await vault.open(context: LAContext())
        let item = try await vault.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        await vault.lock()
        try FileManager.default.removeItem(at: temporaryRoot.appendingPathComponent("primary/catalog.vlt"))
        do { _ = try await vault.open(context: LAContext()); XCTFail("Partial vault was overwritten") }
        catch { XCTAssertEqual(error as? VaultError, .corruptCatalog) }
        let directory = temporaryRoot.appendingPathComponent("primary/assets/\(item.id.uuidString.lowercased())")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testInterruptedAnchorFinalizationRecoversNewAuthenticatedCommit() async throws {
        let store = MemoryVaultKeyStore()
        let vault = engine("primary", store: store)
        _ = try await vault.open(context: LAContext())
        store.failUpdateNumber = store.updates + 2
        do {
            _ = try await vault.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
            XCTFail("Injected Keychain failure did not occur")
        } catch { XCTAssertEqual(error as? VaultError, .transactionFailed) }
        let (recovered, _) = try await vault.open(context: LAContext())
        XCTAssertEqual(recovered.items.count, 1)
        XCTAssertEqual(store.record?.authorizedCatalogs.count, 1)
        let item = try XCTUnwrap(recovered.items.first)
        let data = try await vault.original(for: item.id)
        XCTAssertEqual(data, try photo())
    }

    func testEncryptedBackupRoundTripWrongKeyAndTruncation() async throws {
        let source = engine("source")
        _ = try await source.open(context: LAContext())
        let item = try await source.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        try await source.rename("Private backup title", note: "", for: item.id)
        let backup = try await source.createEncryptedBackup()
        let bytes = try Data(contentsOf: backup.fileURL)
        XCTAssertNil(bytes.range(of: Data("Private backup title".utf8)))
        XCTAssertNil(bytes.range(of: try photo()))
        let destination = engine("destination")
        _ = try await destination.open(context: LAContext())
        do {
            try await destination.restoreEncryptedBackup(from: backup.fileURL, recoveryKey: String(repeating: "a", count: 43))
            XCTFail("Wrong recovery key was accepted")
        } catch { XCTAssertEqual(error as? VaultError, .invalidRecoveryKey) }
        try await destination.restoreEncryptedBackup(from: backup.fileURL, recoveryKey: backup.recoveryKey)
        let restored = try await destination.snapshot()
        XCTAssertEqual(restored.items.first?.title, "Private backup title")
        let restoredOriginal = try await destination.original(for: item.id)
        XCTAssertEqual(restoredOriginal, try photo())
        // Restoring the same authenticated backup is idempotent.
        try await destination.restoreEncryptedBackup(from: backup.fileURL, recoveryKey: backup.recoveryKey)
        let repeated = try await destination.snapshot()
        XCTAssertEqual(repeated.items.count, 1)
        let truncated = temporaryRoot.appendingPathComponent("truncated.velvetbackup")
        try Data(bytes.dropLast()).write(to: truncated)
        do {
            try await destination.restoreEncryptedBackup(from: truncated, recoveryKey: backup.recoveryKey)
            XCTFail("Truncated backup was accepted")
        } catch { XCTAssertEqual(error as? VaultError, .integrityFailure) }
    }

    func testTrashRequiresExplicitDeletionAndDeletesAllManagedBlobs() async throws {
        let vault = engine("primary")
        _ = try await vault.open(context: LAContext())
        let item = try await vault.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        try await vault.saveSearchDocument(SearchDocument(id: item.id, recognizedText: "private"))
        do { try await vault.permanentlyDelete([item.id]); XCTFail("Untrashed item was deleted") }
        catch { XCTAssertEqual(error as? VaultError, .itemNotFound) }
        try await vault.moveToTrash([item.id])
        let trashed = try await vault.snapshot()
        XCTAssertTrue(trashed.items.first?.isTrashed == true)
        let searchable = try await vault.searchDocuments()
        XCTAssertTrue(searchable.isEmpty)
        try await vault.permanentlyDelete([item.id])
        let snapshot = try await vault.snapshot()
        XCTAssertTrue(snapshot.items.isEmpty)
        let directory = temporaryRoot.appendingPathComponent("primary/assets/\(item.id.uuidString.lowercased())")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testVideoBackupRestoresAuthenticatedSeeking() async throws {
        let source = engine("source")
        _ = try await source.open(context: LAContext())
        let writer = try await source.beginVideo(fileExtension: "mp4", width: 1920, height: 1080)
        try writer.append(Data("initialization".utf8), isInitialization: true)
        try writer.append(Data("first-media-segment".utf8), isInitialization: false)
        try writer.append(Data("second-media-segment".utf8), isInitialization: false)
        let item = try await source.finishVideo(writer, duration: 2, thumbnail: nil)
        let backup = try await source.createEncryptedBackup()
        let destination = engine("destination")
        _ = try await destination.open(context: LAContext())
        try await destination.restoreEncryptedBackup(from: backup.fileURL, recoveryKey: backup.recoveryKey)
        let reader = try await destination.videoReader(for: item.id)
        let expected = Data("initializationfirst-media-segmentsecond-media-segment".utf8)
        XCTAssertEqual(try reader.read(offset: 0, length: expected.count), expected)
        XCTAssertEqual(try reader.read(offset: 11, length: 12), expected.subdata(in: 11..<23))
    }

    func testTamperedBackupDoesNotPartiallyRestore() async throws {
        let source = engine("source")
        _ = try await source.open(context: LAContext())
        _ = try await source.savePhoto(data: photo(), fileExtension: "png", thumbnail: nil, width: nil, height: nil)
        let backup = try await source.createEncryptedBackup()
        var corrupted = try Data(contentsOf: backup.fileURL)
        corrupted[corrupted.count - 1] ^= 1
        let corruptURL = temporaryRoot.appendingPathComponent("corrupt.velvetbackup")
        try corrupted.write(to: corruptURL)
        let destination = engine("destination")
        _ = try await destination.open(context: LAContext())
        do {
            try await destination.restoreEncryptedBackup(from: corruptURL, recoveryKey: backup.recoveryKey)
            XCTFail("Corrupted backup was accepted")
        } catch { XCTAssertEqual(error as? VaultError, .integrityFailure) }
        let snapshot = try await destination.snapshot()
        XCTAssertTrue(snapshot.items.isEmpty)
        let assets = temporaryRoot.appendingPathComponent("destination/assets")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: assets.path).isEmpty)
    }
}
