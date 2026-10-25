import SwiftUI
import UIKit

struct EditorView: View {
    @EnvironmentObject private var store: LoopStore
    @Environment(\.dismiss) private var dismiss
    @State private var project: LoopProject
    @StateObject private var preview = EditorPreview()
    @State private var tool: EditorTool = .clip
    @State private var selectedOverlay: UUID?
    @State private var showingResult = false
    @State private var exported: SavedExport?
    @State private var rename = false
    @State private var title = ""
    @State private var undoHistory: [LoopProject] = []
    @State private var redoHistory: [LoopProject] = []
    @State private var applyingHistory = false
    @State private var lastEdit = Date.distantPast
    @State private var keyboardVisible = false

    init(project: LoopProject) { _project = State(initialValue: project) }

    var body: some View {
        NavigationStack {
            ZStack {
                LoopAtmosphere()
                GeometryReader { geometry in
                    if geometry.size.width > 600 && geometry.size.width > geometry.size.height * 1.2 {
                        HStack(alignment: .top, spacing: 18) {
                            canvasCard(height: max(120, geometry.size.height - (keyboardVisible ? 28 : 146)))
                                .frame(width: geometry.size.width * 0.53)
                            VStack(spacing: 12) {
                                if !keyboardVisible { tools }
                                controlsScroll
                            }
                        }.padding(.horizontal, 18).padding(.top, 10)
                    } else {
                        VStack(spacing: 12) {
                            canvasCard(height: keyboardVisible ? 100 : min(250, max(160, geometry.size.height * 0.31)))
                            if !keyboardVisible { tools }
                            controlsScroll
                        }.padding(.horizontal, 18).padding(.top, 10)
                            .frame(maxWidth: 760).frame(maxWidth: .infinity)
                    }
                }.disabled(store.isExporting || store.trackingProgress != nil)
                if store.isExporting { ExportProgressView() }
                if let progress = store.trackingProgress { trackingOverlay(progress) }
            }
            .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { store.flush(project); dismiss() }
                        .disabled(store.isExporting || store.trackingProgress != nil).accessibilityIdentifier("editorDone")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undo() }
                        .labelStyle(.iconOnly)
                        .disabled(undoHistory.isEmpty || store.isExporting || store.trackingProgress != nil)
                        .accessibilityIdentifier("undoEdit")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Undo", systemImage: "arrow.uturn.backward") { undo() }.disabled(undoHistory.isEmpty)
                        Button("Redo", systemImage: "arrow.uturn.forward") { redo() }.disabled(redoHistory.isEmpty)
                        Divider()
                        Button("Rename project", systemImage: "pencil") { title = project.name; rename = true }
                        Button("Reset crop", systemImage: "crop.rotate") { project.crop = CropSettings() }
                        Button("Reset color", systemImage: "slider.horizontal.3") { project.adjustments = ColorAdjustments() }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .disabled(store.isExporting || store.trackingProgress != nil)
                }
            }
            .alert("Rename project", isPresented: $rename) {
                TextField("Name", text: $title)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !clean.isEmpty { project.name = String(clean.prefix(120)) }
                }
            }
            .alert("Loop", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .sheet(item: $exported) { item in ExportDetailView(item: item).environmentObject(store) }
        }
        .interactiveDismissDisabled(store.isExporting || store.trackingProgress != nil)
        .task {
            updatePresentationMode()
            preview.time = project.trimStart
            preview.refresh(project: project, url: store.sourceURL(project))
        }
        .onChange(of: project) { old, value in
            if applyingHistory {
                applyingHistory = false
                lastEdit = .distantPast
            } else {
                let now = Date()
                let changedLayers = old.overlays.map(\.id) != value.overlays.map(\.id)
                if changedLayers || now.timeIntervalSince(lastEdit) > 0.5 {
                    undoHistory.append(old)
                    if undoHistory.count > 40 { undoHistory.removeFirst() }
                }
                lastEdit = now
                redoHistory.removeAll()
            }
            store.saveEdited(value)
            if let id = selectedOverlay, !value.overlays.contains(where: { $0.id == id }) { selectedOverlay = nil }
            preview.refresh(project: value, url: store.sourceURL(value))
        }
        .onChange(of: preview.time) { _, _ in preview.refresh(project: project, url: store.sourceURL(project)) }
        .onChange(of: tool) { _, _ in preview.stop(); showingResult = false; updatePresentationMode(); dismissKeyboard() }
        .onChange(of: showingResult) { _, _ in updatePresentationMode() }
        .onChange(of: selectedOverlay) { _, value in if value == nil { dismissKeyboard() } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onDisappear { store.flush(project); preview.clear() }
    }

    private var controlsScroll: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 16) {
                    Color.clear.frame(height: 1).id("editorControlsTop")
                    activeControls
                    if tool != .export {
                        Button { preview.stop(); tool = .export } label: {
                            Label("Export settings", systemImage: "arrow.right").frame(maxWidth: .infinity).padding(.vertical, 9)
                        }.buttonStyle(.glass).accessibilityIdentifier("showExportSettings")
                    }
                }.padding(.bottom, 24)
            }
            .accessibilityIdentifier("editorControlsScroll")
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: tool) { _, _ in reader.scrollTo("editorControlsTop", anchor: .top) }
            .onChange(of: selectedOverlay) { _, _ in
                if tool == .overlays { reader.scrollTo("editorControlsTop", anchor: .top) }
            }
        }
    }

    private func canvasCard(height: CGFloat) -> some View {
        VStack(spacing: 9) {
            EditorCanvas(project: $project, selectedOverlay: $selectedOverlay, preview: preview, tool: tool, showingResult: showingResult, height: height)
            if !keyboardVisible {
            HStack(spacing: 14) {
                Button { step(-1) } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(.glass).accessibilityLabel("Previous frame")
                Button {
                    preview.toggle(project: project, url: store.sourceURL(project))
                } label: {
                    Image(systemName: preview.playing ? "pause.fill" : "play.fill").frame(width: 26)
                }.buttonStyle(.glassProminent).accessibilityLabel(preview.playing ? "Pause preview" : "Play preview")
                Button { step(1) } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(.glass).accessibilityLabel("Next frame")
                Spacer(minLength: 0)
                if tool == .crop || tool == .overlays {
                    Button { preview.stop(); showingResult.toggle() } label: {
                        Label(showingResult ? "Edit" : "Preview", systemImage: showingResult ? "slider.horizontal.3" : "eye")
                            .font(.caption.weight(.medium))
                    }.buttonStyle(.glass).accessibilityIdentifier("toggleResultPreview")
                }
            }
            Slider(value: Binding(get: { min(project.trimEnd, max(project.trimStart, preview.time)) }, set: {
                preview.seek(to: $0, project: project, url: store.sourceURL(project))
            }), in: project.trimStart...max(project.trimStart + 0.001, project.trimEnd), onEditingChanged: { editing in
                if editing { preview.beginScrubbing() }
                else { preview.endScrubbing(project: project, url: store.sourceURL(project)) }
            })
                .accessibilityLabel("Playhead").accessibilityIdentifier("playhead")
                .accessibilityValue(LoopFormat.time(preview.time))
            HStack {
                Text(LoopFormat.time(project.trimStart))
                Spacer()
                Text("Live preview · \(LoopFormat.rate(project.metadata.nominalFrameRate)) FPS source")
                Spacer()
                Text(LoopFormat.time(project.trimEnd))
            }.font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var tools: some View {
        HStack(spacing: 6) {
            ForEach(EditorTool.allCases) { item in
                Button { tool = item } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .medium))
                        Text(item.title).font(.caption2.weight(.semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundStyle(tool == item ? LoopTheme.deep : .primary)
                        .background(tool == item ? AnyShapeStyle(LoopTheme.lime) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityIdentifier("tool-\(item.rawValue)")
                    .accessibilityAddTraits(tool == item ? .isSelected : [])
            }
        }.padding(6).glassEffect(.regular, in: .rect(cornerRadius: 23))
    }

    @ViewBuilder private var activeControls: some View {
        switch tool {
        case .clip: clipControls
        case .crop: cropControls
        case .overlays: OverlayEditorView(project: $project, selected: $selectedOverlay, preview: preview)
        case .export:
            ExportOptionsView(project: $project)
            Button {
                preview.stop()
                Task { exported = await store.export(project) }
            } label: {
                Label("Create \(project.export.format.title)", systemImage: "sparkles")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 13)
            }.buttonStyle(.glassProminent).accessibilityIdentifier("createAnimation")
                .disabled((try? ExportPlan(project: project)) == nil)
        }
    }

    private var clipControls: some View {
        VStack(spacing: 16) {
            LoopCard {
                EditorSectionTitle(title: "Find your moment", subtitle: "\(project.metadata.size.label) · \(LoopFormat.rate(project.metadata.nominalFrameRate)) FPS source · \(LoopFormat.time(project.metadata.duration))")
                ValueSlider(title: "Start", value: Binding(get: { project.trimStart }, set: { newValue in
                    project.trimStart = min(project.trimEnd - 0.02, newValue)
                    preview.time = project.trimStart
                }), range: 0...max(0.001, project.metadata.duration - 0.02), step: 0.01, display: LoopFormat.time(project.trimStart), accessibilityID: "trimStart")
                ValueSlider(title: "End", value: Binding(get: { project.trimEnd }, set: { newValue in
                    project.trimEnd = min(project.metadata.duration, max(project.trimStart + 0.02, newValue))
                    preview.time = min(preview.time, project.trimEnd - 0.001)
                }), range: 0.02...max(0.021, project.metadata.duration), step: 0.01, display: LoopFormat.time(project.trimEnd), accessibilityID: "trimEnd")
                HStack {
                    Button("Start here") { project.trimStart = min(preview.time, project.trimEnd - 0.02) }
                    Spacer()
                    Button("End here") { project.trimEnd = max(preview.time, project.trimStart + 0.02) }
                    Spacer()
                    Button("Full video") { project.trimStart = 0; project.trimEnd = project.metadata.duration }
                }.font(.caption).buttonStyle(.glass)
            }
            LoopCard {
                EditorSectionTitle(title: "Motion")
                Picker("Playback", selection: $project.export.playback) {
                    ForEach(PlaybackMode.allCases) { mode in Text(mode.title).tag(mode) }
                }.pickerStyle(.segmented)
                ValueSlider(title: "Speed", value: $project.export.speed, range: 0.25...4, step: 0.05,
                            display: String(format: "%.2f×", project.export.speed))
                Text("Speed changes the duration. Frame rate changes how many frames are sampled per output second.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LoopCard {
                EditorSectionTitle(title: "A little finishing touch")
                ValueSlider(title: "Brightness", value: $project.adjustments.brightness, range: -0.5...0.5, display: String(format: "%+.2f", project.adjustments.brightness))
                ValueSlider(title: "Contrast", value: $project.adjustments.contrast, range: 0.5...1.8, display: String(format: "%.2f", project.adjustments.contrast))
                ValueSlider(title: "Saturation", value: $project.adjustments.saturation, range: 0...2, display: String(format: "%.2f", project.adjustments.saturation))
            }
        }
    }

    private var cropControls: some View {
        LoopCard {
            EditorSectionTitle(title: "Give it a frame", subtitle: "Drag the bright crop area over the part you want to keep. The shaded area is removed.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CropAspect.allCases) { aspect in
                    Button { project.crop.aspect = aspect; showingResult = false } label: {
                        Label(aspect.title, systemImage: aspect.symbol).font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 32).padding(5)
                    }.buttonStyle(.glass).tint(project.crop.aspect == aspect ? LoopTheme.teal : .secondary)
                        .accessibilityIdentifier("aspect-\(aspect.rawValue)")
                        .accessibilityAddTraits(project.crop.aspect == aspect ? .isSelected : [])
                }
            }
            ValueSlider(title: "Zoom", value: $project.crop.zoom, range: 1...5, step: 0.01, display: String(format: "%.2f×", project.crop.zoom))
            ValueSlider(title: "Horizontal position", value: $project.crop.centerX, range: 0...1, display: String(format: "%.0f%%", project.crop.centerX * 100))
            ValueSlider(title: "Vertical position", value: $project.crop.centerY, range: 0...1, display: String(format: "%.0f%%", project.crop.centerY * 100))
            Toggle("Mirror horizontally", isOn: $project.crop.mirror)
            Button("Reset framing", systemImage: "arrow.counterclockwise") { project.crop = CropSettings() }
                .font(.subheadline)
        }
    }

    private func step(_ direction: Double) {
        preview.stop()
        let frame = 1 / max(1, project.metadata.nominalFrameRate)
        let time = min(project.trimEnd - 0.001, max(project.trimStart, preview.time + direction * frame))
        preview.seek(to: time, project: project, url: store.sourceURL(project))
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func updatePresentationMode() {
        if !showingResult && tool == .crop { preview.setPresentationMode(.source) }
        else if !showingResult && tool == .overlays { preview.setPresentationMode(.editing) }
        else { preview.setPresentationMode(.result) }
    }

    private func undo() {
        guard let previous = undoHistory.popLast() else { return }
        preview.stop(); redoHistory.append(project); applyingHistory = true; project = previous
    }

    private func redo() {
        guard let next = redoHistory.popLast() else { return }
        preview.stop(); undoHistory.append(project); applyingHistory = true; project = next
    }

    private func trackingOverlay(_ progress: Double) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            LoopCard {
                Label("Following the motion", systemImage: "scope").font(.title3.weight(.semibold))
                ProgressView(value: progress)
                Text("Analyzing frames on your iPhone. Keep Loop open until tracking finishes.").font(.subheadline).foregroundStyle(.secondary)
                Button("Cancel tracking", role: .cancel) { store.cancelTracking() }.buttonStyle(.glass)
            }.padding(28).frame(maxWidth: 480)
        }
    }
}

struct ExportProgressView: View {
    @EnvironmentObject private var store: LoopStore
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            LoopCard {
                HStack {
                    LoopMark(size: 58)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.isPaused ? "Taking a pause" : "Making your loop").font(.title3.weight(.bold))
                        Text("\(Int(store.exportProgress.fraction * 100))% complete").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(1, max(0, store.exportProgress.fraction)))
                Text(store.isPaused ? "Resume when you’re ready. Your progress is kept while Loop stays open." : store.exportProgress.message)
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("\(store.exportProgress.completedFrames) of \(store.exportProgress.totalFrames) frames")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                HStack {
                    Button(store.isPaused ? "Resume" : "Pause", systemImage: store.isPaused ? "play" : "pause") { store.togglePause() }
                        .buttonStyle(.glassProminent)
                    Spacer()
                    Button("Cancel", role: .cancel) { store.cancelExport() }.buttonStyle(.glass)
                }
                Text("Keep Loop open. Processing pauses when the app leaves the foreground.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 480)
        }.accessibilityIdentifier("exportProgress")
    }
}
