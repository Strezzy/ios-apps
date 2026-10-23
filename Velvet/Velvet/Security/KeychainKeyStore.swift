import Foundation
import LocalAuthentication
import Security

struct VaultKeyRecord: Codable {
    var format = 1
    let masterKey: Data
    // Two hashes are allowed only during the bounded catalogue commit window.
    // After a successful commit, stale catalogue snapshots are rejected.
    var authorizedCatalogs: [String]
}

protocol VaultKeyStoring: Sendable {
    func load(context: LAContext) throws -> VaultKeyRecord?
    func create(_ record: VaultKeyRecord, context: LAContext) throws
    func update(_ record: VaultKeyRecord, context: LAContext) throws
}

struct KeychainKeyStore: VaultKeyStoring {
    private let service = "app.velvet.private-vault.v1"
    private let account = "master-and-catalog-integrity"

    private func query(context: LAContext) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseAuthenticationContext as String: context,
         kSecAttrSynchronizable as String: false]
    }

    func load(context: LAContext) throws -> VaultKeyRecord? {
        var request = query(context: context)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.invalidKey }
        guard let record = try? JSONDecoder().decode(VaultKeyRecord.self, from: data),
              record.format == 1, record.masterKey.count == 32,
              (1...2).contains(record.authorizedCatalogs.count) else { throw VaultError.invalidKey }
        return record
    }

    func create(_ record: VaultKeyRecord, context: LAContext) throws {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &accessError) else {
            throw VaultError.authenticationUnavailable
        }
        var request = query(context: context)
        request[kSecAttrAccessControl as String] = access
        request[kSecValueData as String] = try JSONEncoder().encode(record)
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.invalidKey }
    }

    func update(_ record: VaultKeyRecord, context: LAContext) throws {
        let attributes = [kSecValueData as String: try JSONEncoder().encode(record)]
        let status = SecItemUpdate(query(context: context) as CFDictionary, attributes as CFDictionary)
        guard status == errSecSuccess else { throw VaultError.invalidKey }
    }
}
