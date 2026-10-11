import SwiftUI
import QuickLook
import UIKit

struct ExportShareSheet: UIViewControllerRepresentable {
    let files: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Pass file URLs, never decoded UIImage or whole-video Data objects.
        UIActivityViewController(activityItems: files, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportPreviewView: View {
    @EnvironmentObject private var store: StudioStore
    @Environment(\.dismiss) private var dismiss
    let export: ExportResult
    @State private var showingShare = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Eyebrow(text: export.format.title, symbol: export.format.symbol)
                        Spacer()
                        Text(export.size.label)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if export.format != .anaglyph && export.format != .depthMap {
                        InfoNote(text: "This file preview may appear flat. Open a compatible 3D viewer or headset for stereo playback.", symbol: "eyeglasses")
                    }
                    if !export.note.isEmpty {
                        Text(export.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                QuickLookFiles(files: export.files)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background { StudioBackground() }
            .navigationTitle(export.sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { showingShare = true } label: {
                        Label(export.files.count > 1 ? "Share both files" : "Share", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button { store.saveToPhotos(export) } label: {
                        Label("Save to Photos", systemImage: "photo.badge.plus")
                    }
                    .disabled(store.isSavingToPhotos)
                }
            }
            .sheet(isPresented: $showingShare) { ExportShareSheet(files: export.files) }
        }
        .tint(DepthCheckTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear { store.previewIsPresented = true }
        .onDisappear { store.previewIsPresented = false }
        .alert(item: $store.alert) { alert in
            alert.systemAlert
        }
    }
}

private struct QuickLookFiles: UIViewControllerRepresentable {
    let files: [URL]

    func makeCoordinator() -> Coordinator { Coordinator(files: files) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.files != files else { return }
        context.coordinator.files = files
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var files: [URL]

        init(files: [URL]) { self.files = files }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { files.count }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            files[index] as NSURL
        }
    }
}
