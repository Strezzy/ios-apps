import SwiftUI
import ImageIO

struct LoopLibraryView: View {
    @EnvironmentObject private var store: LoopStore
    @State private var section = "Projects"
    @State private var selectedExport: SavedExport?
    @State private var deletingProject: LoopProject?
    @State private var deletingExport: SavedExport?
    @State private var renamingProject: LoopProject?
    @State private var renamingExport: SavedExport?
    @State private var newName = ""
    @State private var renamePresented = false
    @State private var deletePresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                LoopAtmosphere()
                ScrollView {
                    VStack(spacing: 18) {
                        Picker("Library", selection: $section) { Text("Projects").tag("Projects"); Text("Exports").tag("Exports") }
                            .pickerStyle(.segmented)
                        if section == "Projects" {
                            if store.projects.isEmpty {
                                ContentUnavailableView("Room for a little magic", systemImage: "film.stack", description: Text("Import a video in Create. Your edits are saved here automatically."))
                            }
                            ForEach(store.projects) { project in
                                Button { store.editingProject = project } label: {
                                    ProjectRow(project: project, thumbnailURL: store.projectThumbnail(project))
                                }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Rename", systemImage: "pencil") { renamingProject = project; renamingExport = nil; newName = project.name; renamePresented = true }
                                        Button("Delete project", systemImage: "trash", role: .destructive) { deletingProject = project; deletingExport = nil; deletePresented = true }
                                    }
                            }
                        } else {
                            if store.exports.isEmpty {
                                ContentUnavailableView("Your loops live here", systemImage: "infinity", description: Text("Finished GIFs, APNGs and videos are kept on your iPhone, ready to save or share."))
                            }
                            ForEach(store.exports) { item in
                                Button { selectedExport = item } label: { ExportRow(item: item, thumbnail: store.exportThumbnail(item)) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        ShareLink(item: store.exportURL(item))
                                        Button("Rename", systemImage: "pencil") { renamingExport = item; renamingProject = nil; newName = item.name; renamePresented = true }
                                        Button("Delete export", systemImage: "trash", role: .destructive) { deletingExport = item; deletingProject = nil; deletePresented = true }
                                    }
                            }
                        }
                    }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Library")
                .sheet(item: $selectedExport) { item in ExportDetailView(item: item).environmentObject(store) }
                .alert("Rename", isPresented: $renamePresented) {
                    TextField("Name", text: $newName)
                    Button("Cancel", role: .cancel) { }
                    Button("Save") {
                        if let project = renamingProject { store.renameProject(project, name: newName) }
                        if let item = renamingExport { store.renameExport(item, name: newName) }
                    }
                }
                .confirmationDialog(deletingProject == nil ? "Delete this export?" : "Delete this project and its imported video?", isPresented: $deletePresented, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        if let project = deletingProject { store.deleteProject(project) }
                        if let item = deletingExport { store.deleteExport(item) }
                    }
                } message: { Text("This removes Loop’s local copy. Your original in Photos or Files is unchanged.") }
        }
    }
}

struct ExportRow: View {
    let item: SavedExport
    let thumbnail: URL?
    var body: some View {
        HStack(spacing: 15) {
            LocalThumbnail(url: thumbnail).frame(width: 78, height: 78).clipShape(.rect(cornerRadius: 18))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline).lineLimit(1)
                Text("\(item.format.title) · \(item.size.label)").font(.caption).foregroundStyle(.secondary)
                Text("\(LoopFormat.bytes(item.byteCount)) · \(LoopFormat.time(item.duration))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "play.circle").font(.title2).foregroundStyle(LoopTheme.teal)
        }.padding(12).background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}

struct ExportDetailView: View {
    @EnvironmentObject private var store: LoopStore
    @Environment(\.dismiss) private var dismiss
    let item: SavedExport
    @State private var saving = false
    var body: some View {
        NavigationStack {
            ZStack {
                LoopAtmosphere()
                ScrollView {
                    VStack(spacing: 22) {
                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(LoopTheme.teal)
                            Text("Ready for another round.").font(.title3.weight(.bold))
                        }.padding(.top, 8)
                        Group {
                            if item.format.isVideo { SavedVideoPreview(url: store.exportURL(item)) }
                            else { AnimatedExportPreview(url: store.exportURL(item)) }
                        }
                            .aspectRatio(item.size.aspect, contentMode: .fit)
                            .frame(maxHeight: 420).clipShape(.rect(cornerRadius: 25))
                            .accessibilityIdentifier("exportAnimationPreview")
                        LoopCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name).font(.headline)
                                    Text("\(item.format.title) · \(item.size.label) · \(LoopFormat.bytes(item.byteCount))").font(.caption).foregroundStyle(.secondary)
                                    Text("\(item.frameCount) frames · \(LoopFormat.time(item.duration))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            ShareLink(item: store.exportURL(item)) {
                                Label("Share or save to Files", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                            }.buttonStyle(.glassProminent).accessibilityIdentifier("shareAnimation")
                            Button {
                                saving = true
                                Task { await store.saveToPhotos(item); saving = false }
                            } label: {
                                Label(saving ? "Saving…" : "Save to Photos", systemImage: "photo.badge.arrow.down")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }.buttonStyle(.glass).disabled(saving)
                            if let notice = store.notice { Label(notice, systemImage: "checkmark.circle").font(.caption).foregroundStyle(LoopTheme.teal) }
                        }
                        Text(item.format.isVideo ? "Video is saved with the selected codec and all edits baked in. HDR sources are exported in standard color." : item.format == .gif ? "GIF playback may differ between viewers, particularly above 50 FPS. This preview reads the file’s original frame delays." : "APNG plays with full color and precise timing. Some sharing apps convert animated PNGs to still images.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(22).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Your loop").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.accessibilityIdentifier("exportDetailDone") } }
                .alert("Loop", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                    Button("OK", role: .cancel) { store.error = nil }
                } message: { Text(store.error ?? "") }
                .onAppear { store.notice = nil }
        }
    }
}

@MainActor final class AnimationPlayer: ObservableObject {
    @Published var frame: CGImage?
    @Published var failed = false
    @Published var playing = false
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func start(url: URL, play: Bool = true) {
        stop()
        let token = UUID(); generation = token; playing = play; failed = false
        task = Task { [weak self] in
            defer { if self?.generation == token { self?.playing = false } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { self?.failed = true; return }
            let count = CGImageSourceGetCount(source)
            guard count > 0 else { self?.failed = true; return }
            let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let totalPlays: Int
            if let repeats = (gif?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue {
                totalPlays = repeats == 0 ? 0 : repeats + 1
            } else if let plays = (png?[kCGImagePropertyAPNGLoopCount] as? NSNumber)?.intValue {
                totalPlays = plays
            } else { totalPlays = 1 }
            var completedPlays = 0
            var index = 0
            while !Task.isCancelled {
                let started = Date()
                let frameIndex = index
                let decoded: (CGImage?, Double) = await Task.detached(priority: .userInitiated) {
                    autoreleasepool {
                        let properties = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [CFString: Any]
                        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                        let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                        let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                            ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue
                            ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? NSNumber)?.doubleValue
                            ?? (png?[kCGImagePropertyAPNGDelayTime] as? NSNumber)?.doubleValue ?? 0.1
                        let image = CGImageSourceCreateThumbnailAtIndex(source, frameIndex, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceShouldCache: false] as CFDictionary)
                        return (image, max(0.008, delay))
                    }
                }.value
                guard !Task.isCancelled else { break }
                self?.frame = decoded.0
                if decoded.0 == nil { self?.failed = true; break }
                if !play { break }
                index = (index + 1) % count
                if index == 0 { completedPlays += 1 }
                let remaining = max(0.001, decoded.1 - Date().timeIntervalSince(started))
                do { try await Task.sleep(for: .seconds(remaining)) } catch { break }
                if totalPlays > 0 && completedPlays >= totalPlays { break }
            }
        }
    }
    func stop() { generation = UUID(); task?.cancel(); task = nil; playing = false }
    func clear() { stop(); frame = nil }
}

struct AnimatedExportPreview: View {
    let url: URL
    @StateObject private var player = AnimationPlayer()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var paused = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black
            if let frame = player.frame { Image(decorative: frame, scale: 1).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if player.failed { Text("Preview unavailable. You can still share the saved file.").font(.caption).foregroundStyle(.white).padding() }
            else { ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Button {
                paused = player.playing
                if paused { player.stop() } else { player.start(url: url) }
            } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").padding(11) }
                .buttonStyle(.glass).tint(.white).padding(12)
                .accessibilityLabel(player.playing ? "Pause animation" : "Play animation")
        }.onAppear { paused = reduceMotion; player.start(url: url, play: !reduceMotion) }
            .onDisappear { player.clear() }
            .onChange(of: phase) { _, value in if value == .active && !paused { player.start(url: url) } else { player.stop() } }
            .onChange(of: reduceMotion) { _, value in if value { paused = true; player.stop() } }
    }
}

struct LoopSettingsView: View {
    @EnvironmentObject private var store: LoopStore
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        NavigationStack {
            ZStack {
                LoopAtmosphere()
                ScrollView {
                    VStack(spacing: 18) {
                        HStack(spacing: 18) {
                            LoopMark(size: 70)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Loop").font(.system(.largeTitle, design: .rounded, weight: .bold))
                                Text("A moment. On repeat.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(.vertical, 12)
                        LoopCard {
                            EditorSectionTitle(title: "Make yourself at home")
                            Picker("Appearance", selection: $appearance) {
                                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                            }.pickerStyle(.segmented).accessibilityIdentifier("appearancePicker")
                            Text("Loop follows your text size and Reduce Transparency preferences.").font(.caption).foregroundStyle(.secondary)
                        }
                        LoopCard {
                            Label("Made on your iPhone", systemImage: "lock.shield").font(.headline)
                            Text("Video decoding, motion tracking, effects and animation export all happen on device. No account, ads, analytics, server uploads or runtime model downloads. Portrait models are bundled with the app.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("Projects and exports stay in Loop’s local storage and are excluded from automatic cloud backup. Delete them from Library when you no longer need them. Uninstalling Loop removes this library.")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Photos and Files can retrieve cloud-only originals through their system pickers. Choose downloaded media to work offline. Sharing or saving to a cloud-backed library is your choice.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        LoopCard {
                            EditorSectionTitle(title: "A few useful details")
                            detail("Resolution", "Export up to a 4096-pixel longest edge. Native crop mode keeps source detail within that limit.")
                            detail("Frame rate", "High-frame-rate and variable-frame-rate videos are sampled by time. GIF has 10 ms timing steps; APNG supports more precise timing.")
                            detail("Tracking", "Tracking can drift when a subject is hidden or moves quickly. Check your result and add manual position keyframes where needed.")
                            detail("Long exports", "Keep Loop open. Processing pauses outside the foreground; iOS can still terminate a background app. Save completed animations before uninstalling.")
                        }
                        Text("\(store.projects.count) projects · \(store.exports.count) exports · \(LoopFormat.bytes(store.exports.reduce(0) { $0 + $1.byteCount })) exported")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Loop \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                            .font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 20)
                    }.padding(20).frame(maxWidth: 700).frame(maxWidth: .infinity)
                }
            }.navigationTitle("Settings")
        }
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium))
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }
}
