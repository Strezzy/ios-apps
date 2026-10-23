import CryptoKit
import Foundation
import XCTest
@testable import Velvet

final class EncryptedVideoTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try ProtectedFiles.createDirectory(directory)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    private func fixture() throws -> (VaultVideoWriter, VaultVideoReader, VaultSession, SymmetricKey) {
        let key = VaultCrypto.randomKey()
        let session = VaultSession()
        let id = UUID()
        let writer = VaultVideoWriter(id: id, key: key, wrappedKey: Data(), directory: directory, session: session,
            fileExtension: "mp4", width: 1920, height: 1080)
        try writer.append(Data("INIT".utf8), isInitialization: true)
        try writer.append(Data("abcdef".utf8), isInitialization: false)
        try writer.append(Data("GHIJKLMN".utf8), isInitialization: false)
        let finished = try writer.prepareToCommit()
        let encrypted = try Data(contentsOf: directory.appendingPathComponent(finished.manifest.filename))
        let manifest = try JSONDecoder().decode(VaultVideoManifest.self,
            from: VaultCrypto.open(encrypted, key: key, domain: "video.manifest", assetID: id))
        writer.markCommitted()
        let reader = try VaultVideoReader(manifest: manifest, directory: directory, key: key, session: session)
        return (writer, reader, session, key)
    }

    func testAuthenticatedRandomAccessAcrossSegmentBoundaries() throws {
        let (_, reader, _, _) = try fixture()
        XCTAssertEqual(reader.totalLength, 18)
        XCTAssertEqual(try reader.read(offset: 2, length: 11), Data("ITabcdefGHI".utf8))
        XCTAssertEqual(try reader.read(offset: 17, length: 1), Data("N".utf8))
        XCTAssertEqual(try reader.read(offset: 18, length: 0), Data())
        XCTAssertThrowsError(try reader.read(offset: 17, length: 2))
        XCTAssertThrowsError(try reader.read(offset: -1, length: 1))
    }

    func testSegmentSwapTruncationAndRollbackAreRejected() throws {
        let (writer, reader, _, key) = try fixture()
        let segment = VaultVideoWriter.segmentURL(directory: directory, index: 1)
        let original = try Data(contentsOf: segment)
        let swapped = try Data(contentsOf: VaultVideoWriter.segmentURL(directory: directory, index: 2))
        try swapped.write(to: segment)
        XCTAssertThrowsError(try reader.read(offset: 4, length: 1))
        try Data(original.dropLast()).write(to: segment)
        XCTAssertThrowsError(try reader.read(offset: 4, length: 1))
        // Even an otherwise valid old ciphertext using the same key and sequence
        // is rejected when it is not the ciphertext committed by the manifest.
        let old = try VaultCrypto.seal(Data("abcdef".utf8), key: key, domain: "video.segment", assetID: writer.id, sequence: 1)
        try old.write(to: segment)
        XCTAssertThrowsError(try reader.read(offset: 4, length: 1))
    }

    func testWriterRejectsMissingOrRepeatedInitializationAndIncompleteRecording() throws {
        let writer = VaultVideoWriter(id: UUID(), key: VaultCrypto.randomKey(), wrappedKey: Data(), directory: directory,
            session: VaultSession(), fileExtension: "mp4", width: nil, height: nil)
        XCTAssertThrowsError(try writer.append(Data([1]), isInitialization: false))
        try writer.append(Data([1]), isInitialization: true)
        XCTAssertThrowsError(try writer.append(Data([2]), isInitialization: true))
        XCTAssertThrowsError(try writer.prepareToCommit())
        writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertThrowsError(try writer.append(Data([3]), isInitialization: false))
    }

    func testManifestRejectsDuplicatesMissingSequenceAndWrongTotal() throws {
        let id = UUID()
        let first = VaultVideoSegment(sequence: 0, byteCount: 4, isInitialization: true, ciphertextHash: String(repeating: "a", count: 64))
        let wrong = VaultVideoSegment(sequence: 2, byteCount: 4, isInitialization: false, ciphertextHash: String(repeating: "b", count: 64))
        XCTAssertThrowsError(try VaultVideoManifest(format: 1, assetID: id, segments: [first, wrong], totalByteCount: 8).validate(expectedID: id))
        XCTAssertThrowsError(try VaultVideoManifest(format: 1, assetID: id, segments: [first, first], totalByteCount: 8).validate(expectedID: id))
        let second = VaultVideoSegment(sequence: 1, byteCount: 4, isInitialization: false, ciphertextHash: String(repeating: "b", count: 64))
        XCTAssertThrowsError(try VaultVideoManifest(format: 1, assetID: id, segments: [first, second], totalByteCount: 9).validate(expectedID: id))
    }

    func testLockInvalidatesCachedReaderSynchronously() throws {
        let (_, reader, session, _) = try fixture()
        _ = try reader.read(offset: 4, length: 1)
        session.revoke()
        XCTAssertThrowsError(try reader.read(offset: 4, length: 1)) { XCTAssertEqual($0 as? VaultError, .locked) }
    }
}
