import AVFoundation
import Combine
import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct OrbitVideo: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    let fileName: String
    let thumbnailName: String?
    let importedAt: Date
    var lastPlayedAt: Date
    let duration: Double
    let width: Int
    let height: Int
    let isSpatial: Bool
    let byteCount: Int64

    var dimensions: String { "\(width) × \(height)" }
}

private enum MediaImportError: LocalizedError {
    case noVideo, missingFile, inaccessibleLibrary, insufficientStorage
    var errorDescription: String? {
        switch self {
        case .noVideo: return "This file doesn’t contain a playable video. Choose a video from Photos or Files."
        case .missingFile: return "The video couldn’t be opened. Download it in Photos or Files, then try again."
        case .inaccessibleLibrary: return "Orbit’s local library couldn’t be opened. Restart the app and try again."
        case .insufficientStorage: return "There isn’t enough free space to keep a local copy of this video. Free some space and try again."
        }
    }
}

/// Original movie files are copied byte-for-byte. No export session or transcoding
/// sits between PHPicker's current representation and the spatial video decoder.
@MainActor final class MediaLibrary: ObservableObject {
    @Published private(set) var videos: [OrbitVideo] = []
    @Published private(set) var isImporting = false
    @Published private(set) var importProgress: Double?
    @Published private(set) var importStatus = "Opening video…"
    @Published var selectedVideo: OrbitVideo?
    @Published var errorMessage: String?

    private let rootURL: URL
    private var importTask: Task<Void, Never>?
    private var providerProgress: Progress?
    private var progressObservation: NSKeyValueObservation?
    private var importGeneration = UUID()
    private var libraryAvailable = true

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = base.appendingPathComponent("Orbit", isDirectory: true)
        do {
            for url in [rootURL, mediaDirectory, thumbnailDirectory, importDirectory] {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                var localURL = url
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? localURL.setResourceValues(values)
            }
            if FileManager.default.fileExists(atPath: indexURL.path) {
                let decoded = try JSONDecoder().decode([OrbitVideo].self, from: Data(contentsOf: indexURL))
                videos = decoded.filter {
                    $0.fileName == URL(fileURLWithPath: $0.fileName).lastPathComponent &&
                    FileManager.default.fileExists(atPath: mediaDirectory.appendingPathComponent($0.fileName).path)
                }.sorted { $0.lastPlayedAt > $1.lastPlayedAt }
            }
            // Interrupted imports never appear in the library and can be discarded.
            for file in (try? FileManager.default.contentsOfDirectory(at: importDirectory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: file)
            }
        } catch {
            libraryAvailable = false
            errorMessage = "Your library couldn’t be read. Existing videos are still stored on this device. Restart Orbit and try again."
        }
    }

    private var mediaDirectory: URL { rootURL.appendingPathComponent("Videos", isDirectory: true) }
    private var thumbnailDirectory: URL { rootURL.appendingPathComponent("Thumbnails", isDirectory: true) }
    private var importDirectory: URL { rootURL.appendingPathComponent("Imports", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("library.json") }

    var totalBytes: Int64 { videos.reduce(0) { $0 + $1.byteCount } }
    func videoURL(_ video: OrbitVideo) -> URL { mediaDirectory.appendingPathComponent(video.fileName) }
    func thumbnailURL(_ video: OrbitVideo) -> URL? {
        guard let name = video.thumbnailName, name == URL(fileURLWithPath: name).lastPathComponent else { return nil }
        return thumbnailDirectory.appendingPathComponent(name)
    }

    func open(_ video: OrbitVideo) {
        guard FileManager.default.fileExists(atPath: videoURL(video).path) else {
            errorMessage = "This local copy is missing. Import the original video again."
            return
        }
        var next = videos
        if let index = next.firstIndex(where: { $0.id == video.id }) {
            next[index].lastPlayedAt = Date()
            next.sort { $0.lastPlayedAt > $1.lastPlayedAt }
            do { try persist(next); videos = next } catch { /* Playback remains available. */ }
        }
        selectedVideo = video
    }

    func rename(_ video: OrbitVideo, to name: String) {
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !clean.isEmpty, let index = videos.firstIndex(where: { $0.id == video.id }) else { return }
        var next = videos; next[index].title = clean
        do { try persist(next); videos = next }
        catch { errorMessage = "The new name couldn’t be saved. Please try again." }
    }

    func delete(_ video: OrbitVideo) {
        let next = videos.filter { $0.id != video.id }
        do {
            // Persist the removal first: a failed index write never destroys a listed video.
            try persist(next)
            videos = next
            try? FileManager.default.removeItem(at: videoURL(video))
            if let thumbnail = thumbnailURL(video) { try? FileManager.default.removeItem(at: thumbnail) }
        } catch { errorMessage = "The video couldn’t be removed. Please try again." }
    }

    func importFile(_ source: URL) {
        guard source.isFileURL else {
            errorMessage = "Choose a video file from Photos or Files."
            return
        }
        guard beginImport(status: "Opening from Files…") else { return }
        let generation = importGeneration
        let staging = importDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.safeExtension(source.pathExtension))
        let title = source.deletingPathExtension().lastPathComponent
        importTask = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: staging); self.finishImport(generation) }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    try Self.copyCoordinatedFile(from: source, to: staging)
                }.value
                try Task.checkCancellation()
                guard generation == self.importGeneration else { return }
                await self.completeImport(staging: staging, title: title, generation: generation)
            } catch {
                if generation == self.importGeneration && !Task.isCancelled { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func importProvider(_ provider: NSItemProvider) {
        guard beginImport(status: "Opening from Photos…") else { return }
        let generation = importGeneration
        let destinationDirectory = importDirectory
        importTask = Task { [weak self] in
            guard let self else { return }
            var stagedURL: URL?
            defer {
                if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
                self.finishImport(generation)
            }
            do {
                let type = provider.registeredTypeIdentifiers.first {
                    UTType($0)?.conforms(to: .movie) == true
                } ?? UTType.movie.identifier
                let result: (URL, String) = try await withCheckedThrowingContinuation { continuation in
                    let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                        if let error { continuation.resume(throwing: error); return }
                        guard let url else { continuation.resume(throwing: MediaImportError.missingFile); return }
                        do {
                            let staged = destinationDirectory.appendingPathComponent(UUID().uuidString)
                                .appendingPathExtension(Self.safeExtension(url.pathExtension))
                            try Self.checkSpace(for: url, at: destinationDirectory)
                            // The provider URL expires when this callback returns.
                            // Copy here, before resuming the continuation. FileManager streams
                            // the file rather than loading an entire 4K movie into memory.
                            try FileManager.default.copyItem(at: url, to: staged)
                            continuation.resume(returning: (staged, provider.suggestedName ?? url.deletingPathExtension().lastPathComponent))
                        } catch { continuation.resume(throwing: error) }
                    }
                    self.providerProgress = progress
                    self.progressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            guard let self, generation == self.importGeneration, self.isImporting else { return }
                            self.importProgress = fraction > 0 && fraction < 1 ? fraction : nil
                        }
                    }
                }
                stagedURL = result.0
                try Task.checkCancellation()
                guard generation == self.importGeneration else { return }
                await self.completeImport(staging: result.0, title: result.1, generation: generation)
            } catch {
                if generation == self.importGeneration && !Task.isCancelled { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func cancelImport() {
        importGeneration = UUID()
        providerProgress?.cancel(); providerProgress = nil
        progressObservation = nil
        importTask?.cancel(); importTask = nil
        isImporting = false; importProgress = nil
    }

    private func beginImport(status: String) -> Bool {
        guard !isImporting else { return false }
        guard libraryAvailable else { errorMessage = MediaImportError.inaccessibleLibrary.localizedDescription; return false }
        importGeneration = UUID()
        errorMessage = nil; importStatus = status; importProgress = nil; isImporting = true
        return true
    }

    private func completeImport(staging: URL, title: String, generation: UUID) async {
        importStatus = "Preparing your video…"; importProgress = nil
        let id = UUID()
        let fileName = id.uuidString + "." + Self.safeExtension(staging.pathExtension)
        let thumbnailName = id.uuidString + ".jpg"
        let destination = mediaDirectory.appendingPathComponent(fileName)
        let thumbnail = thumbnailDirectory.appendingPathComponent(thumbnailName)
        do {
            let inspection = try await OrbitMediaInspection.inspect(staging, thumbnailURL: thumbnail)
            try Task.checkCancellation()
            guard generation == importGeneration else { try? FileManager.default.removeItem(at: thumbnail); return }
            try FileManager.default.moveItem(at: staging, to: destination)
            let now = Date()
            let cleanTitle = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            let video = OrbitVideo(id: id, title: cleanTitle.isEmpty ? "Untitled video" : cleanTitle,
                                   fileName: fileName, thumbnailName: inspection.hasThumbnail ? thumbnailName : nil,
                                   importedAt: now, lastPlayedAt: now, duration: inspection.duration,
                                   width: inspection.width, height: inspection.height,
                                   isSpatial: inspection.isSpatial, byteCount: inspection.bytes)
            let next = [video] + videos
            try persist(next)
            videos = next
            selectedVideo = video
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: thumbnail)
            if generation == importGeneration && !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func finishImport(_ generation: UUID) {
        guard generation == importGeneration else { return }
        isImporting = false; importProgress = nil
        providerProgress = nil; progressObservation = nil; importTask = nil
    }

    private func persist(_ entries: [OrbitVideo]) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(entries).write(to: indexURL, options: .atomic)
    }

    nonisolated private static func safeExtension(_ value: String) -> String {
        let lower = value.lowercased()
        return ["mov", "mp4", "m4v", "qt"].contains(lower) ? lower : "mov"
    }

    nonisolated private static func checkSpace(for source: URL, at directory: URL) throws {
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let available = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? Int64.max
        guard Int64(size) + 32 * 1_024 * 1_024 < available else { throw MediaImportError.insufficientStorage }
    }

    nonisolated private static func copyCoordinatedFile(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            do {
                guard FileManager.default.fileExists(atPath: readable.path) else { throw MediaImportError.missingFile }
                try checkSpace(for: readable, at: destination.deletingLastPathComponent())
                try FileManager.default.copyItem(at: readable, to: destination)
            } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }
}

private struct OrbitMediaInspection {
    let duration: Double
    let width: Int
    let height: Int
    let isSpatial: Bool
    let bytes: Int64
    let hasThumbnail: Bool

    static func inspect(_ url: URL, thumbnailURL: URL) async throws -> OrbitMediaInspection {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable), let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaImportError.noVideo
        }
        let duration = try await asset.load(.duration)
        let (size, transform) = try await track.load(.naturalSize, .preferredTransform)
        let displayed = size.applying(transform)
        let stereoTracks = try await asset.loadTracks(withMediaCharacteristic: .containsStereoMultiviewVideo)
        let spatial = !stereoTracks.isEmpty
        let bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        var hasThumbnail = false
        do {
            let (image, _) = try await generator.image(at: .zero)
            if let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) {
                try data.write(to: thumbnailURL, options: .atomic)
                hasThumbnail = true
            }
        } catch { /* A movie remains usable when its thumbnail cannot be generated. */ }
        return OrbitMediaInspection(duration: duration.seconds.isFinite ? max(0, duration.seconds) : 0,
                                    width: Int(abs(displayed.width).rounded()), height: Int(abs(displayed.height).rounded()),
                                    isSpatial: spatial, bytes: bytes, hasThumbnail: hasThumbnail)
    }
}
