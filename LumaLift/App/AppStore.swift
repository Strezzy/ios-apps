import SwiftUI
import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

struct LibraryItem: Codable, Identifiable {
    let id: UUID
    let filename: String
    let title: String
    let created: Date
    let dimensions: String
    let fps: String
    let bytes: Int64
    let duration: Double
    let frames: Int
    let sha256: String
    let settings: EnhanceSettings
    var url: URL { LocalFiles.library.appendingPathComponent(filename) }
}

enum LocalFiles {
    static var library: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lucid", isDirectory: true)
    }
    static var pending: URL { library.appendingPathComponent("Pending", isDirectory: true) }
    static var imports: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumaLiftImports", isDirectory: true)
    }
    static func prepare(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    static func importMovie(_ source: URL) throws -> URL {
        guard source.isFileURL else { throw LiftError.message("Only local video files can be imported.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let folder = imports.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try prepare(folder)
        let result = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: result)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: result.path)
            return result
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}

struct ImportedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            ImportedMovie(url: try LocalFiles.importMovie(received.file))
        }
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var settings = EnhanceSettings() {
        didSet { if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "enhancement-settings") } }
    }
    @Published var clip: ClipInfo?
    @Published var library: [LibraryItem] = []
    @Published var importing = false
    @Published var working = false
    @Published var paused = false
    @Published var progress = WorkProgress(fraction: 0, stage: "Preparing")
    @Published var error: String?
    @Published var resultURL: URL?
    @Published var resultIsPreview = false
    @Published var notice: String?
    private var control: WorkControl?
    private var workTask: Task<ExportResult, Error>?
    private var previewURL: URL?
    init() {
        if let data = UserDefaults.standard.data(forKey: "enhancement-settings"),
           let saved = try? JSONDecoder().decode(EnhanceSettings.self, from: data) { settings = saved }
        do {
            try LocalFiles.prepare(LocalFiles.library)
            for disposable in [LocalFiles.imports, LocalFiles.pending] {
                if FileManager.default.fileExists(atPath: disposable.path) { try FileManager.default.removeItem(at: disposable) }
                try LocalFiles.prepare(disposable)
            }
            let temporary = FileManager.default.temporaryDirectory
            for url in (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? [] {
                if url.lastPathComponent.hasPrefix("LumaLift-") { try? FileManager.default.removeItem(at: url) }
            }
            let index = LocalFiles.library.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: index.path) {
                library = try JSONDecoder().decode([LibraryItem].self, from: Data(contentsOf: index))
                    .filter { FileManager.default.fileExists(atPath: $0.url.path) }
            }
        } catch { self.error = error.localizedDescription }
    }
    var validationError: String? {
        guard let clip else { return nil }
        do { try settings.validate(width: clip.width, height: clip.height, sourceFPS: clip.fps); return nil }
        catch { return error.localizedDescription }
    }
    var outputDimensions: String {
        guard let clip else { return "Original dimensions" }
        return "\(Int(clip.displaySize.width) * settings.scale) × \(Int(clip.displaySize.height) * settings.scale)"
    }
    func importPhoto(_ item: PhotosPickerItem) async {
        guard !working else { return }
        importing = true
        defer { importing = false }
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw LiftError.message("The selected video could not be copied. For offline use, first download it to your phone in Photos.")
            }
            try await accept(movie.url)
        } catch { self.error = error.localizedDescription }
    }
    func importFile(_ source: URL) async {
        guard !working else { return }
        importing = true
        defer { importing = false }
        do {
            let url = try await Task.detached { try LocalFiles.importMovie(source) }.value
            try await accept(url)
        } catch { self.error = error.localizedDescription }
    }
    private func accept(_ url: URL) async throws {
        do {
            let inspected = try await ClipInfo.inspect(url)
            try EnhanceSettings(enhance: false).validate(width: inspected.width, height: inspected.height, sourceFPS: inspected.fps)
            if let old = clip?.url { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
            if let previewURL { try? FileManager.default.removeItem(at: previewURL) }
            clip = inspected
            resultURL = nil
            previewURL = nil
            notice = nil
        } catch {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            throw error
        }
    }
    func start(preview: Bool) {
        guard let clip, !working, validationError == nil else { return }
        let configuration = settings
        let control = WorkControl()
        self.control = control
        working = true
        paused = false
        progress = WorkProgress(fraction: 0, stage: "Preparing on-device models")
        UIApplication.shared.isIdleTimerDisabled = true
        let id = UUID()
        let destination = (preview ? LocalFiles.imports : LocalFiles.pending).appendingPathComponent(id.uuidString + ".mov")
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            try await VideoEngine().export(clip: clip, settings: configuration, output: destination,
                control: control, previewSeconds: preview ? 2 : nil) { [weak self] value in
                    Task { @MainActor [weak self] in self?.progress = value }
                }
        }
        workTask = task
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.working = false
                self.paused = false
                self.workTask = nil
                self.control = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }
            do {
                let result = try await task.value
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: result.url.path)
                let finalURL: URL
                if preview {
                    if let old = self.previewURL { try? FileManager.default.removeItem(at: old) }
                    finalURL = result.url
                    self.previewURL = finalURL
                } else {
                    finalURL = LocalFiles.library.appendingPathComponent(result.url.lastPathComponent)
                    try FileManager.default.moveItem(at: result.url, to: finalURL)
                    let item = LibraryItem(id: id, filename: finalURL.lastPathComponent, title: clip.title,
                        created: Date(), dimensions: "\(Int(clip.displaySize.width) * configuration.scale) × \(Int(clip.displaySize.height) * configuration.scale)",
                        fps: configuration.fps == 0 ? String(format: "%.2f FPS", clip.fps) : "\(configuration.fps) FPS",
                        bytes: result.bytes, duration: result.duration, frames: result.frames, sha256: result.sha256, settings: configuration)
                    self.library.insert(item, at: 0)
                    try self.saveIndex()
                }
                self.resultURL = finalURL
                self.resultIsPreview = preview
                self.notice = preview ? "2-second preview ready" : "Verified export saved to your library"
            } catch is CancellationError {
                self.notice = "Cancelled. Your original video is unchanged."
            } catch { self.error = error.localizedDescription }
        }
    }
    func cancel() { control?.cancel(); workTask?.cancel() }
    func togglePause() { paused.toggle(); control?.setPaused(paused) }
    func setBackground(_ value: Bool) { control?.setBackground(value) }
    func remove(_ item: LibraryItem) {
        do {
            try FileManager.default.removeItem(at: item.url)
            library.removeAll { $0.id == item.id }
            if resultURL == item.url { resultURL = nil }
            try saveIndex()
        } catch { self.error = error.localizedDescription }
    }
    private func saveIndex() throws {
        let data = try JSONEncoder().encode(library)
        try data.write(to: LocalFiles.library.appendingPathComponent("library.json"), options: [.atomic, .completeFileProtection])
    }
    func saveToPhotos(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Allow LumaLift to add videos to Photos in Settings, or use Share to save to Files."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            notice = "Saved to Photos"
        } catch { self.error = error.localizedDescription }
    }
}
