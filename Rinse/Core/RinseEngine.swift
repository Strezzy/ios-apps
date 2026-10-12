import Foundation
import ImageIO

enum RinseEngine {
    static func clean(_ input: URL, options: CleanOptions = CleanOptions(),
                      progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> CleanResult {
        try Workspace.prepare()
        try Task.checkCancellation()
        guard let kind = MediaKind.of(input) else { throw RinseError.message("This file type is not supported.") }
        let originalHash = try Fingerprint.sha256(input)
        let before: Audit
        let output: URL
        var notes: [String]
        progress(0.02)
        switch kind {
        case .photo:
            before = try PhotoCleaner.audit(input)
            (output, notes) = try autoreleasepool { try PhotoCleaner.rebuild(input, options: options) }
        case .video:
            before = try await VideoCleaner.audit(input)
            (output, notes) = try await VideoCleaner.rebuild(input) { progress(0.03 + $0 * 0.87) }
        }
        do {
            try Task.checkCancellation()
            progress(0.92)
            if options.freshFingerprint {
                try Fingerprint.randomize(output)
                notes.append("Fresh random container padding changes the byte fingerprint. It contains no source identity and does not prevent visual or audio matching.")
            }
            let after: Audit
            if kind == .photo {
                after = try PhotoCleaner.audit(output)
                guard let source = CGImageSourceCreateWithURL(output as CFURL, nil),
                      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
                    throw RinseError.message("The cleaned photo could not be decoded during verification.")
                }
            } else { after = try await VideoCleaner.audit(output) }
            guard after.fields.isEmpty else {
                throw RinseError.message("Verification found remaining metadata. This output was blocked and deleted; your original is unchanged.")
            }
            let cleanedHash = try Fingerprint.sha256(output)
            if options.freshFingerprint && originalHash == cleanedHash {
                throw RinseError.message("The new fingerprint could not be confirmed. No copy was exported.")
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: output.path)
            progress(1)
            return CleanResult(output: output, originalHash: originalHash, cleanedHash: cleanedHash,
                               before: before, after: after, notes: notes)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
