import SwiftUI
import AVKit

struct MediaDetailScreen: View {
    let itemID: UUID
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var playback: SecureVideoPlayback?
    @State private var info = false
    @State private var title = ""
    @State private var note = ""
    @State private var magnification: CGFloat = 1
    @State private var loadingError: String?
    @State private var displayedItemID: UUID?
    @State private var showingSimilar = false
    private var currentID: UUID { displayedItemID ?? itemID }
    private var item: VaultItem? { vault.items.first { $0.id == currentID } }
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let playback { VideoPlayer(player: playback.player).ignoresSafeArea(edges: .bottom) }
                else if let image {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .containerRelativeFrame(.horizontal).scaleEffect(magnification)
                            .gesture(MagnifyGesture().onChanged { magnification = min(max($0.magnification, 1), 5) })
                            .onTapGesture(count: 2) { withAnimation { magnification = magnification == 1 ? 2 : 1 } }
                    }.defaultScrollAnchor(.center)
                } else if let loadingError { ContentUnavailableView("Unable to open", systemImage: "exclamationmark.lock", description: Text(loadingError)) }
                else { ProgressView().tint(.white) }
            }.navigationTitle(item?.title ?? "Photo").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { if let item { model.perform { try await vault.setFavorite(!item.isFavorite, for: item.id) } } } label: { Image(systemName: item?.isFavorite == true ? "heart.fill" : "heart") }
                        Button { title = item?.title ?? ""; note = item?.note ?? ""; info = true } label: { Image(systemName: "info.circle") }
                        if item?.trashedAt == nil {
                            Button { showingSimilar = true } label: { Image(systemName: "square.on.square") }
                                .accessibilityLabel("Find similar photos")
                                .disabled(model.aiBusy || model.camera.isRecording || model.camera.isCapturing)
                            Button { let id = currentID; model.perform { try await vault.moveToTrash(id); dismiss() } } label: { Image(systemName: "trash") }
                        }
                    }
                }.sheet(isPresented: $info) { details }
                .sheet(isPresented: $showingSimilar) {
                    SimilarMediaSheet(referenceID: currentID) { id in
                        displayedItemID = id
                        showingSimilar = false
                    }
                }
                .task(id: currentID) { await load() }
                .onDisappear { playback?.invalidate(); playback = nil; image = nil }
                .onChange(of: vault.isUnlocked) { _, unlocked in if !unlocked {
                    playback?.invalidate(); playback = nil; image = nil
                    showingSimilar = false; info = false; title = ""; note = ""; dismiss()
                } }
        }
    }
    private var details: some View {
        NavigationStack {
            Form {
                Section("Notes") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $note, axis: .vertical).lineLimit(3...8)
                }
                if let item {
                    Section("Original") {
                        LabeledContent("Captured", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Format", value: item.fileExtension.uppercased())
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
                        if let w = item.width, let h = item.height { LabeledContent("Dimensions", value: "\(w) × \(h)") }
                        if let duration = item.duration { LabeledContent("Duration", value: Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond))) }
                    }
                    if !vault.albums.isEmpty {
                        Section("Albums") { ForEach(vault.albums) { album in
                            Toggle(album.name, isOn: Binding(get: { item.albumIDs.contains(album.id) }, set: { enabled in model.perform {
                                var albums = item.albumIDs; if enabled { albums.insert(album.id) } else { albums.remove(album.id) }
                                try await vault.setAlbums(albums, for: item.id)
                            } }))
                        } }
                    }
                }
            }.navigationTitle("Details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    let id = currentID, savedTitle = title, savedNote = note
                    model.perform { try await vault.rename(savedTitle, note: savedNote, for: id); info = false }
                } } }
        }
    }
    private func load() async {
        guard let item else { return }
        let requestedID = item.id, session = model.sessionID
        playback?.invalidate(); playback = nil; image = nil; loadingError = nil; magnification = 1
        do {
            if item.kind == .video {
                let reader = try await vault.videoReader(for: requestedID)
                guard model.sessionID == session, currentID == requestedID, vault.isUnlocked, !Task.isCancelled else { return }
                playback = SecureVideoPlayback(reader: reader)
            } else {
                let data = try await vault.original(for: requestedID)
                guard model.sessionID == session, currentID == requestedID, vault.isUnlocked, !Task.isCancelled else { return }
                image = UIImage(data: data)
                if image == nil { loadingError = "This original could not be decoded on this device." }
            }
        } catch {
            guard model.sessionID == session, currentID == requestedID, vault.isUnlocked, !Task.isCancelled else { return }
            loadingError = "Authentication or media validation failed. No unverified content was displayed."
        }
    }
}

/// Selects a new item in the existing viewer, avoiding recursively nested detail sheets.
private struct SimilarMediaSheet: View {
    let referenceID: UUID
    let select: (UUID) -> Void
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var matches: [SearchMatch] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Similar photos and video covers.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                    if loading { ProgressView("Finding similar items…").frame(maxWidth: .infinity).padding(.vertical, 32) }
                    else if matches.isEmpty {
                        EmptyLibrary(title: "No Similar Items", subtitle: message ?? "Update the search index in Settings, then try again.", symbol: "square.on.square")
                    }
                    LazyVGrid(columns: VelvetTheme.photoColumns, spacing: VelvetTheme.gridSpacing) {
                        ForEach(matches) { match in
                            if let item = vault.items.first(where: { $0.id == match.id && !$0.isTrashed }) {
                                Button { select(item.id) } label: {
                                    VaultThumbnail(item: item).aspectRatio(1, contentMode: .fit)
                                }.buttonStyle(.plain).accessibilityLabel("Open \(item.title)")
                            }
                        }
                    }.padding(.horizontal, VelvetTheme.gridSpacing)
                }.padding(.vertical, 16)
            }.background(.black).navigationTitle("Similar").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task(id: referenceID) { await findSimilar() }
                .onChange(of: vault.isUnlocked) { _, unlocked in if !unlocked { matches = []; dismiss() } }
        }
    }

    private func findSimilar() async {
        let session = model.sessionID
        guard vault.isUnlocked, !model.camera.isRecording, !model.camera.isCapturing else { loading = false; return }
        loading = true; matches = []; message = nil
        model.beginSearch()
        defer { model.endSearch(); loading = false }
        do {
            var documents = try await vault.searchDocuments()
            guard model.sessionID == session, vault.isUnlocked, !Task.isCancelled else { return }
            if !documents.contains(where: { $0.id == referenceID }) {
                await model.index(referenceID)
                documents = try await vault.searchDocuments()
            }
            guard model.sessionID == session, vault.isUnlocked, !Task.isCancelled else { return }
            guard let reference = documents.first(where: { $0.id == referenceID }) else {
                message = "This item has not been indexed. Update the search index in Settings, then try again."
                return
            }
            let found = await model.search.similar(to: reference, in: documents)
            guard model.sessionID == session, vault.isUnlocked, !Task.isCancelled else { return }
            matches = Array(found.prefix(60))
        } catch {
            guard model.sessionID == session, vault.isUnlocked, !Task.isCancelled else { return }
            message = "Visual search is temporarily unavailable. Try again after reindexing your library."
        }
    }
}
