import UniformTypeIdentifiers

/// File providers may advertise a playable movie as generic data. Let the user
/// select the file, then use ClipInfo.inspect to validate its actual video track.
/// This does not add codecs or relax the existing SDR/resolution restrictions.
enum VideoFileImportPolicy {
    static let allowedContentTypes: [UTType] = [.item]
}
