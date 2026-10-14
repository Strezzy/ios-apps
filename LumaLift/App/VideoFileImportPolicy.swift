import Foundation
import UniformTypeIdentifiers

/// File providers may advertise a playable movie as generic data. Let the user
/// select the file, then use ClipInfo.inspect to validate its actual video track.
/// This does not add codecs or relax the existing SDR/resolution restrictions.
enum VideoFileImportPolicy {
    static let allowedContentTypes: [UTType] = [.item]

    /// AVFoundation can reject an otherwise valid MOV/MP4 when its name has an
    /// unknown extension. Give only the private copy a matching container hint.
    /// A recognizable header is not validation: ClipInfo.inspect still decides
    /// whether the file contains a supported, unprotected video track.
    static func stagingFilename(for source: URL, originalName: String) throws -> String {
        let ext = (originalName as NSString).pathExtension.lowercased()
        if ["mov", "mp4", "m4v"].contains(ext) { return originalName }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 16) ?? Data()
        guard header.count >= 12 else { return originalName }
        let atom = String(data: header.subdata(in: 4..<8), encoding: .ascii)
        let suffix: String
        if atom == "ftyp" {
            let brand = String(data: header.subdata(in: 8..<12), encoding: .ascii)
            suffix = brand == "qt  " ? "mov" : "mp4"
        } else if ["moov", "mdat", "wide", "free", "skip"].contains(atom ?? "") {
            suffix = "mov"
        } else {
            return originalName
        }
        return originalName + "." + suffix
    }
}
