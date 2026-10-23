import CryptoKit
import Foundation

enum VaultCrypto {
    static let format: UInt8 = 1

    static func randomKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func keyData(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    static func key(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw VaultError.invalidKey }
        return SymmetricKey(data: data)
    }

    // A fixed field order, length prefixes, and big-endian integers avoid ambiguous
    // authenticated contexts. Every domain is separated and every item is bound.
    static func context(domain: String, assetID: UUID? = nil, sequence: UInt64 = 0) -> Data {
        var result = Data("app.velvet.vault".utf8)
        result.append(format)
        let domainBytes = Data(domain.utf8)
        appendInteger(UInt64(domainBytes.count), to: &result)
        result.append(domainBytes)
        let identifier = Data((assetID?.uuidString.lowercased() ?? "vault").utf8)
        appendInteger(UInt64(identifier.count), to: &result)
        result.append(identifier)
        appendInteger(sequence, to: &result)
        return result
    }

    static func seal(_ data: Data, key: SymmetricKey, domain: String, assetID: UUID? = nil, sequence: UInt64 = 0) throws -> Data {
        let box = try AES.GCM.seal(data, using: key, authenticating: context(domain: domain, assetID: assetID, sequence: sequence))
        guard let combined = box.combined else { throw VaultError.integrityFailure }
        return Data([format]) + combined
    }

    static func open(_ data: Data, key: SymmetricKey, domain: String, assetID: UUID? = nil, sequence: UInt64 = 0) throws -> Data {
        guard data.count >= 29, data.first == format else { throw VaultError.integrityFailure }
        do {
            let box = try AES.GCM.SealedBox(combined: data.dropFirst())
            return try AES.GCM.open(box, using: key, authenticating: context(domain: domain, assetID: assetID, sequence: sequence))
        } catch {
            throw VaultError.integrityFailure
        }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ data: Data, reference: VaultBlobReference) throws {
        guard digest(data) == reference.ciphertextHash else { throw VaultError.integrityFailure }
    }

    private static func appendInteger(_ value: UInt64, to data: inout Data) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }
}

protocol VaultRevocable: AnyObject {
    func revoke()
}

private final class WeakVaultResource {
    weak var value: (any VaultRevocable)?
    let itemID: UUID
    init(_ value: any VaultRevocable, itemID: UUID) {
        self.value = value
        self.itemID = itemID
    }
}

// Session revocation is synchronous. Recording and playback handles cannot outlive
// a successful lock merely because an actor has not processed its next message.
final class VaultSession: @unchecked Sendable {
    let id = UUID()
    private let mutex = NSLock()
    private var active = true
    private var resources: [WeakVaultResource] = []

    func requireActive() throws {
        mutex.lock()
        defer { mutex.unlock() }
        guard active else { throw VaultError.locked }
    }

    func register(_ resource: any VaultRevocable, itemID: UUID) {
        mutex.lock()
        let shouldRevoke = !active
        if active {
            resources.removeAll { $0.value == nil }
            resources.append(WeakVaultResource(resource, itemID: itemID))
        }
        mutex.unlock()
        if shouldRevoke { resource.revoke() }
    }

    func revokeItem(_ itemID: UUID) {
        mutex.lock()
        let live = resources.filter { $0.itemID == itemID }.compactMap(\.value)
        resources.removeAll { $0.itemID == itemID || $0.value == nil }
        mutex.unlock()
        for resource in live { resource.revoke() }
    }

    func revoke() {
        mutex.lock()
        active = false
        let live = resources.compactMap(\.value)
        resources.removeAll()
        mutex.unlock()
        for resource in live { resource.revoke() }
    }
}
