import Foundation

enum ProtectedFiles {
    static func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        try protect(url)
    }

    static func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    static func write(_ ciphertext: Data, to url: URL) throws {
        try requireCapacity(for: ciphertext.count, at: url.deletingLastPathComponent())
        // Atomic temporary files contain ciphertext only, with Complete protection
        // applied at their creation, before the final rename.
        try ciphertext.write(to: url, options: [.atomic, .completeFileProtection])
        try protect(url)
    }

    static func requireCapacity(for count: Int, at directory: URL) throws {
        if let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           capacity < Int64(count) + 8 * 1_024 * 1_024 {
            throw VaultError.storageFull
        }
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= maximumBytes else { throw VaultError.integrityFailure }
        return try Data(contentsOf: url, options: [])
    }

    static func blobURL(_ reference: VaultBlobReference, directory: URL) throws -> URL {
        guard !reference.filename.isEmpty,
              reference.filename.count <= 100,
              reference.filename.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }),
              !reference.filename.hasPrefix("."),
              reference.filename.hasSuffix(".vlt") else { throw VaultError.corruptCatalog }
        return directory.appendingPathComponent(reference.filename, isDirectory: false)
    }
}
