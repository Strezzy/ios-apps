import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var results: [SearchMatch] = []
    @State private var searching = false
    @State private var opened: VaultItem?
    @State private var performedSearch = false
    @State private var requestID = UUID()
    private let suggestions = ["Portraits", "Warm light", "Outdoors", "At night", "Blue lighting", "Documents"]
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var displayedItems: [VaultItem] {
        let items = Dictionary(uniqueKeysWithValues: vault.items.filter { !$0.isTrashed }.map { ($0.id, $0) })
        return results.compactMap { items[$0.id] }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !hasQuery {
                        VStack(alignment: .leading, spacing: 24) {
                            Text("Describe a photo or video cover.").font(.subheadline).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Suggestions").font(.headline)
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                                    ForEach(suggestions, id: \.self) { text in
                                        Button { query = text } label: {
                                            HStack(spacing: 8) {
                                                Text(text).multilineTextAlignment(.leading)
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                                        }.font(.subheadline).buttonStyle(.glass).foregroundStyle(.primary)
                                    }
                                }
                            }
                        }.padding(.horizontal, 20)
                    } else {
                        HStack {
                            if performedSearch { Text("\(displayedItems.count) \(displayedItems.count == 1 ? "Result" : "Results")").font(.subheadline).foregroundStyle(.secondary) }
                            Spacer()
                            if searching { ProgressView().accessibilityLabel("Searching") }
                        }.padding(.horizontal, 20)
                        if performedSearch && displayedItems.isEmpty && !searching {
                            EmptyLibrary(title: "No Results", subtitle: "Try another description. You can update the search index in Settings.", symbol: "magnifyingglass")
                                .padding(.top, 24)
                        }
                    }
                    LazyVGrid(columns: VelvetTheme.photoColumns, spacing: VelvetTheme.gridSpacing) {
                        ForEach(displayedItems) { item in
                            Button { opened = item } label: {
                                VaultThumbnail(item: item).aspectRatio(1, contentMode: .fit)
                            }.buttonStyle(.plain).accessibilityLabel(item.title)
                        }
                    }.padding(.horizontal, VelvetTheme.gridSpacing)
                }.padding(.top, 12).padding(.bottom, 24)
            }.background(.black).navigationTitle("Search")
                .searchable(text: $query, prompt: "Describe a photo or video cover")
                .task(id: query) { await search() }
                .sheet(item: $opened) { MediaDetailScreen(itemID: $0.id) }
                .onChange(of: vault.isUnlocked) { _, unlocked in
                    if !unlocked { query = ""; results = []; opened = nil; performedSearch = false; requestID = UUID() }
                }
        }
    }
    private func search() async {
        let request = UUID()
        requestID = request
        let session = model.sessionID
        let text = query
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { results = []; performedSearch = false; searching = false; return }
        guard vault.isUnlocked, !model.camera.isRecording, !model.camera.isCapturing else { return }
        searching = true
        model.beginSearch()
        defer {
            model.endSearch()
            if requestID == request { searching = false }
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let documents = try await vault.searchDocuments()
            guard model.sessionID == session, vault.isUnlocked, requestID == request, !Task.isCancelled,
                  !model.camera.isRecording, !model.camera.isCapturing else { return }
            let found = try await model.search.search(query: text, documents: documents)
            guard model.sessionID == session, vault.isUnlocked, requestID == request, !Task.isCancelled else { return }
            results = found; performedSearch = true
        } catch is CancellationError {} catch {
            guard model.sessionID == session, vault.isUnlocked, requestID == request else { return }
            model.error = "Search is unavailable. Try reindexing the library in Settings."
        }
    }
}
