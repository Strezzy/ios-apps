import CryptoKit
import Foundation

struct VaultBackupExport: Identifiable, Sendable {
    let id = UUID()
    let fileURL: URL
    let recoveryKey: String
}

struct VaultBackupFile: Codable, Sendable {
    let assetID: UUID
    let filename: String
    let byteCount: Int
    let ciphertextHash: String

    var identity: String { assetID.uuidString.lowercased() + "/" + filename }
}

struct VaultBackupManifest: Codable {
    let format: Int
    let sourceMasterKey: Data
    let encryptedCatalog: Data
    let files: [VaultBackupFile]
}

struct VaultBackupBlobPlan {
    let file: VaultBackupFile
    let domain: String
    let sequence: UInt64
}

enum VaultBackupFormat {
    static let magic = Data("VLTBK001".utf8)
    static let maximumManifestBytes = 64 * 1_024 * 1_024

    static func header(manifestLength: Int) -> Data {
        var length = UInt64(manifestLength).bigEndian
        var result = magic
        withUnsafeBytes(of: &length) { result.append(contentsOf: $0) }
        return result
    }

    static func manifestLength(from header: Data) throws -> Int {
        guard header.count == 16, header.prefix(8) == magic else { throw VaultError.invalidRecoveryKey }
        let length = header.suffix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard length >= 30, length <= UInt64(maximumManifestBytes) else { throw VaultError.backupTooLarge }
        return Int(length)
    }

    static func encodeKey(_ key: SymmetricKey) -> String {
        VaultCrypto.keyData(key).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeKey(_ value: String) throws -> SymmetricKey {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 43, trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw VaultError.invalidRecoveryKey
        }
        let base64 = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + "="
        guard let bytes = Data(base64Encoded: base64), bytes.count == 32 else { throw VaultError.invalidRecoveryKey }
        return SymmetricKey(data: bytes)
    }

    static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0 else { throw VaultError.integrityFailure }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard let part = try handle.read(upToCount: min(count - result.count, 1_024 * 1_024)), !part.isEmpty else {
                throw VaultError.integrityFailure
            }
            result.append(part)
        }
        return result
    }
}
