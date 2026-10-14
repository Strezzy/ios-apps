import SwiftUI
import PhotosUI

struct CreateView: View {
    @EnvironmentObject private var store: StudioStore
    @State private var photoSelection: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showFormats = false
    @State private var showPrivacy = false
    @State private var sharingExport: ExportResult?

    var body: some View {
        ZStack {
            StudioBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if store.isImporting {
                        importingCard
                    } else if let source = store.selectedSource {
                        sourceCard(source)
                    } else {
                        importCard
                    }
                    if let source = store.selectedSource {
                        formatCard(source)
                        depthCard
                        if store.isConverting { conversionCard }
                        else { createButton }
                        if let export = store.latestExport { completedCard(export) }
                    }
                    if let note = store.activityNote, store.latestExport == nil {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 680)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Facet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPrivacy = true } label: {
                    Label("Privacy", systemImage: "lock.shield")
                }
                .accessibilityLabel("Privacy")
                .accessibilityIdentifier("privacyButton")
            }
        }
        .sheet(isPresented: $showPrivacy) { PrivacyInfoView() }
        .sheet(isPresented: $showFormats) {
            OutputFormatPicker(selection: $store.options.format)
        }
        .sheet(item: $sharingExport) { export in
            ExportShareSheet(files: export.files)
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: MediaImporter.allowedContentTypes, allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let first = urls.first { store.importFile(first) }
            case .failure(let error): store.reportImportError(error)
            }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            store.importPhotoSelection(selection)
            photoSelection = nil
        }
    }

    private var importCard: some View {
        GlassCard(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(DepthCheckTheme.accent.opacity(0.07))
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular.tint(DepthCheckTheme.accent.opacity(0.13)), in: RoundedRectangle(cornerRadius: 20))
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(DepthCheckTheme.accent)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Choose a photo or video")
                        .font(.title2.weight(.semibold))
                }
                VStack(spacing: 12) {
                    photosButton(prominent: true)
                    Button { showFileImporter = true } label: {
                        Label("Choose from Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.glass)
                }
                Text("For RAW originals, choose Files.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func photosButton(prominent: Bool) -> some View {
        let picker = PhotosPicker(selection: $photoSelection, matching: .any(of: [.images, .videos]), preferredItemEncoding: .current) {
            Label(prominent ? "Choose from Photos" : "Photos", systemImage: "photo.on.rectangle")
                .foregroundStyle(prominent ? DepthCheckTheme.primaryButtonInk : DepthCheckTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, prominent ? 9 : 5)
        }
        if prominent { picker.buttonStyle(.glassProminent) }
        else { picker.buttonStyle(.glass) }
    }

    private var importingCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                ProgressView().controlSize(.large).padding(.top, 4)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Importing…").font(.headline)
                    Text("Large files and iCloud downloads may take a moment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func sourceCard(_ source: MediaSource) -> some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Eyebrow(text: "Source", symbol: source.kind == .video ? "video" : "photo")
                    Spacer()
                    Button { store.removeSource() } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).frame(width: 32, height: 32)
                    }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel("Remove selected source")
                        .disabled(store.isBusy)
                }
                Group {
                    if let thumbnail = store.sourceThumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 310)
                    } else {
                        Image(systemName: source.kind == .video ? "video" : "photo")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                    }
                }
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 17))
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityLabel("Original \(source.kind == .video ? "video" : "photo") preview")
                VStack(alignment: .leading, spacing: 9) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { sourceMetadata(source) }
                        VStack(alignment: .leading, spacing: 8) { sourceMetadata(source) }
                    }
                }
                HStack(spacing: 10) {
                    photosButton(prominent: false)
                    Button { showFileImporter = true } label: {
                        Label("Files", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(.glass)
                }
                .disabled(store.isBusy)
            }
        }
    }

    @ViewBuilder
    private func sourceMetadata(_ source: MediaSource) -> some View {
        MetadataPill(text: source.size.label, symbol: "arrow.up.left.and.arrow.down.right")
        if source.kind == .video {
            MetadataPill(text: "\(StudioFormat.fps(source.frameRate)) fps", symbol: "film")
            MetadataPill(text: StudioFormat.duration(source.duration), symbol: "clock")
        } else {
            MetadataPill(text: source.url.pathExtension.uppercased(), symbol: "doc")
        }
    }

    private func formatCard(_ source: MediaSource) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Output format")
                Button { showFormats = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: store.options.format.symbol)
                            .font(.title2)
                            .foregroundStyle(DepthCheckTheme.accent)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(store.options.format.title).font(.headline).foregroundStyle(.primary)
                            Text(store.options.format.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Output format, \(store.options.format.title). Change format")
                .disabled(store.isBusy)
                Divider().overlay(.white.opacity(0.06))
                QualityFacts(source: source, options: store.options)
            }
        }
    }

    private var depthCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Depth strength").font(.headline)
                    Spacer()
                    Text((store.options.depthAmount / 0.05).formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(DepthCheckTheme.accent)
                        .contentTransition(.numericText())
                }
                Slider(value: $store.options.depthAmount, in: 0...0.05)
                    .accessibilityLabel("Depth strength")
                    .accessibilityValue((store.options.depthAmount / 0.05).formatted(.percent.precision(.fractionLength(0))))
                HStack {
                    Text("Low")
                    Spacer()
                    Text("High")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Higher strength can reveal edge artifacts and video wobble.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button { store.selectedTab = .settings } label: {
                    HStack {
                        Label("More settings", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.vertical, 5)
                }
                .buttonStyle(.glass)
            }
            .disabled(store.isBusy)
        }
    }

    private var createButton: some View {
        Button { store.startConversion() } label: {
            HStack(spacing: 11) {
                Image(systemName: "square.3.layers.3d")
                Text("Create 3D \(store.selectedSource?.kind == .video ? "Video" : "Photo")")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .foregroundStyle(DepthCheckTheme.primaryButtonInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glassProminent)
        .disabled(store.isBusy)
        .accessibilityHint("Converts the original media using the selected depth model and output format")
    }

    private var conversionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow(text: store.isCancelling ? "Stopping" : "Converting", symbol: "square.3.layers.3d")
                    Spacer()
                    Text(StudioFormat.percentage(store.progress?.fraction ?? 0))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                Text(store.isCancelling ? "Finishing the current operation…" : store.progress?.stage ?? "Preparing…")
                    .font(.headline)
                ProgressView(value: min(1, max(0, store.progress?.fraction ?? 0)))
                    .tint(DepthCheckTheme.accent)
                if let progress = store.progress, progress.framesProcessed > 0 {
                    Text(progress.totalFramesEstimate > 0 ? "\(progress.framesProcessed.formatted()) of about \(progress.totalFramesEstimate.formatted()) frames" : "\(progress.framesProcessed.formatted()) frames processed")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                InfoNote(text: "Keep Facet open until conversion finishes.", symbol: "iphone")
                Button(role: .cancel) { store.cancelConversion() } label: {
                    Text(store.isCancelling ? "Stopping…" : "Cancel conversion")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.glass)
                .disabled(store.isCancelling)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func completedCard(_ export: ExportResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 15) {
                Label("Export ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(DepthCheckTheme.accent)
                Text("\(export.format.title) · \(export.size.label)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { store.selectedTab = .exports } label: {
                        Label("View export", systemImage: "square.stack")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    Button { sharingExport = export } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .foregroundStyle(DepthCheckTheme.primaryButtonInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
    }

}

struct OutputFormatPicker: View {
    @Binding var selection: OutputFormat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StudioBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(OutputFormat.allCases) { format in
                            Button {
                                selection = format
                                dismiss()
                            } label: {
                                GlassCard(padding: 18) {
                                    HStack(alignment: .center, spacing: 15) {
                                        Image(systemName: format.symbol)
                                            .font(.title2)
                                            .foregroundStyle(DepthCheckTheme.accent)
                                            .frame(width: 36)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(format.title).font(.headline).foregroundStyle(.primary)
                                            Text(format.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: selection == format ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selection == format ? DepthCheckTheme.accent : .secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(format.title). \(format.detail)")
                            .accessibilityValue(selection == format ? "Selected" : "")
                        }
                    }
                    .frame(maxWidth: 680)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Export format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(DepthCheckTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}
