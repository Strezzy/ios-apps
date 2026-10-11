import SwiftUI
import UIKit

struct ExportsView: View {
    @EnvironmentObject private var store: StudioStore
    @State private var previewingExport: ExportResult?
    @State private var sharingExport: ExportResult?
    @State private var deletingExport: ExportResult?

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Made on your iPhone", symbol: "square.stack")
                        Text("A new point of view.")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .tracking(-0.8)
                        Text(store.exports.isEmpty ? "Your finished photos and videos will be right here." : "\(store.exports.count.formatted()) \(store.exports.count == 1 ? "export" : "exports") · Ready to save, share, or explore.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if store.exports.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 19) {
                            ForEach(store.exports) { export in
                                ExportCard(
                                    export: export,
                                    available: store.filesAreAvailable(export),
                                    onPreview: { previewingExport = export },
                                    onShare: { sharingExport = export },
                                    onDelete: { deletingExport = export }
                                )
                            }
                        }
                        InfoNote(text: "Exports are also available in Files → On My iPhone → Depth Check → Exports.", symbol: "folder")
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Exports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.selectedTab = .create } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create an export")
            }
        }
        .sheet(item: $previewingExport) { export in
            ExportPreviewView(export: export)
        }
        .sheet(item: $sharingExport) { export in
            ExportShareSheet(files: export.files)
        }
        .confirmationDialog("Delete this export?", isPresented: Binding(get: { deletingExport != nil }, set: { if !$0 { deletingExport = nil } }), titleVisibility: .visible) {
            if let export = deletingExport {
                Button("Delete export", role: .destructive) {
                    store.deleteExport(export)
                    deletingExport = nil
                }
            }
            Button("Cancel", role: .cancel) { deletingExport = nil }
        } message: {
            Text("This removes the exported files from Depth Check. Copies already saved to Photos or shared elsewhere are kept.")
        }
    }

    private var emptyState: some View {
        GlassCard(padding: 28) {
            VStack(alignment: .leading, spacing: 19) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 45, weight: .light))
                    .foregroundStyle(DepthCheckTheme.accent)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
                Text("Your first perspective awaits.")
                    .font(.title2.weight(.semibold))
                Text("Turn a favorite photo or video into spatial media, full side-by-side, or another 3D format.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { store.selectedTab = .create } label: {
                    Label("Create something", systemImage: "plus")
                        .foregroundStyle(DepthCheckTheme.primaryButtonInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

private struct ExportCard: View {
    @EnvironmentObject private var store: StudioStore
    let export: ExportResult
    let available: Bool
    let onPreview: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow(text: export.format.title, symbol: export.format.symbol)
                        Text(export.sourceName)
                            .font(.headline)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button(action: onPreview) { Label("Preview", systemImage: "eye") }.disabled(!available)
                        Button(action: onShare) { Label("Share original export", systemImage: "square.and.arrow.up") }.disabled(!available)
                        Button { store.saveToPhotos(export) } label: { Label("Save to Photos", systemImage: "photo.badge.plus") }.disabled(!available || store.isSavingToPhotos)
                        Divider()
                        Button(role: .destructive, action: onDelete) { Label("Delete export", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Export actions")
                }
                Button(action: onPreview) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 230)
                            } else {
                                Image(systemName: available ? export.format.symbol : "externaldrive.badge.exclamationmark")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 140)
                            }
                        }
                        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                        if available {
                            Label(isVideo ? "Play" : "Preview", systemImage: isVideo ? "play.fill" : "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .glassEffect(.regular, in: Capsule())
                                .padding(10)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .accessibilityLabel("Preview \(export.sourceName), \(export.format.title)")
                VStack(alignment: .leading, spacing: 7) {
                    Text(metadata)
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(DepthCheckTheme.accent.opacity(0.9))
                    Text(export.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !available {
                        Text("An export file has been moved or deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if available {
                    HStack(spacing: 10) {
                        Button(action: onShare) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .foregroundStyle(DepthCheckTheme.primaryButtonInk)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.glassProminent)
                        Button { store.saveToPhotos(export) } label: {
                            Label("Save to Photos", systemImage: "photo.badge.plus")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.glass)
                        .disabled(store.isSavingToPhotos)
                    }
                    .font(.subheadline.weight(.medium))
                }
            }
        }
        .task(id: export.id) {
            guard available, let url = export.files.first else { return }
            let source = MediaSource(url: url, name: export.sourceName, kind: isVideo ? .video : .photo, size: export.size, frameRate: export.frameRate, duration: export.duration)
            thumbnail = await MediaImporter.thumbnail(for: source, maximumDimension: 1100)
        }
    }

    private var isVideo: Bool { export.frameRate > 0 || export.frameCount > 1 || export.duration > 0 }

    private var metadata: String {
        var text = export.size.label
        if isVideo { text += " · \(StudioFormat.fps(export.frameRate)) fps" }
        if export.files.count > 1 { text += " · \(export.files.count) files" }
        return text
    }
}
