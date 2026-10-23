import CryptoKit
import XCTest
@testable import Velvet

final class VaultCryptoTests: XCTestCase {
    func testEmptyAuthenticatedPayloadRoundTrip() throws {
        let key = VaultCrypto.randomKey()
        let sealed = try VaultCrypto.seal(Data(), key: key, domain: "empty.test")
        XCTAssertEqual(sealed.count, 29)
        XCTAssertEqual(try VaultCrypto.open(sealed, key: key, domain: "empty.test"), Data())
    }

    func testRandomNoncesAndRoundTrip() throws {
        let key = VaultCrypto.randomKey()
        let id = UUID()
        let plaintext = Data("private media bytes".utf8)
        let first = try VaultCrypto.seal(plaintext, key: key, domain: "original", assetID: id)
        let second = try VaultCrypto.seal(plaintext, key: key, domain: "original", assetID: id)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try VaultCrypto.open(first, key: key, domain: "original", assetID: id), plaintext)
        XCTAssertNil(first.range(of: plaintext))
    }

    func testTamperingTruncationAndWrongKeyFailClosed() throws {
        let key = VaultCrypto.randomKey()
        let data = try VaultCrypto.seal(Data(repeating: 42, count: 100), key: key, domain: "thumbnail")
        for index in [0, 1, 13, data.count - 1] {
            var modified = data
            modified[index] ^= 1
            XCTAssertThrowsError(try VaultCrypto.open(modified, key: key, domain: "thumbnail"))
        }
        for length in [0, 1, 16, data.count - 1] {
            XCTAssertThrowsError(try VaultCrypto.open(Data(data.prefix(length)), key: key, domain: "thumbnail"))
        }
        XCTAssertThrowsError(try VaultCrypto.open(data, key: VaultCrypto.randomKey(), domain: "thumbnail"))
    }

    func testDomainAssetAndSequenceAreAuthenticated() throws {
        let key = VaultCrypto.randomKey()
        let id = UUID()
        let sealed = try VaultCrypto.seal(Data("segment".utf8), key: key, domain: "video.segment", assetID: id, sequence: 7)
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key, domain: "original", assetID: id, sequence: 7))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key, domain: "video.segment", assetID: UUID(), sequence: 7))
        XCTAssertThrowsError(try VaultCrypto.open(sealed, key: key, domain: "video.segment", assetID: id, sequence: 8))
        XCTAssertEqual(try VaultCrypto.open(sealed, key: key, domain: "video.segment", assetID: id, sequence: 7), Data("segment".utf8))
    }

    func testItemKeysCannotBeMovedBetweenRecords() throws {
        let master = VaultCrypto.randomKey()
        let itemKey = VaultCrypto.randomKey()
        let id = UUID()
        let wrapped = try VaultCrypto.seal(VaultCrypto.keyData(itemKey), key: master, domain: "item.key", assetID: id)
        XCTAssertEqual(wrapped.count, 61)
        XCTAssertThrowsError(try VaultCrypto.open(wrapped, key: master, domain: "item.key", assetID: UUID()))
    }

    func testRecoveryKeysAndBackupHeaderAreStrict() throws {
        let key = VaultCrypto.randomKey()
        let encoded = VaultBackupFormat.encodeKey(key)
        XCTAssertEqual(encoded.count, 43)
        XCTAssertEqual(VaultCrypto.keyData(try VaultBackupFormat.decodeKey(encoded)), VaultCrypto.keyData(key))
        XCTAssertThrowsError(try VaultBackupFormat.decodeKey("weak password"))
        XCTAssertEqual(try VaultBackupFormat.manifestLength(from: VaultBackupFormat.header(manifestLength: 1_000)), 1_000)
        XCTAssertThrowsError(try VaultBackupFormat.manifestLength(from: Data(repeating: 0, count: 16)))
    }
}
