import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// File representations are copied inside the provider's callback, before its
/// temporary URL expires. Providers can be system cloud providers; Rinse has no
/// networking client of its own.
enum ProviderImporter {
    static func copy(_ provider: NSItemProvider) async throws -> URL {
        let candidates = provider.registeredTypeIdentifiers.compactMap { identifier -> (String, UTType)? in
            guard let type = UTType(identifier), type.conforms(to: .image) || type.conforms(to: .movie) else { return nil }
            return (identifier, type)
        }
        guard let (identifier, type) = candidates.first else { throw RinseError.message("The shared item is not a photo or video.") }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: identifier) { source, error in
                guard let source else {
                    continuation.resume(throwing: error ?? RinseError.message("The media is unavailable. Download it to your iPhone in Photos or Files first.")); return
                }
                do {
                    let staged = try Workspace.stage(source)
                    if MediaKind.of(staged) != nil { continuation.resume(returning: staged); return }
                    guard let suffix = type.preferredFilenameExtension else {
                        try? FileManager.default.removeItem(at: staged)
                        throw RinseError.message("The provider supplied an unsupported file format.")
                    }
                    let renamed = Workspace.destination(extension: suffix)
                    try FileManager.default.moveItem(at: staged, to: renamed)
                    continuation.resume(returning: renamed)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

struct PhotoImporter: UIViewControllerRepresentable {
    let selected: ([NSItemProvider]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0
        configuration.filter = .any(of: [.images, .videos])
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let selected: ([NSItemProvider]) -> Void
        init(selected: @escaping ([NSItemProvider]) -> Void) { self.selected = selected }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            selected(results.map(\.itemProvider))
        }
    }
}

struct FileImporter: UIViewControllerRepresentable {
    var folder: Bool
    let selected: ([URL]) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: folder ? [.folder] : [.image, .movie], asCopy: false)
        picker.allowsMultipleSelection = !folder
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(selected: selected) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let selected: ([URL]) -> Void
        init(selected: @escaping ([URL]) -> Void) { self.selected = selected }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { selected(urls) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { selected([]) }
    }
}

struct ExportSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
