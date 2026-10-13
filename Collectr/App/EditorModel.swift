import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    @Published var image: UIImage?
    @Published var depth: UIImage?
    @Published var palette = RGB.defaults
    @Published var edits = PhotoEdits()
    @Published var title = ""
    @Published var rarity: Rarity = .original
    @Published var editionCount = 1
    @Published var depthEnabled = true
    @Published var depthAmount = 0.45
    @Published var working = false
    @Published var depthWorking = false
    @Published var sealing = false
    @Published var error: String?
    @Published var depthError: String?
    @Published var showPicker = false
    @Published var showSeal = false
    private var source: Data?
    private var sourceIdentifier = ""
    private var generation = UUID()
    private var work: Task<Void, Never>?
    private var editWork: Task<Void, Never>?
    private let pipeline = PhotoPipeline()

    func pick() { Task { do { try await PhotoLibraryGate.authorize(); showPicker = true } catch { self.error = error.localizedDescription } } }
    func importPhoto(data: Data, identifier: String) {
        source = data; sourceIdentifier = identifier
        edits = PhotoEdits(); title = ""; depth = nil; depthError = nil
        render()
    }
    func scheduleRender() {
        working = true
        editWork?.cancel()
        editWork = Task { try? await Task.sleep(for: .milliseconds(180)); guard !Task.isCancelled else { return }; render() }
    }
    func render() {
        guard let source else { return }
        work?.cancel(); let token = UUID(); generation = token
        working = true; depthWorking = depthEnabled; depth = nil; depthError = nil
        let edits = edits; let pipeline = pipeline
        work = Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) { try pipeline.render(source, edits: edits) }.value
                guard generation == token, !Task.isCancelled else { return }
                self.image = image; self.palette = PhotoPipeline.palette(image); working = false
                if depthEnabled { await generateDepth(image, token: token) } else { depthWorking = false }
            } catch { guard generation == token else { return }; working = false; depthWorking = false; self.error = error.localizedDescription }
        }
    }
    func updateDepth() {
        if !depthEnabled { depthWorking = false; return }
        guard let image, depth == nil, !depthWorking else { return }
        let token = generation
        work = Task { await generateDepth(image, token: token) }
    }
    private func generateDepth(_ image: UIImage, token: UUID) async {
        depthWorking = true; let pipeline = pipeline
        do {
            let map = try await Task.detached(priority: .userInitiated) { try await pipeline.depth(image) }.value
            guard generation == token, !Task.isCancelled else { return }
            depth = map; depthWorking = false
        } catch { guard generation == token else { return }; depthWorking = false; depthError = "Depth could not be added. Try again, or turn Depth off to keep a flat card. \(error.localizedDescription)" }
    }
    var canSeal: Bool { image != nil && !working && !depthWorking && (!depthEnabled || depth != nil) && !sealing }
    func seal(store: CollectionStore) async -> CollectorCard? {
        guard canSeal, let image, let bytes = image.jpegData(compressionQuality: 0.94) else { return nil }
        sealing = true; defer { sealing = false }
        do {
            let depthBytes = depthEnabled ? depth?.pngData() : nil
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let draft = DraftRecord(editionID: UUID(), title: name.isEmpty ? "Untitled moment" : String(name.prefix(80)), rarity: rarity, count: editionCount, depthAmount: depthEnabled ? depthAmount : 0, palette: palette, imageHash: CollectionStore.hash(bytes), depthHash: depthBytes.map(CollectionStore.hash), sourceIdentifier: sourceIdentifier, deletionConfirmed: false)
            try store.saveDraft(draft, photo: bytes, depth: depthBytes)
            try await PhotoLibraryGate.deleteOriginal(identifier: sourceIdentifier)
            try store.confirmDeletion()
            let result = try store.finalizeDraft()
            reset(); return result
        } catch { self.error = error.localizedDescription; return nil }
    }
    func resume(store: CollectionStore) async -> CollectorCard? {
        guard let draft = store.draft else { return nil }
        sealing = true; defer { sealing = false }
        do {
            if !draft.deletionConfirmed { try await PhotoLibraryGate.deleteOriginal(identifier: draft.sourceIdentifier); try store.confirmDeletion() }
            return try store.finalizeDraft()
        } catch { self.error = error.localizedDescription; return nil }
    }
    func reset() { work?.cancel(); generation = UUID(); source = nil; image = nil; depth = nil; title = ""; edits = PhotoEdits(); working = false; depthWorking = false; depthError = nil }
}

struct LibraryPicker: UIViewControllerRepresentable {
    var onPick: (Data, String) -> Void
    var onError: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared()); config.filter = .images; config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPicker
        init(_ parent: LibraryPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss(); guard let result = results.first else { return }
            guard let id = result.assetIdentifier else { parent.onError("The photo's original is not accessible. Allow full photo access in Settings and choose it again."); return }
            result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data,error in
                DispatchQueue.main.async { if let data { self.parent.onPick(data,id) } else { self.parent.onError(error?.localizedDescription ?? "This photo could not be imported.") } }
            }
        }
    }
}
