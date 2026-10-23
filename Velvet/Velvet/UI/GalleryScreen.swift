import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct GalleryScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vault: VaultStore
    @State private var filter = "all"
    @State private var albumID: UUID?
    @State private var browsingAlbums = false
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
    private var visible: [VaultItem] {
        let duplicates: Set<UUID> = filter == "duplicates" ? Set(vault.duplicateGroups().flatMap { $0.map(\.id) }) : []
        return vault.items.filter {
            (filter == "trash" ? $0.isTrashed : !$0.isTrashed) &&
            (filter != "favorites" || $0.isFavorite) && (filter != "photos" || $0.kind == .photo) &&
            (filter != "videos" || $0.kind == .video) && (filter != "duplicates" || duplicates.contains($0.id)) &&
            (albumID == nil || $0.albumIDs.contains(albumID!))
        }.sorted { newestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt }
    }
    private var albumTitle: String? { vault.albums.first { $0.id == albumID }?.name }
    private var countText: String {
        let photos = visible.filter { $0.kind == .photo }.count
        let videos = visible.count - photos
        if photos == 0 && videos == 0 { return "No items" }
        return [photos > 0 ? "\(photos) \(photos == 1 ? "Photo" : "Photos")" : nil,
                videos > 0 ? "\(videos) \(videos == 1 ? "Video" : "Videos")" : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("View", selection: $browsingAlbums) {
                        Text("Library").tag(false)
                        Text("Albums").tag(true)
                    }.pickerStyle(.segmented).padding(.horizontal, 20)
                        .onChange(of: browsingAlbums) { _, _ in selecting = false; selected.removeAll() }
                    if browsingAlbums { albums } else { library }
                }.padding(.top, 8).padding(.bottom, 24)
            }.background(Color.black).navigationTitle("Photos")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !browsingAlbums {
                            Menu {
                                Picker("Sort", selection: $newestFirst) {
                                    Text("Newest First").tag(true)
                                    Text("Oldest First").tag(false)
                                }
                                Divider()
                                Button("Duplicates", systemImage: "square.on.square") { applyFilter("duplicates") }
                                Button("Recently Deleted", systemImage: "trash") { applyFilter("trash") }
                                if filter == "duplicates" || filter == "trash" || albumID != nil {
                                    Button("All Photos and Videos", systemImage: "photo.on.rectangle") { albumID = nil; applyFilter("all") }
                                }
                            } label: { Image(systemName: "line.3.horizontal.decrease") }
                                .accessibilityLabel("Sort and filter photos")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if !browsingAlbums {
                            Button(selecting ? "Done" : "Select") { selecting.toggle(); selected.removeAll() }.disabled(visible.isEmpty)
                        }
                        Menu {
                            Button("Import Photos", systemImage: "photo.badge.plus") { importNotice = true }
                            Button("New Album", systemImage: "folder.badge.plus") { createAlbum = true }
                        } label: { Image(systemName: "plus") }
                            .disabled(importing).accessibilityLabel("Add photos or album")
                    }
                    if selecting && !selected.isEmpty {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Text("\(selected.count) Selected").font(.subheadline)
                            Spacer()
                            if filter == "trash" {
                                Button("Restore") { mutateSelection { try await vault.restoreFromTrash($0) } }
                                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Delete selected items permanently")
                            } else {
                                Menu {
                                    ForEach(vault.albums) { album in Button(album.name) {
                                        mutateSelection { id in
                                            let current = vault.items.first(where: { $0.id == id })?.albumIDs ?? []
                                            try await vault.setAlbums(current.union([album.id]), for: id)
                                        }
                                    } }
                                } label: { Image(systemName: "folder.badge.plus") }
                                    .disabled(vault.albums.isEmpty).accessibilityLabel("Add selected items to album")
                                Button { mutateSelection { try await vault.moveToTrash($0) } } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("Delete selected items")
                            }
                        }
                    }
                }
                .alert("New Album", isPresented: $createAlbum) {
                    TextField("Album name", text: $albumName)
                    Button("Create") { model.perform { _ = try await vault.createAlbum(name: albumName); albumName = "" } }
                        .disabled(albumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Cancel", role: .cancel) { albumName = "" }
                }
                .confirmationDialog("Import Photos", isPresented: $importNotice, titleVisibility: .visible) {
                    Button("Choose Photos") { picker = true }
                } message: {
                    Text("Originals stay in Apple Photos. iCloud photos may need a download.")
                }
                .photosPicker(isPresented: $picker, selection: $picks, maxSelectionCount: 20, matching: .images, preferredItemEncoding: .current)
                .onChange(of: picks) { _, items in Task { await importPhotos(items) } }
                .sheet(item: $opened) { MediaDetailScreen(itemID: $0.id) }
                .confirmationDialog("Permanently Delete Selected Items?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Permanently", role: .destructive) { mutateSelection { try await vault.permanentlyDelete($0) } }
                } message: { Text("These photos and videos will be permanently removed from Velvet. This can’t be undone.") }
                .onChange(of: vault.isUnlocked) { _, unlocked in
                    if !unlocked {
                        opened = nil; picker = false; picks = []; selected.removeAll()
                        albumName = ""; createAlbum = false; confirmDelete = false; importNotice = false
                    }
                }
        }
    }
    private var library: some View {
        VStack(spacing: 14) {
            if filter != "trash" && filter != "duplicates" {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All", value: "all"); filterChip("Photos", value: "photos")
                        filterChip("Videos", value: "videos"); filterChip("Favorites", value: "favorites")
                    }.padding(.horizontal, 20)
                }
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if let albumTitle { Text(albumTitle).font(.headline) }
                    else if filter == "trash" { Text("Recently Deleted").font(.headline) }
                    else if filter == "duplicates" { Text("Duplicates").font(.headline) }
                    Text(countText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if importing { ProgressView().accessibilityLabel("Importing photos") }
                if albumID != nil || filter == "trash" || filter == "duplicates" {
                    Button { albumID = nil; applyFilter("all") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Show all photos and videos")
                }
                if selecting && !visible.isEmpty {
                    Button(selected.count == visible.count ? "Deselect All" : "Select All") {
                        selected = selected.count == visible.count ? [] : Set(visible.map(\.id))
                    }.font(.subheadline)
                }
            }.padding(.horizontal, 20)
            if visible.isEmpty {
                EmptyLibrary(title: emptyTitle, subtitle: emptyDescription, symbol: filter == "trash" ? "trash" : "photo.on.rectangle")
                    .padding(.top, 20)
                if filter == "all" && albumID == nil {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { emptyActions }
                        VStack(spacing: 12) { emptyActions }
                    }.padding(.horizontal, 20)
                }
            } else {
                LazyVGrid(columns: VelvetTheme.photoColumns, spacing: VelvetTheme.gridSpacing) {
                    ForEach(visible) { item in
                        Button {
                            if selecting {
                                if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                            } else { opened = item }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VaultThumbnail(item: item).aspectRatio(1, contentMode: .fit)
                                if selecting {
                                    Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, selected.contains(item.id) ? VelvetTheme.accent : Color.black.opacity(0.3))
                                        .shadow(color: .black.opacity(0.35), radius: 2).padding(8)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel(item.title)
                            .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                }.padding(.horizontal, VelvetTheme.gridSpacing)
            }
            if filter == "trash" {
                Text("Items remain here until you permanently delete them.").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
        }
    }
    @ViewBuilder private var emptyActions: some View {
        Button("Open Camera") { model.tab = 0 }.buttonStyle(.glass)
        Button("Import Photos") { importNotice = true }.buttonStyle(.glassProminent)
    }
    private var albums: some View {
        VStack(alignment: .leading, spacing: 16) {
            if vault.albums.isEmpty {
                EmptyLibrary(title: "No Albums", subtitle: "Create an album to organize your photos and videos.", symbol: "rectangle.stack").padding(.top, 20)
                Button("New Album", systemImage: "plus") { createAlbum = true }.buttonStyle(.glassProminent).frame(maxWidth: .infinity)
            } else {
                Text("\(vault.albums.count) \(vault.albums.count == 1 ? "Album" : "Albums")").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 16)], alignment: .leading, spacing: 24) {
                    ForEach(vault.albums) { album in
                        let items = vault.items.filter { !$0.isTrashed && $0.albumIDs.contains(album.id) }.sorted { $0.createdAt > $1.createdAt }
                        Button { albumID = album.id; filter = "all"; browsingAlbums = false } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    VelvetTheme.surface
                                    if let cover = items.first { VaultThumbnail(item: cover, showsBadges: false) }
                                    else { Image(systemName: "rectangle.stack").font(.largeTitle).foregroundStyle(.tertiary) }
                                }.aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 16))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name).font(.headline).foregroundStyle(.primary).lineLimit(1)
                                    Text("\(items.count)").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(album.name), \(items.count) items")
                    }
                }
            }
        }.padding(.horizontal, 20)
    }
    private var emptyTitle: String {
        switch filter {
        case "trash": return "No Recently Deleted Items"
        case "duplicates": return "No Duplicates"
        case "favorites": return "No Favorites"
        case "videos": return "No Videos"
        case "photos": return "No Photos"
        default: return albumID == nil ? "No Photos or Videos" : "This Album Is Empty"
        }
    }
    private var emptyDescription: String {
        switch filter {
        case "trash": return "Items you delete will appear here."
        case "duplicates": return "No identical files were found."
        case "favorites": return "Tap the heart when viewing a photo or video to add it here."
        case "videos": return "Record a video with the camera to add it here."
        default: return albumID == nil ? "Take a photo or import from Apple Photos." : "Select items in the library and add them to this album."
        }
    }
    private func filterChip(_ title: String, value: String) -> some View {
        Button(title) { applyFilter(value) }.font(.subheadline.weight(filter == value ? .semibold : .regular))
            .buttonStyle(.glass).tint(filter == value ? VelvetTheme.accent : Color.secondary)
            .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
    private func applyFilter(_ value: String) { filter = value; selected.removeAll() }
    private func mutateSelection(_ operation: @escaping (UUID) async throws -> Void) {
        let ids = selected, session = model.sessionID
        selected.removeAll(); selecting = false
        model.perform { for id in ids {
            guard model.sessionID == session, vault.isUnlocked else { return }
            try await operation(id)
        } }
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
                guard vault.isUnlocked, model.sessionID == session else { return }
                await model.index(saved.id)
            } catch {
                guard vault.isUnlocked, model.sessionID == session else { return }
                model.error = "A photo could not be imported. It may be unavailable offline, too large, or in an unsupported format."
            }
        }
    }
}

struct VaultThumbnail: View {
    let item: VaultItem
    var showsBadges = true
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VelvetTheme.surface
                if let image { Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: item.kind == .video ? "video" : "photo").foregroundStyle(.secondary) }
                if showsBadges && (item.isFavorite || item.kind == .video) {
                    VStack { Spacer(); ZStack(alignment: .bottom) {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom).frame(height: 38)
                        HStack {
                            if item.isFavorite { Image(systemName: "heart.fill") }
                            Spacer()
                            if item.kind == .video { Text(Duration.seconds(item.duration ?? 0).formatted(.time(pattern: .minuteSecond))).monospacedDigit() }
                        }.font(.caption2.weight(.semibold)).foregroundStyle(.white).padding(7)
                    } }
                }
            }
        }.task(id: item.id) {
            let session = model.sessionID
            do {
                let data = try await vault.thumbnail(for: item.id)
                guard vault.isUnlocked, model.sessionID == session, !Task.isCancelled else { return }
                image = data.flatMap { UIImage(data: $0) }
            } catch { image = nil }
        }.onDisappear { image = nil }
            .onChange(of: vault.isUnlocked) { _, unlocked in if !unlocked { image = nil } }
    }
}
