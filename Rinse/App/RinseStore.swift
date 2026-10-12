import Foundation
import Combine
import Photos

struct QueueItem: Identifiable {
    enum State { case waiting, cleaning, clean, blocked, cancelled }
    let id = UUID()
    let input: URL
    let name: String
    let kind: MediaKind
    var state: State = .waiting
    var fraction = 0.0
    var result: CleanResult?
    var error: String?
}

@MainActor final class RinseStore: ObservableObject {
    @Published var items: [QueueItem] = []
    @Published var busy = false
    @Published var importing = false
    @Published var message: String?
    @Published var options = CleanOptions()
    private var operation: Task<Void, Never>?
    var results: [CleanResult] { items.compactMap(\.result) }
    var waiting: Int { items.filter { $0.state == .waiting }.count }
    init(reset: Bool = true) {
        do { try Workspace.prepare(reset: reset) } catch { message = "Private temporary storage could not be prepared." }
    }
    func add(_ url: URL, name: String? = nil) {
        guard items.count < 500, let kind = MediaKind.of(url) else {
            try? FileManager.default.removeItem(at: url)
            message = "Use JPEG, PNG, HEIC, MOV or MP4, with at most 500 items per batch."; return
        }
        items.append(QueueItem(input: url, name: name ?? "\(kind == .photo ? "Photo" : "Video") \(items.count + 1)", kind: kind))
    }
    func importProviders(_ providers: [NSItemProvider]) {
        guard !busy, !importing, !providers.isEmpty else { return }
        importing = true
        Task {
            var failed = 0
            for provider in providers.prefix(max(0, 500 - items.count)) {
                do { add(try await ProviderImporter.copy(provider), name: provider.suggestedName) }
                catch { failed += 1 }
            }
            importing = false
            if failed > 0 { message = "\(failed) item(s) could not be imported. They may be unsupported or not stored locally." }
            if providers.count > 500 { message = "Only the first 500 items were considered. Import another batch after clearing this one." }
        }
    }
    func importFiles(_ roots: [URL]) {
        guard !busy, !importing, !roots.isEmpty else { return }
        importing = true
        let remaining = 500 - items.count
        Task {
            let batch = await Task.detached(priority: .userInitiated) { () -> ([(URL, String)], Int, Bool) in
                var staged: [(URL, String)] = []
                var skipped = 0
                var capped = false
                func copy(_ url: URL) {
                    guard staged.count < remaining else { capped = true; return }
                    guard MediaKind.of(url) != nil else { skipped += 1; return }
                    do { staged.append((try Workspace.stage(url), url.lastPathComponent)) }
                    catch { skipped += 1 }
                }
                for root in roots {
                    let accessed = root.startAccessingSecurityScopedResource()
                    defer { if accessed { root.stopAccessingSecurityScopedResource() } }
                    guard let values = try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]), values.isSymbolicLink != true else { skipped += 1; continue }
                    if values.isDirectory == true {
                        let enumerator = FileManager.default.enumerator(at: root,
                            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
                            options: [.skipsHiddenFiles, .skipsPackageDescendants],
                            errorHandler: { _, _ in skipped += 1; return true })
                        while let url = enumerator?.nextObject() as? URL {
                            if staged.count >= remaining { capped = true; break }
                            guard let value = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { skipped += 1; continue }
                            if value.isSymbolicLink == true { enumerator?.skipDescendants(); skipped += 1; continue }
                            if value.isRegularFile == true { copy(url) }
                        }
                    } else { copy(root) }
                }
                return (staged, skipped, capped)
            }.value
            for (url, name) in batch.0 { add(url, name: name) }
            importing = false
            if batch.1 > 0 || batch.2 {
                message = "Imported \(batch.0.count) item(s). \(batch.1) unsupported or unavailable item(s) skipped.\(batch.2 ? " The 500-item limit was reached." : "")"
            }
        }
    }
    func clean() {
        guard !busy, !importing, waiting > 0 else { return }
        busy = true
        let jobs = items.filter { $0.state == .waiting }
        let configuration = options
        operation = Task.detached(priority: .userInitiated) { [weak self] in
            for job in jobs {
                if Task.isCancelled { break }
                await self?.change(job.id, state: .cleaning)
                do {
                    let result = try await RinseEngine.clean(job.input, options: configuration) { fraction in
                        Task { @MainActor [weak self] in self?.progress(job.id, fraction: fraction) }
                    }
                    await self?.finish(job.id, result: result)
                } catch is CancellationError { await self?.change(job.id, state: .cancelled) }
                catch { await self?.change(job.id, state: .blocked, error: error.localizedDescription) }
            }
            await self?.ended()
        }
    }
    private func progress(_ id: UUID, fraction: Double) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].fraction = fraction
    }
    private func change(_ id: UUID, state: QueueItem.State, error: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state; items[index].error = error
    }
    private func finish(_ id: UUID, result: CleanResult) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .clean; items[index].fraction = 1; items[index].result = result
        // Release the imported original as soon as verification completes.
        try? FileManager.default.removeItem(at: items[index].input)
    }
    private func ended() { busy = false; operation = nil }
    func cancel() { operation?.cancel() }
    func retry(_ id: UUID) {
        guard !busy, let index = items.firstIndex(where: { $0.id == id }), items[index].result == nil else { return }
        items[index].state = .waiting; items[index].error = nil; items[index].fraction = 0
    }
    func clear() {
        guard !busy, !importing else { return }
        do { try Workspace.prepare(reset: true); items.removeAll() }
        catch { message = "Some temporary files could not be removed. Close and reopen Rinse to retry." }
    }
    func saveToPhotos() {
        let exports = results.map(\.output)
        guard !exports.isEmpty else { return }
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { message = "Allow Rinse to add photos in iPhone Settings, or use Share to save to Files."; return }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    for url in exports {
                        if MediaKind.of(url) == .video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                        else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
                    }
                }
                message = "Saved \(exports.count) clean copies to Photos. Photos may add its own library dates or sync them through your iCloud settings."
            } catch { message = "Photos could not save these copies. You can still export them to Files." }
        }
    }
}
