import Foundation
import Combine
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum StudioTab: Hashable { case create, exports, settings }

struct StudioAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

@MainActor
final class StudioStore: ObservableObject {
    @Published var selectedTab: StudioTab = .create
    @Published private(set) var selectedSource: MediaSource?
    @Published private(set) var sourceThumbnail: UIImage?
    @Published var options: ConversionOptions {
        didSet { saveOptions() }
    }
    @Published private(set) var exports: [ExportResult] = []
    @Published private(set) var latestExport: ExportResult?
    @Published private(set) var progress: ConversionProgress?
    @Published private(set) var isImporting = false
    @Published private(set) var isConverting = false
    @Published private(set) var isCancelling = false
    @Published private(set) var isSavingToPhotos = false
    @Published private(set) var activityNote: String?
    @Published var alert: StudioAlert?
    @Published var previewIsPresented = false

    private var conversionTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var conversionID: UUID?
    private var previousIdleTimerDisabled = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let preferencesKey = "DepthCheck.ConversionOptions.v1"
    private static let historyName = "export-history.json"
    private static let selectionName = "selected-source.json"

    var isBusy: Bool { isImporting || isConverting }

    init() {
        if let data = UserDefaults.standard.data(forKey: "DepthCheck.ConversionOptions.v1"),
           let saved = try? JSONDecoder().decode(ConversionOptions.self, from: data) {
            options = saved
        } else {
            options = ConversionOptions()
        }
        do {
            let url = AppPaths.root.appendingPathComponent(Self.historyName)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let manifest = try JSONDecoder().decode(HistoryManifest.self, from: data)
                exports = try manifest.exports.map { try $0.result() }.sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            alert = StudioAlert(title: "History needs attention", message: "Your export history could not be opened. Your media is still in Files → On My iPhone → Depth Check → Exports. \(error.localizedDescription)")
        }
        let sourceURL = AppPaths.root.appendingPathComponent(Self.selectionName)
        if let data = try? Data(contentsOf: sourceURL),
           let saved = try? JSONDecoder().decode(SavedSource.self, from: data),
           let source = try? saved.source(),
           FileManager.default.fileExists(atPath: source.url.path) {
            selectedSource = source
            Task { [weak self] in
                let thumbnail = await MediaImporter.thumbnail(for: source)
                guard self?.selectedSource?.id == source.id else { return }
                self?.sourceThumbnail = thumbnail
            }
        }
    }

    func importPhotoSelection(_ item: PhotosPickerItem) {
        guard !isBusy else { return }
        prepareImport()
        importTask = Task { [weak self] in
            guard let self else { return }
            var transferredURL: URL?
            do {
                guard let transferred = try await item.loadTransferable(type: ImportedMediaFile.self) else {
                    throw DepthCheckError.message("Photos could not provide the original file. If it is stored in iCloud, let it finish downloading, then try again.")
                }
                transferredURL = transferred.url
                let source = try await MediaImporter.inspect(transferred.url, originalName: transferred.originalName)
                try Task.checkCancellation()
                let thumbnail = await MediaImporter.thumbnail(for: source)
                self.completeImport(source, thumbnail: thumbnail)
            } catch {
                if let transferredURL { try? FileManager.default.removeItem(at: transferredURL) }
                self.failImport(error)
            }
        }
    }

    func importFile(_ url: URL) {
        guard !isBusy else { return }
        prepareImport()
        importTask = Task { [weak self] in
            guard let self else { return }
            do {
                // File providers can copy many gigabytes. Keep their synchronous copy off the UI actor.
                let source = try await Task.detached(priority: .userInitiated) {
                    try await MediaImporter.importFile(url)
                }.value
                try Task.checkCancellation()
                let thumbnail = await MediaImporter.thumbnail(for: source)
                self.completeImport(source, thumbnail: thumbnail)
            } catch {
                self.failImport(error)
            }
        }
    }

    func reportImportError(_ error: Error) {
        // Closing the document picker is not an import failure.
        let nsError = error as NSError
        guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else { return }
        alert = StudioAlert(title: "Could not open file", message: error.localizedDescription)
    }

    private func prepareImport() {
        isImporting = true
        activityNote = nil
        latestExport = nil
    }

    private func completeImport(_ source: MediaSource, thumbnail: UIImage?) {
        let previousSource = selectedSource
        selectedSource = source
        sourceThumbnail = thumbnail
        isImporting = false
        importTask = nil
        do {
            let saved = try SavedSource(source)
            try JSONEncoder().encode(saved).write(to: AppPaths.root.appendingPathComponent(Self.selectionName), options: .atomic)
            if let previousSource, previousSource.url != source.url,
               Self.isOwnedFile(previousSource.url, folder: "Imports") {
                try? FileManager.default.removeItem(at: previousSource.url)
            }
        } catch {
            alert = StudioAlert(title: "Source ready", message: "The source is ready to convert, but the app could not remember it for next time. \(error.localizedDescription)")
        }
    }

    private func failImport(_ error: Error) {
        isImporting = false
        importTask = nil
        if !(error is CancellationError) {
            alert = StudioAlert(title: "Could not import media", message: error.localizedDescription)
        }
    }

    func removeSource() {
        guard !isBusy else { return }
        if let source = selectedSource, Self.isOwnedFile(source.url, folder: "Imports") {
            try? FileManager.default.removeItem(at: source.url)
        }
        selectedSource = nil
        sourceThumbnail = nil
        latestExport = nil
        activityNote = nil
        try? FileManager.default.removeItem(at: AppPaths.root.appendingPathComponent(Self.selectionName))
    }

    func startConversion() {
        guard let source = selectedSource, !isBusy else { return }
        let selectedOptions = options
        let identifier = UUID()
        conversionID = identifier
        isConverting = true
        isCancelling = false
        latestExport = nil
        activityNote = nil
        progress = ConversionProgress(fraction: 0, stage: "Preparing original media")
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Depth Check conversion") { [weak self] in
            Task { @MainActor [weak self] in
                self?.activityNote = "iOS paused background work. Keep Depth Check open while converting."
                self?.cancelConversion()
                self?.endBackgroundTask()
            }
        }
        conversionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await ConversionEngine().convert(source: source, options: selectedOptions) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard self?.conversionID == identifier else { return }
                        self?.progress = update
                    }
                }
                self.exports.insert(result, at: 0)
                self.latestExport = result
                do { try self.persistHistory() }
                catch {
                    self.alert = StudioAlert(title: "Export finished", message: "Your media was created, but its history entry could not be saved. Share it now or find it in the Exports folder in Files. \(error.localizedDescription)")
                }
                self.activityNote = "Your 3D export is ready."
                UIAccessibility.post(notification: .announcement, argument: "Depth Check export complete")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    if self.activityNote == nil { self.activityNote = "Conversion canceled." }
                } else {
                    self.alert = StudioAlert(title: "Conversion could not finish", message: error.localizedDescription)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
            self.finishConversion()
        }
    }

    func cancelConversion() {
        guard isConverting else { return }
        isCancelling = true
        conversionTask?.cancel()
    }

    private func finishConversion() {
        conversionID = nil
        progress = nil
        isConverting = false
        isCancelling = false
        conversionTask = nil
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    func saveToPhotos(_ export: ExportResult) {
        guard !isSavingToPhotos else { return }
        guard filesAreAvailable(export) else {
            alert = StudioAlert(title: "File unavailable", message: "An export file has been moved or deleted. Create the export again to save it to Photos.")
            return
        }
        isSavingToPhotos = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isSavingToPhotos = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                self.alert = StudioAlert(title: "Allow saving to Photos", message: "Open Settings → Apps → Depth Check → Photos and allow Add Photos Only. You can also use Share to save your export to Files.")
                return
            }
            do {
                let files = export.files
                try await PHPhotoLibrary.shared().performChanges {
                    for url in files {
                        let type = UTType(filenameExtension: url.pathExtension)
                        let isVideo = type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
                        let request = PHAssetCreationRequest.forAsset()
                        request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                    }
                }
                self.alert = StudioAlert(title: "Saved to Photos", message: files.count == 1 ? "Your 3D export has been added to your photo library." : "Both full-resolution eye files have been added to your photo library.")
            } catch {
                self.alert = StudioAlert(title: "Photos could not save this export", message: "You can still use Share → Save to Files to keep the original output. \(error.localizedDescription)")
            }
        }
    }

    func filesAreAvailable(_ export: ExportResult) -> Bool {
        !export.files.isEmpty && export.files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    func deleteExport(_ export: ExportResult) {
        do {
            for file in export.files {
                guard Self.isOwnedFile(file, folder: "Exports") else { continue }
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                let parent = file.deletingLastPathComponent()
                if parent.lastPathComponent != "Exports",
                   let contents = try? FileManager.default.contentsOfDirectory(atPath: parent.path), contents.isEmpty {
                    try? FileManager.default.removeItem(at: parent)
                }
            }
            exports.removeAll { $0.id == export.id }
            if latestExport?.id == export.id { latestExport = nil }
            try persistHistory()
        } catch {
            alert = StudioAlert(title: "Could not remove export", message: error.localizedDescription)
        }
    }

    func resetOptions() { options = ConversionOptions() }

    private func saveOptions() {
        guard let data = try? JSONEncoder().encode(options) else { return }
        UserDefaults.standard.set(data, forKey: preferencesKey)
    }

    private func persistHistory() throws {
        let manifest = HistoryManifest(exports: try exports.map(SavedExport.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: AppPaths.root.appendingPathComponent(Self.historyName), options: .atomic)
    }

    private static func isOwnedFile(_ url: URL, folder: String) -> Bool {
        let root = AppPaths.root.appendingPathComponent(folder, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return url.isFileURL && url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
    }
}

// Persist paths relative to Documents. iOS can move an app's container after an
// update; storing absolute file URLs would make every old export appear missing.
private enum SavedPaths {
    static func relative(_ url: URL) throws -> String {
        let root = AppPaths.root.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard url.isFileURL, path.hasPrefix(root) else {
            throw DepthCheckError.message("The media file is outside this app's document folder.")
        }
        return String(path.dropFirst(root.count))
    }

    static func resolve(_ path: String, folder: String) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == Substring(folder), components.count >= 2,
              !components.contains(".."), !components.contains("."), !components.contains("") else {
            throw DepthCheckError.message("The saved media path is invalid.")
        }
        return AppPaths.root.appendingPathComponent(path)
    }
}

private struct HistoryManifest: Codable {
    var version = 1
    var exports: [SavedExport]
}

private struct SavedSource: Codable {
    var id: UUID
    var path: String
    var name: String
    var kind: MediaKind
    var size: PixelSize
    var frameRate: Double
    var duration: Double
    var hasAudio: Bool
    var isHDR: Bool

    init(_ source: MediaSource) throws {
        id = source.id
        path = try SavedPaths.relative(source.url)
        name = source.name
        kind = source.kind
        size = source.size
        frameRate = source.frameRate
        duration = source.duration
        hasAudio = source.hasAudio
        isHDR = source.isHDR
    }

    func source() throws -> MediaSource {
        MediaSource(id: id, url: try SavedPaths.resolve(path, folder: "Imports"), name: name, kind: kind, size: size, frameRate: frameRate, duration: duration, hasAudio: hasAudio, isHDR: isHDR)
    }
}

private struct SavedExport: Codable {
    var id: UUID
    var paths: [String]
    var createdAt: Date
    var sourceName: String
    var format: OutputFormat
    var size: PixelSize
    var frameCount: Int
    var frameRate: Double
    var duration: Double
    var note: String

    init(_ export: ExportResult) throws {
        id = export.id
        paths = try export.files.map(SavedPaths.relative)
        createdAt = export.createdAt
        sourceName = export.sourceName
        format = export.format
        size = export.size
        frameCount = export.frameCount
        frameRate = export.frameRate
        duration = export.duration
        note = export.note
    }

    func result() throws -> ExportResult {
        ExportResult(id: id, files: try paths.map { try SavedPaths.resolve($0, folder: "Exports") }, createdAt: createdAt, sourceName: sourceName, format: format, size: size, frameCount: frameCount, frameRate: frameRate, duration: duration, note: note)
    }
}
