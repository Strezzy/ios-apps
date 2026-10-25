import PhotosUI
import SwiftUI

struct OrbitPhotoPicker: UIViewControllerRepresentable {
    let onSelect: (NSItemProvider) -> Void
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .videos
        configuration.selectionLimit = 1
        // Compatible representations may flatten MV-HEVC. Request the original
        // current movie representation so both recorded eyes are retained.
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: OrbitPhotoPicker
        init(parent: OrbitPhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.onDismiss()
            if let provider = results.first?.itemProvider { parent.onSelect(provider) }
        }
    }
}
