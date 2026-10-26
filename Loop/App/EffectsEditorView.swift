import SwiftUI
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import UIKit

@MainActor private final class EffectGallery: ObservableObject {
    @Published var thumbnails: [String: CGImage] = [:]
    @Published var message: String?
    @Published var loading = false
    private var task: Task<Void, Never>?
    private var generation = UUID()
    func cancel() { generation = UUID(); task?.cancel(); task = nil; loading = false }
    func refresh(source: CGImage?, category: EffectCategory, time: Double, custom: Data?) {
        cancel(); thumbnails = [:]; message = nil
        guard let source else { message = "Move the playhead to load a frame, then tap Refresh previews."; return }
        let token = UUID(); generation = token; loading = true
        task = Task { [weak self] in
            defer { if self?.generation == token { self?.loading = false } }
            do {
                let prepared = try await Task.detached(priority: .utility) { () throws -> (CGImage, EffectsAnalysis) in
                    guard let small = OfflineEffectsRenderer.boundedImage(source, edge: 320) else { throw LoopError.encoding("The gallery frame could not be resized.") }
                    let analysis = try OfflineEffectsRenderer.analyze(CIImage(cgImage: small), faces: category == .face,
                        person: category == .body || category == .background || category == .atmosphere, preview: true, body: category == .body)
                    return (small, analysis)
                }.value
                guard !Task.isCancelled, self?.generation == token else { return }
                if category == .face && prepared.1.faces.isEmpty { self?.message = "No clear face in this frame. Try a front-facing frame for face previews." }
                for preset in EffectLibrary.inCategory(category) {
                    guard !Task.isCancelled, self?.generation == token else { return }
                    let image = try await Task.detached(priority: .utility) {
                        try autoreleasepool {
                            try OfflineEffectsRenderer.thumbnail(prepared.0, preset: preset, time: time, analysis: prepared.1, custom: custom)
                        }
                    }.value
                    guard !Task.isCancelled, self?.generation == token else { return }
                    self?.thumbnails[preset.id] = image
                    await Task.yield()
                }
            } catch {
                if self?.generation == token && !Task.isCancelled { self?.message = error.localizedDescription }
            }
        }
    }
}

struct EffectsEditorView: View {
    @Binding var project: LoopProject
    @ObservedObject var preview: EditorPreview
    @State private var category: EffectCategory = .looks
    @State private var search = ""
    @State private var favoritesOnly = false
    @AppStorage("loop.effectFavorites") private var favorites = ""
    @StateObject private var gallery = EffectGallery()
    @State private var importingBackground = false
    @State private var importError: String?
    @State private var loadingBackground = false
    @State private var addAnother = false
    private var settings: EffectSettings { project.effects ?? EffectSettings() }
    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }
    private var selected: EffectLayer? { settings.layer(category) }
    private var visible: [EffectPreset] {
        EffectLibrary.inCategory(category).filter {
            (!favoritesOnly || favoriteIDs.contains($0.id)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }
    private func change(_ update: (inout EffectSettings) -> Void) {
        var value = settings; update(&value); project.effects = value
    }
    var body: some View {
        VStack(spacing: 16) {
            CreativeToolsView(project: $project, preview: preview)
            LoopCard {
                EditorSectionTitle(title: "Choose an effect", subtitle: "All effects stay on your iPhone")
                HStack {
                    Toggle("Compare original", isOn: Binding(get: { settings.bypass }, set: { newValue in change { $0.bypass = newValue } }))
                        .font(.subheadline).accessibilityIdentifier("effectsBypass")
                    Button("Reset", systemImage: "arrow.counterclockwise") { project.effects = nil }
                        .labelStyle(.iconOnly).buttonStyle(.glass).accessibilityLabel("Remove all effects")
                }
                if !settings.visibleTracks.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(EffectCategory.allCases) { group in
                                if let layer = settings.layer(group), let preset = EffectLibrary.preset(layer.preset) {
                                    Button { category = group } label: { Label(preset.name, systemImage: group.symbol).font(.caption) }
                                        .buttonStyle(.glass).tint(group == category ? LoopTheme.teal : .secondary)
                                }
                            }
                        }.padding(2)
                    }
                }
                Text("Tap to try an effect. Use My effect mix above to combine effects or change when they appear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LoopCard {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(EffectCategory.allCases) { item in
                            Button { category = item } label: { Label(item.title, systemImage: item.symbol).font(.subheadline.weight(.medium)) }
                                .buttonStyle(.glass).tint(category == item ? LoopTheme.teal : .secondary)
                                .accessibilityIdentifier("effectCategory-\(item.rawValue)")
                                .accessibilityAddTraits(category == item ? .isSelected : [])
                        }
                    }.padding(2)
                }
                Text(category.guidance).font(.caption).foregroundStyle(.secondary)
                Toggle("Add another effect instead of replacing", isOn: $addAnother).font(.caption)
                RealismControls(settings: Binding(get: { settings }, set: { project.effects = $0 }), category: category)
                if selected != nil {
                    ValueSlider(title: "Intensity", value: Binding(get: { selected?.amount ?? 1 }, set: { value in change { $0.setAmount(value, category: category) } }), range: 0...1,
                                display: "\(Int((selected?.amount ?? 1) * 100))%")
                    Button("Remove \(category.title.lowercased()) effect", systemImage: "xmark.circle") { change { $0.select(nil, category: category) } }
                        .font(.caption).buttonStyle(.glass)
                }
                if category == .background {
                    Button { importingBackground = true } label: {
                        Label(loadingBackground ? "Preparing background…" : "Choose your own background photo", systemImage: "photo.badge.plus")
                    }.font(.subheadline).buttonStyle(.glass).disabled(loadingBackground)
                    if settings.backgroundImage != nil {
                        Button("Remove imported photo", role: .destructive) {
                            change { $0.backgroundImage = nil; if $0.layer(.background)?.preset == "customBackground" { $0.select(nil, category: .background) } }
                            refresh()
                        }.font(.caption)
                    }
                }
                HStack {
                    TextField("Search \(category.title.lowercased())", text: $search)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("effectSearch")
                    Button { favoritesOnly.toggle() } label: { Image(systemName: favoritesOnly ? "star.fill" : "star") }
                        .buttonStyle(.glass).accessibilityLabel(favoritesOnly ? "Show all effects" : "Show favorites")
                }
                HStack {
                    Button("Refresh previews", systemImage: "arrow.clockwise") { refresh() }.font(.caption).buttonStyle(.glass)
                    Spacer()
                    if gallery.loading { ProgressView().controlSize(.small) }
                    Text("\(visible.count) effects").font(.caption2).foregroundStyle(.secondary)
                }
                Text("Gallery thumbnails use a still frame. Tap an effect and play the main preview to see it in motion.")
                    .font(.caption2).foregroundStyle(.secondary)
                if let message = gallery.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 14) {
                    ForEach(visible) { preset in tile(preset) }
                }
                if visible.isEmpty { Text("No matching effects in this category.").font(.subheadline).foregroundStyle(.secondary).padding() }
            }
        }
        .onAppear { refresh() }
        .onChange(of: category) { _, _ in search = ""; refresh() }
        .onDisappear { gallery.cancel() }
        .fileImporter(isPresented: $importingBackground, allowedContentTypes: [.image], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { importBackground(url) }
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .alert("Background photo", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }
    private func tile(_ preset: EffectPreset) -> some View {
        VStack(spacing: 7) {
            Button {
                if preset.id == "customBackground" && settings.backgroundImage == nil { importingBackground = true }
                else { change {
                    $0.moveLegacyToMix()
                    if addAnother { $0.add(preset.id, target: $0.scene?.selectedID == nil ? "all" : "subject", subjectID: $0.scene?.selectedID) }
                    else { $0.select(preset.id, category: category) }
                    $0.bypass = false
                }; addAnother = false }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Rectangle().fill(LoopTheme.teal.opacity(0.08))
                    if let image = gallery.thumbnails[preset.id] {
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                    } else { Image(systemName: category.symbol).font(.title2).foregroundStyle(LoopTheme.teal).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    if selected?.preset == preset.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, LoopTheme.teal).padding(7) }
                }.frame(height: 100).clipped().clipShape(.rect(cornerRadius: 15))
                    .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(selected?.preset == preset.id ? LoopTheme.teal : .clear, lineWidth: 2) }
            }.buttonStyle(.plain).accessibilityLabel(preset.name).accessibilityIdentifier("effect-\(preset.id)")
                .accessibilityAddTraits(selected?.preset == preset.id ? .isSelected : [])
            HStack(spacing: 3) {
                Text(preset.name).font(.caption.weight(.medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    var ids = favoriteIDs
                    if ids.contains(preset.id) { ids.remove(preset.id) } else { ids.insert(preset.id) }
                    favorites = ids.sorted().joined(separator: ",")
                } label: { Image(systemName: favoriteIDs.contains(preset.id) ? "star.fill" : "star").font(.caption).padding(.vertical, 5) }
                    .buttonStyle(.plain).foregroundStyle(LoopTheme.teal).accessibilityLabel("Favorite \(preset.name)")
            }
        }
    }
    private func refresh() {
        gallery.refresh(source: preview.sourceFrame, category: category, time: preview.displayedTime, custom: settings.backgroundImage)
    }
    private func importBackground(_ url: URL) {
        loadingBackground = true
        Task {
            defer { loadingBackground = false }
            do {
                let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let bytes = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard bytes <= 64_000_000 else { throw LoopError.invalidSettings("Choose a background photo smaller than 64 MB.") }
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                        throw LoopError.invalidSettings("This image could not be opened.")
                    }
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw LoopError.encoding("The background could not be saved.") }
                    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
                    guard CGImageDestinationFinalize(destination), data.length <= 8_000_000 else { throw LoopError.invalidSettings("Choose a smaller background photo.") }
                    return data as Data
                }.value
                change { $0.backgroundImage = data; $0.select("customBackground", category: .background); $0.bypass = false }
                refresh()
            } catch { importError = error.localizedDescription }
        }
    }
}
