import SwiftUI

struct SearchScreen: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var results: [SearchMatch] = []
    @State private var searching = false
    @State private var capability = "On-device visual search"
    @State private var opened: VaultItem?
    @State private var performedSearch = false
    @State private var requestID = UUID()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "sparkle.magnifyingglass").font(.system(size: 36, weight: .light)).foregroundStyle(VelvetTheme.accent).padding(.bottom, 8)
                        Text("Find the feeling.").font(.system(.largeTitle, design: .serif))
                        Text("Describe a moment. Search stays here.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.top, 20)
                    if searching { ProgressView("Searching privately…") }
                    if !performedSearch {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TRY A DESCRIPTION").font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(.secondary)
                            ForEach(["Portraits next to a window", "Warm light and red clothing", "Outside at night", "A black background"], id: \.self) { text in
                                Button { query = text } label: { HStack { Text(text); Spacer(); Image(systemName: "arrow.up.left").foregroundStyle(.secondary) }.padding(.vertical, 10) }.foregroundStyle(.primary)
                                Divider()
                            }
                        }
                    } else if results.isEmpty && !searching {
                        EmptyLibrary(title: "No matching memories", subtitle: "Try another description, or index your library in Settings.", symbol: "magnifyingglass")
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 12) {
                        ForEach(results, id: \.id) { result in
                            if let item = vault.items.first(where: { $0.id == result.id && $0.trashedAt == nil }) {
                                Button { opened = item } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        VaultThumbnail(item: item).aspectRatio(1, contentMode: .fit).clipShape(.rect(cornerRadius: 14))
                                        Text(item.title).font(.caption).lineLimit(1).foregroundStyle(.primary)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Text(capability).font(.caption).foregroundStyle(.secondary)
                    PrivacyFootnote(text: "Encrypted search features. No query history. No cloud inference.")
                }.padding(20)
            }.background(.black).navigationTitle("Search")
                .searchable(text: $query, prompt: "Describe a photo or video cover")
                .task(id: query) { await search() }
                .task { capability = await model.search.capabilityDescription }
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
            capability = await model.search.capabilityDescription
        } catch is CancellationError {} catch {
            guard model.sessionID == session, vault.isUnlocked, requestID == request else { return }
            model.error = "Search is unavailable. Try reindexing the library in Settings."
        }
    }
}
