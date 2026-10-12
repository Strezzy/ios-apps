import Foundation

struct CleanOptions: Sendable {
    enum PhotoFormat: String, CaseIterable, Sendable { case original = "Keep format", jpeg = "JPEG", png = "PNG" }
    var photoFormat: PhotoFormat = .original
    var freshFingerprint = true
    var maxPhotoPixels = 64_000_000
}

struct Audit: Sendable {
    var fields: [String]
    var mediaDescription: String
}

struct CleanResult: Identifiable, Sendable {
    let id = UUID()
    let output: URL
    let originalHash: String
    let cleanedHash: String
    let before: Audit
    let after: Audit
    let notes: [String]
    var hashChanged: Bool { originalHash != cleanedHash }
}

enum RinseError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum MediaKind: String, Sendable {
    case photo, video
    static func of(_ url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif": return .photo
        case "mov", "mp4", "m4v": return .video
        default: return nil
        }
    }
}

enum Workspace {
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("RinsePrivate", isDirectory: true)
    static func prepare(reset: Bool = false) throws {
        if reset, FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var url = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func destination(extension suffix: String) -> URL {
        root.appendingPathComponent("Rinse-" + UUID().uuidString.lowercased()).appendingPathExtension(suffix)
    }
    static func checkSpace(for bytes: Int64) throws {
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = values.volumeAvailableCapacityForImportantUsage, free < bytes + 100_000_000 {
            throw RinseError.message("Not enough free storage. Free some space and try again.")
        }
    }
    static func stage(_ source: URL) throws -> URL {
        try prepare()
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw RinseError.message("Choose a regular media file, not a link or folder shortcut.")
        }
        try checkSpace(for: Int64(values.fileSize ?? 0) * 2)
        let destination = destination(extension: source.pathExtension.lowercased())
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
