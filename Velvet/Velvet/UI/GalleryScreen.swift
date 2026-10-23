import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct GalleryScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vault: VaultStore
    @State private var filter = "all"
    @State private var albumID: UUID?
    @State private var selected = Set<UUID>()
    @State private var selecting = false
    @State private var newestFirst = true
    @State private var albumName = ""
    @State private var createAlbum = false
    @State private var importNotice = false
    @State private var picker = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var opened: VaultItem?
    @State private var confirmDelete = false
    private let columns = [GridItem(.adaptive(minimum: 106), spacing: 3)]
    private var visible: [VaultItem] {
        let duplicates = Set(vault.duplicateGroups().flatMap { $0.map(\.id) })
        return vault.items.filter {
            (filter == "trash" ? $0.trashedAt != nil : $0.trashedAt == nil) &&
            (filter != "favorites" || $0.isFavorite) && (filter != "videos" || $0.kind == .video) &&
            (filter != "duplicates" || duplicates.contains($0.id)) &&
            (albumID == nil || $0.albumIDs.contains(albumID!))
        }.sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(filter == "trash" ? "A second thought." : "Only yours.").font(.system(.title, design: .serif))
                            Text("\(visible.count) \(visible.count == 1 ? "memory" : "memories") · Encrypted on this iPhone")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if importing { ProgressView() }
                    }.padding(.horizontal, 20).padding(.top, 10)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            filterChip("All", value: "all"); filterChip("Favorites", value: "favorites")
                            filterChip("Videos", value: "videos"); filterChip("Duplicates", value: "duplicates"); filterChip("Trash", value: "trash")
                        }.padding(.horizontal, 20)
                    }
                    if visible.isEmpty {
                        EmptyLibrary(title: filter == "trash" ? "Nothing in Trash" : "Room for your memories", subtitle: "Capture something with the camera, or import a photo into your private vault.", symbol: "photo.on.rectangle.angled").padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(visible) { item in
                                Button {
                                    if selecting {
                                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                                    } else { opened = item }
                                } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        VaultThumbnail(item: item).aspectRatio(1, contentMode: .fit)
                                        if selecting { Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(.white, VelvetTheme.accent).padding(8) }
                                    }
                                }.buttonStyle(.plain).accessibilityLabel(item.title)
                            }
                        }.padding(.horizontal, 3)
                    }
                    if filter == "trash" { Text("Trash is retained until you deliberately delete it. Storage-level erasure cannot be guaranteed on flash storage.").font(.caption).foregroundStyle(.secondary).padding(20) }
                }
            }.background(Color.black).navigationTitle("Vault")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(newestFirst ? "Oldest first" : "Newest first") { newestFirst.toggle() }
                            Button("All albums") { albumID = nil }
                            ForEach(vault.albums) { album in Button(album.name) { albumID = album.id } }
                            Button("New album", systemImage: "folder.badge.plus") { createAlbum = true }
                        } label: { Image(systemName: albumID == nil ? "line.3.horizontal.decrease" : "folder.fill") }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }
                        Button { importNotice = true } label: { Image(systemName: "plus") }.disabled(importing).accessibilityLabel("Import photos")
                    }
                    if selecting && !selected.isEmpty {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Text("\(selected.count) selected").font(.caption)
                            Spacer()
                            if filter == "trash" {
                                Button("Restore") { mutateSelection { try await vault.restoreFromTrash($0) } }
                                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                            } else {
                                Menu { ForEach(vault.albums) { album in Button(album.name) { mutateSelection { id in
                                    let current = vault.items.first(where: { $0.id == id })?.albumIDs ?? []
                                    try await vault.setAlbums(current.union([album.id]), for: id)
                                } } } } label: { Image(systemName: "folder.badge.plus") }.disabled(vault.albums.isEmpty)
                                Button { mutateSelection { try await vault.moveToTrash($0) } } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                }
                .alert("New private album", isPresented: $createAlbum) {
                    TextField("Album name", text: $albumName)
                    Button("Create") { model.perform { _ = try await vault.createAlbum(name: albumName); albumName = "" } }
                    Button("Cancel", role: .cancel) {}
                }
                .confirmationDialog("Import into Velvet", isPresented: $importNotice, titleVisibility: .visible) {
                    Button("Choose photos") { picker = true }
                } message: { Text("Originals stay in Photos. Apple's picker may download an iCloud asset if it is not on this iPhone. For a strictly offline import, enable Airplane Mode and select a local photo. Velvet processes and encrypts the copy on device. Videos cannot be imported in this release.") }
                .photosPicker(isPresented: $picker, selection: $picks, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .current)
                .onChange(of: picks) { _, items in Task { await importPhotos(items) } }
                .sheet(item: $opened) { MediaDetailScreen(itemID: $0.id) }
                .confirmationDialog("Permanently delete selected media?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete permanently", role: .destructive) { mutateSelection { try await vault.permanentlyDelete($0) } }
                } message: { Text("All Velvet-managed copies and records will be removed. This cannot be undone.") }
        }
    }
    private func filterChip(_ title: String, value: String) -> some View {
        Button(title) { filter = value; selected.removeAll() }
            .font(.subheadline.weight(.medium)).buttonStyle(.glass).tint(filter == value ? VelvetTheme.accent : .white)
    }
    private func mutateSelection(_ operation: @escaping (UUID) async throws -> Void) {
        let ids = selected; selected.removeAll(); selecting = false
        model.perform { for id in ids { try await operation(id) } }
    }
    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !importing else { return }
        let session = model.sessionID
        importing = true
        defer { importing = false; picks = [] }
        for item in items {
            guard vault.isUnlocked, model.sessionID == session else { return }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                guard vault.isUnlocked, model.sessionID == session else { return }
                let ext = item.supportedContentTypes.first(where: { $0.conforms(to: .image) })?.preferredFilenameExtension ?? "heic"
                let saved = try await vault.savePhoto(data: data, fileExtension: ext)
                await model.index(saved.id)
            } catch { model.error = "One photo could not be imported. It may be unavailable offline, too large, or in an unsupported format." }
        }
    }
}

struct VaultThumbnail: View {
    let item: VaultItem
    @EnvironmentObject private var vault: VaultStore
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VelvetTheme.surface
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: item.kind == .video ? "video" : "photo").foregroundStyle(.secondary) }
                VStack { Spacer(); HStack {
                    if item.isFavorite { Image(systemName: "heart.fill") }
                    Spacer()
                    if item.kind == .video { Image(systemName: "play.fill"); Text(Duration.seconds(item.duration ?? 0).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }
                }.font(.caption2.weight(.medium)).padding(7).shadow(radius: 3) }
            }
        }.task(id: item.id) {
            do {
                let data = try await vault.thumbnail(for: item.id)
                guard vault.isUnlocked, !Task.isCancelled else { return }
                image = data.flatMap { UIImage(data: $0) }
            } catch { image = nil }
        }.onDisappear { image = nil }
    }
}
