import SwiftUI
import PhotosUI
import Photos
import ImageIO
import UniformTypeIdentifiers

@MainActor final class LoopStore: ObservableObject {
    @Published var projects: [LoopProject] = []
    @Published var exports: [SavedExport] = []
    @Published var editingProject: LoopProject?
    @Published var importing = false
    @Published var error: String?
    @Published var notice: String?
    @Published var isExporting = false
    @Published var isPaused = false
    @Published var exportProgress = ExportProgress(fraction: 0, completedFrames: 0, totalFrames: 0, message: "Preparing frames…")
    @Published var trackingProgress: Double?
    private var exportControl: ExportControl?
    private var trackingControl: ExportControl?
    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var automaticallyPaused = false
    private let engine = ExportEngine()
    let root: URL
    var projectsDirectory: URL { root.appendingPathComponent("Projects", isDirectory: true) }
    var exportsDirectory: URL { root.appendingPathComponent("Exports", isDirectory: true) }

    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(testing ? "LoopUITests" : "Loop", isDirectory: true)
        do {
            if testing, FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: exportsDirectory, withIntermediateDirectories: true)
            var directory = root
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            removeInterruptedExports()
            loadLibrary()
        } catch { self.error = "Loop could not open its local library: \(error.localizedDescription)" }
    }

    func projectDirectory(_ id: UUID) -> URL { projectsDirectory.appendingPathComponent(id.uuidString, isDirectory: true) }
    func sourceURL(_ project: LoopProject) -> URL {
        projectDirectory(project.id).appendingPathComponent(URL(fileURLWithPath: project.sourceFilename).lastPathComponent)
    }
    func projectThumbnail(_ project: LoopProject) -> URL { projectDirectory(project.id).appendingPathComponent("preview.jpg") }
    func exportURL(_ item: SavedExport) -> URL { exportsDirectory.appendingPathComponent(URL(fileURLWithPath: item.filename).lastPathComponent) }
    func exportThumbnail(_ item: SavedExport) -> URL? {
        item.thumbnailFilename.map { exportsDirectory.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }
    }

    private func loadLibrary() {
        let decoder = JSONDecoder()
        projects = ((try? FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .compactMap { directory -> LoopProject? in
                guard let data = try? Data(contentsOf: directory.appendingPathComponent("project.json")),
                      var project = try? decoder.decode(LoopProject.self, from: data),
                      directory.lastPathComponent == project.id.uuidString,
                      FileManager.default.fileExists(atPath: sourceURL(project).path) else { return nil }
                for index in project.overlays.indices {
                    project.overlays[index].keyframes.sort { $0.time < $1.time }
                }
                project.crop.tracking?.keyframes.sort { $0.time < $1.time }
                return project
            }.sorted { $0.modifiedAt > $1.modifiedAt }
        if let data = try? Data(contentsOf: root.appendingPathComponent("exports.json")),
           let items = try? decoder.decode([SavedExport].self, from: data) {
            exports = items.filter { FileManager.default.fileExists(atPath: exportURL($0).path) }
        }
    }

    /// Only this encoder's exact temporary-file naming scheme is eligible for cleanup.
    /// Completed exports and unknown files are never removed during startup.
    private func removeInterruptedExports() {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: exportsDirectory, includingPropertiesForKeys: Array(keys)) else { return }
        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix(".loop-"), name.hasSuffix(".partial"), name.count == 50,
                  UUID(uuidString: String(name.dropFirst(6).dropLast(8))) != nil,
                  let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    func importPhoto(_ item: PhotosPickerItem) async {
        guard !importing else { return }
        importing = true; notice = nil
        defer { importing = false }
        do {
            guard let movie = try await item.loadTransferable(type: ImportedMovie.self) else {
                throw LoopError.invalidVideo("This video could not be imported. Save a local copy in Photos or Files and try again.")
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            try await importLocalURL(movie.url, displayName: "New loop")
        } catch { self.error = error.localizedDescription }
    }

    func importFile(_ url: URL) async {
        guard !importing else { return }
        importing = true; notice = nil
        defer { importing = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try await importLocalURL(url, displayName: url.deletingPathExtension().lastPathComponent) }
        catch { self.error = error.localizedDescription }
    }

    private func importLocalURL(_ url: URL, displayName: String) async throws {
        let metadata = try await MediaEngine.inspect(url: url)
        let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
        var project = LoopProject(name: displayName, sourceFilename: "source.\(ext)", metadata: metadata)
        project.export.frameRate = min(30, max(1, metadata.nominalFrameRate > 0 ? metadata.nominalFrameRate : 24))
        let directory = projectDirectory(project.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let destination = sourceURL(project)
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.copyItem(at: url, to: destination)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
            }.value
            try persist(project)
            if let frame = try? await MediaEngine.thumbnail(url: destination, time: 0, maximumDimension: 600) {
                writeThumbnail(frame, to: projectThumbnail(project))
            }
            projects.insert(project, at: 0)
            editingProject = project
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func saveEdited(_ project: LoopProject) {
        var updated = project; updated.modifiedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == updated.id }) { projects[index] = updated }
        saveTasks[project.id]?.cancel()
        saveTasks[project.id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation() }
            catch { return }
            guard let self else { return }
            do { try self.persist(updated) }
            catch { self.error = "The project could not be saved: \(error.localizedDescription)" }
            self.saveTasks[project.id] = nil
        }
    }

    func flush(_ project: LoopProject) {
        saveTasks[project.id]?.cancel(); saveTasks[project.id] = nil
        var updated = project; updated.modifiedAt = Date()
        if let index = projects.firstIndex(where: { $0.id == updated.id }) { projects[index] = updated }
        do { try persist(updated) } catch { self.error = "The project could not be saved: \(error.localizedDescription)" }
    }

    private func persist(_ project: LoopProject) throws {
        let data = try JSONEncoder().encode(project)
        try data.write(to: projectDirectory(project.id).appendingPathComponent("project.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func renameProject(_ project: LoopProject, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var updated = project; updated.name = String(clean.prefix(120)); flush(updated)
    }

    func deleteProject(_ project: LoopProject) {
        guard !isExporting, trackingProgress == nil else { return }
        saveTasks[project.id]?.cancel(); saveTasks[project.id] = nil
        do {
            try FileManager.default.removeItem(at: projectDirectory(project.id))
            projects.removeAll { $0.id == project.id }
        } catch { self.error = error.localizedDescription }
    }

    func deleteExport(_ item: SavedExport) {
        do {
            try FileManager.default.removeItem(at: exportURL(item))
            if let thumbnail = exportThumbnail(item) { try? FileManager.default.removeItem(at: thumbnail) }
            exports.removeAll { $0.id == item.id }
            try persistExports()
        } catch { self.error = error.localizedDescription }
    }

    func renameExport(_ item: SavedExport, name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = exports.firstIndex(where: { $0.id == item.id }) else { return }
        do {
            let filename = exportFilename(name: clean, format: item.format)
            try FileManager.default.moveItem(at: exportURL(exports[index]), to: exportsDirectory.appendingPathComponent(filename))
            exports[index].name = String(clean.prefix(120))
            exports[index].filename = filename
            try persistExports()
        } catch { self.error = error.localizedDescription }
    }

    private func persistExports() throws {
        try JSONEncoder().encode(exports).write(to: root.appendingPathComponent("exports.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func export(_ project: LoopProject) async -> SavedExport? {
        guard !isExporting else { return nil }
        do { _ = try ExportPlan(project: project) } catch { self.error = error.localizedDescription; return nil }
        flush(project)
        isExporting = true; isPaused = false; automaticallyPaused = false
        exportProgress = ExportProgress(fraction: 0, completedFrames: 0, totalFrames: 0, message: "Preparing your animation…")
        let control = ExportControl(); exportControl = control
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            isExporting = false; isPaused = false; exportControl = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        let filename = exportFilename(name: project.name, format: project.export.format)
        let destination = exportsDirectory.appendingPathComponent(filename)
        do {
            let result = try await engine.export(sourceURL: sourceURL(project), project: project, destination: destination, control: control) { [weak self] progress in
                Task { @MainActor in self?.exportProgress = progress }
            }
            let thumbnailName = UUID().uuidString + ".jpg"
            if let source = CGImageSourceCreateWithURL(result.url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 700] as CFDictionary) {
                writeThumbnail(image, to: exportsDirectory.appendingPathComponent(thumbnailName))
            }
            let item = SavedExport(name: project.name, filename: filename, format: project.export.format, size: result.size, frameCount: result.frameCount, duration: result.duration, byteCount: result.byteCount, thumbnailFilename: thumbnailName)
            exports.insert(item, at: 0)
            do { try persistExports() }
            catch { self.error = "The animation was created, but its library entry could not be saved: \(error.localizedDescription)" }
            return item
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination); return nil
        } catch LoopError.cancelled {
            try? FileManager.default.removeItem(at: destination); return nil
        } catch {
            try? FileManager.default.removeItem(at: destination)
            self.error = error.localizedDescription; return nil
        }
    }

    func togglePause() {
        automaticallyPaused = false
        isPaused.toggle()
        if isPaused { exportControl?.pause() } else { exportControl?.resume() }
    }
    func cancelExport() { exportControl?.cancel() }
    func cancelTracking() { trackingControl?.cancel() }

    func setActive(_ active: Bool) {
        if !active {
            let pending = Set(saveTasks.keys)
            for project in projects where pending.contains(project.id) { flush(project) }
            if isExporting, !isPaused { automaticallyPaused = true; isPaused = true; exportControl?.pause() }
            trackingControl?.cancel()
        } else if automaticallyPaused {
            automaticallyPaused = false; isPaused = false; exportControl?.resume()
        }
    }

    func track(project: LoopProject, overlay: OverlayItem, anchorTime: Double) async throws -> [TrackingKeyframe] {
        let control = ExportControl(); trackingControl = control; trackingProgress = 0
        defer { trackingControl = nil; trackingProgress = nil }
        return try await TrackingEngine.track(sourceURL: sourceURL(project), project: project, overlay: overlay, anchorTime: anchorTime, control: control) { [weak self] progress in
            Task { @MainActor in self?.trackingProgress = progress }
        }
    }

    func trackCrop(project: LoopProject, anchorTime: Double) async throws -> CropTrackingSettings {
        guard !isExporting, trackingControl == nil else {
            throw LoopError.invalidSettings("Wait for the current operation to finish before tracking the crop.")
        }
        let control = ExportControl(); trackingControl = control; trackingProgress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            trackingControl = nil; trackingProgress = nil
            UIApplication.shared.isIdleTimerDisabled = false
        }
        return try await TrackingEngine.trackCrop(sourceURL: sourceURL(project), project: project,
            anchorTime: anchorTime, control: control) { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.trackingControl === control else { return }
                    self.trackingProgress = progress
                }
            }
    }

    func saveToPhotos(_ item: SavedExport) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            error = "Allow Loop to add photos in Settings, or use Share to save the animation in Files."
            return
        }
        let url = exportURL(item)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = item.name + "." + item.format.fileExtension
                request.addResource(with: .photo, fileURL: url, options: options)
            }
            notice = "Saved to Photos."
        } catch { self.error = "Photos could not save this animation. Use Share → Save to Files. \(error.localizedDescription)" }
    }

    private func writeThumbnail(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        _ = CGImageDestinationFinalize(destination)
    }

    private func exportFilename(name: String, format: AnimationFormat) -> String {
        let base = String(name.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "_" }.prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "-")
        return (base.isEmpty ? "Loop" : base) + "-" + String(UUID().uuidString.prefix(8)) + "." + format.fileExtension
    }

    func prepareUITestFixtureIfNeeded() async {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--uitesting"), projects.isEmpty else { return }
        do {
            let url = try await DebugFixture.makeVideo()
            try await importLocalURL(url, displayName: "Coastal motion")
            try? FileManager.default.removeItem(at: url)
            if let first = projects.first {
                var small = first; small.export.maximumDimension = 480; small.export.frameRate = 12
                small.trimEnd = min(1.0, small.metadata.duration); flush(small)
            }
            editingProject = nil
        } catch { self.error = error.localizedDescription }
        #endif
    }
}
