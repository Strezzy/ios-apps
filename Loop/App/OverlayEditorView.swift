import SwiftUI

struct OverlayEditorView: View {
    @EnvironmentObject private var store: LoopStore
    @Binding var project: LoopProject
    @Binding var selected: UUID?
    @ObservedObject var preview: EditorPreview
    @State private var timingExpanded = false
    @State private var trackingExpanded = false
    @State private var emojiFocused = false
    @State private var geometryGestureActive = false
    @FocusState private var captionFocused: Bool

    private var current: OverlayItem? { project.overlays.first { $0.id == selected } }
    private var editTime: Double {
        min(project.trimEnd - 0.000001, max(project.trimStart, preview.displayedTime))
    }

    var body: some View {
        VStack(spacing: 12) {
            if let overlay = current {
                options(overlay)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("overlayControls")
                LoopCard {
                    DisclosureGroup(isExpanded: $timingExpanded) {
                        timing(overlay).padding(.top, 12)
                    } label: {
                        Label("Timing", systemImage: "clock").font(.subheadline.weight(.semibold))
                    }.accessibilityIdentifier("overlayTiming")
                    Divider()
                    DisclosureGroup(isExpanded: $trackingExpanded) {
                        tracking(overlay).padding(.top, 12)
                    } label: {
                        HStack {
                            Label("Motion tracking", systemImage: "scope")
                                .font(.subheadline.weight(.semibold))
                            if overlay.trackingNeedsReview {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                    .accessibilityLabel("Tracking needs review")
                            } else if overlay.trackingEnabled {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(LoopTheme.teal)
                                    .accessibilityLabel("Motion path ready")
                            }
                        }
                    }.accessibilityIdentifier("overlayTracking")
                }
            } else {
                addMenu
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("overlayAddMenu")
            }
        }
        .onChange(of: selected) { _, _ in
            dismissKeyboard()
            timingExpanded = false
            trackingExpanded = false
            geometryGestureActive = false
        }
        .onChange(of: project.overlays.map(\.id)) { _, ids in
            if let selected, !ids.contains(selected) { finishEditing() }
        }
        .onDisappear { dismissKeyboard() }
    }

    private var addMenu: some View {
        LoopCard {
            EditorSectionTitle(title: "Add an overlay", subtitle: "Choose a layer, then adjust it directly on the video.")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
                ForEach(OverlayKind.allCases) { kind in
                    Button { add(kind) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: kind.symbol).font(.title3)
                            Text(kind.title).font(.caption2.weight(.medium)).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity, minHeight: 61)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Add \(kind.title.lowercased())")
                    .accessibilityIdentifier("add-\(kind.rawValue)")
                }
            }
            if !project.overlays.isEmpty {
                Divider()
                Text("Your layers").font(.subheadline.weight(.semibold))
                ForEach(project.overlays) { overlay in
                    Button { select(overlay) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: overlay.kind.symbol).frame(width: 22)
                            Text(overlay.title).lineLimit(1)
                            Spacer()
                            if overlay.trackingEnabled { Image(systemName: "scope").font(.caption) }
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }.font(.subheadline).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(overlay.title)")
                    .accessibilityIdentifier("select-overlay-\(overlay.id.uuidString)")
                }
            }
        }
    }

    private func options(_ overlay: OverlayItem) -> some View {
        LoopCard {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(overlay.kind.title).font(.headline)
                    Text("Drag to move · pull the corner to resize")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Done") { finishEditing() }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityLabel("Finish editing overlay")
                    .accessibilityIdentifier("overlayDone")
                Button(role: .destructive) { deleteSelected() } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete selected overlay")
                .accessibilityIdentifier("deleteOverlay")
            }

            VStack(spacing: 12) {
                if overlay.kind == .emoji {
                    EmojiInput(text: field(\.content, fallback: ""), isFocused: $emojiFocused)
                        .frame(height: 54)
                    Button {
                        preview.stop()
                        captionFocused = false
                        emojiFocused = true
                    } label: {
                        Label("Choose emoji", systemImage: "face.smiling")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityHint("Opens the iPhone keyboard with Emoji preferred.")
                    .accessibilityIdentifier("chooseEmoji")
                } else if overlay.kind == .text {
                    TextField("Your caption", text: field(\.content, fallback: ""), axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3)
                        .focused($captionFocused).submitLabel(.done)
                        .onSubmit { captionFocused = false }
                        .accessibilityLabel("Caption")
                        .accessibilityIdentifier("overlayContent")
                } else {
                    Picker("Shape", selection: field(\.shape, fallback: .ellipse)) {
                        ForEach(OverlayShape.allCases) { shape in Text(shape.title).tag(shape) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("overlayShape")
                    if overlay.kind == .blur || overlay.kind == .pixelate {
                        ValueSlider(title: overlay.kind == .blur ? "Radius" : "Block size",
                                    value: field(\.strength, fallback: 0.7), range: 0...1, step: 0.005,
                                    display: effectSize(overlay), accessibilityID: "overlayStrength")
                    }
                }
                geometrySlider(title: "Width", path: \.width, pixels: project.metadata.size.width,
                               accessibilityID: "overlayWidth")
                geometrySlider(title: "Height", path: \.height, pixels: project.metadata.size.height,
                               accessibilityID: "overlayHeight")
                if overlay.kind == .emoji || overlay.kind == .text {
                    ValueSlider(title: "Opacity", value: field(\.opacity, fallback: 1), range: 0.1...1,
                                display: String(format: "%.0f%%", overlay.opacity * 100),
                                accessibilityID: "overlayOpacity")
                }
            }
            HStack(spacing: 12) {
                Button("Center", systemImage: "scope") { centerSelected() }
                    .accessibilityLabel("Center overlay in the crop")
                    .accessibilityIdentifier("overlayCenter")
                Spacer(minLength: 0)
                Button("Reset size", systemImage: "arrow.counterclockwise") { resetSize() }
                    .accessibilityIdentifier("overlayResetSize")
            }.font(.caption).buttonStyle(.glass)
        }
    }

    private func timing(_ overlay: OverlayItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ValueSlider(title: "Appears", value: Binding(get: { current?.startTime ?? project.trimStart }, set: { value in
                set(\.startTime, min(value, (current?.endTime ?? project.trimEnd) - 0.01))
            }), range: project.trimStart...max(project.trimStart + 0.001, project.trimEnd - 0.01), step: 0.01,
                        display: LoopFormat.time(overlay.startTime), accessibilityID: "overlayStart")
            ValueSlider(title: "Disappears", value: Binding(get: { current?.endTime ?? project.trimEnd }, set: { value in
                set(\.endTime, max(value, (current?.startTime ?? project.trimStart) + 0.01))
            }), range: min(project.trimStart + 0.01, project.trimEnd)...max(project.trimStart + 0.011, project.trimEnd), step: 0.01,
                        display: LoopFormat.time(overlay.endTime), accessibilityID: "overlayEnd")
            Button("Use the whole clip") {
                set(\.startTime, project.trimStart)
                set(\.endTime, project.trimEnd)
            }.font(.caption).buttonStyle(.glass)
        }
    }

    private func tracking(_ overlay: OverlayItem) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Place the layer over your subject at this frame. Tracking follows it in both directions through its time range.")
                .font(.caption).foregroundStyle(.secondary)
            Button { track(overlay) } label: {
                Label(overlay.trackingEnabled ? "Track again from this frame" : "Track this subject", systemImage: "scope")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.glassProminent).accessibilityIdentifier("trackOverlay")
            if overlay.trackingNeedsReview {
                Label("Re-track this layer, or use manual keyframes and review the clip.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if overlay.trackingEnabled {
                Label("Motion path ready · \(overlay.keyframes.count) positions", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(LoopTheme.teal)
            }
            HStack {
                Button("Add position keyframe", systemImage: "diamond") { addKeyframe(overlay) }
                    .buttonStyle(.glass).font(.caption).accessibilityIdentifier("addOverlayKeyframe")
                if !overlay.keyframes.isEmpty {
                    Button("Remove here", systemImage: "diamond.slash") {
                        preview.beginCanvasInteraction()
                        guard let index = project.overlays.firstIndex(where: { $0.id == selected }) else { return }
                        let time = editTime
                        project.overlays[index].keyframes.removeAll { abs($0.time - time) < 0.05 }
                    }.buttonStyle(.glass).font(.caption).accessibilityIdentifier("removeOverlayKeyframe")
                }
            }
            Text("Scrub and move the layer to add a correction. Review tracking across the clip before exporting.")
                .font(.caption).foregroundStyle(.secondary)
            if overlay.trackingEnabled || overlay.trackingNeedsReview {
                Button("Switch to manual keyframes") {
                    set(\.trackingEnabled, false); set(\.trackingNeedsReview, false)
                    addKeyframe(overlay)
                }.font(.caption)
            }
            if !overlay.keyframes.isEmpty {
                Button("Use one fixed position") {
                    preview.beginCanvasInteraction()
                    let rect = overlay.rect(at: editTime)
                    set(\.rect, rect); set(\.keyframes, []); set(\.trackingEnabled, false); set(\.trackingNeedsReview, false)
                }.font(.caption)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(overlay.keyframes.enumerated()).filter { $0.element.manual }, id: \.offset) { _, key in
                            Button { preview.stop(); preview.time = key.time } label: {
                                Label(LoopFormat.time(key.time), systemImage: "diamond.fill").font(.caption2.monospacedDigit())
                            }.buttonStyle(.glass)
                        }
                    }.padding(2)
                }
            }
        }
    }

    private func add(_ kind: OverlayKind) {
        preview.beginCanvasInteraction()
        dismissKeyboard()
        var overlay = OverlayItem(kind: kind, startTime: project.trimStart, endTime: project.trimEnd)
        let crop = project.crop.rect(source: project.metadata.size, at: editTime)
        let width = min(0.28, crop.width * 0.65)
        let height = min(0.28, crop.height * 0.65)
        overlay.rect = NormalizedRect(x: crop.centerX - width / 2, y: crop.centerY - height / 2, width: width, height: height).clamped()
        if kind == .text { overlay.content = "Your moment"; overlay.shape = .rectangle }
        project.overlays.append(overlay)
        selected = overlay.id
    }

    private func select(_ overlay: OverlayItem) {
        dismissKeyboard()
        selected = overlay.id
        preview.stop()
        if !overlay.isActive(at: editTime) {
            preview.time = min(project.trimEnd - 0.001, max(project.trimStart, overlay.startTime))
        }
    }

    private func finishEditing() {
        dismissKeyboard()
        selected = nil
    }

    private func dismissKeyboard() {
        emojiFocused = false
        captionFocused = false
    }

    private func deleteSelected() {
        guard let id = selected else { return }
        preview.stop()
        dismissKeyboard()
        project.overlays.removeAll { $0.id == id }
        selected = nil
    }

    private func centerSelected() {
        guard let current else { return }
        preview.beginCanvasInteraction()
        var rect = current.rect(at: editTime)
        let crop = project.crop.rect(source: project.metadata.size, at: editTime)
        rect.x = crop.centerX - rect.width / 2
        rect.y = crop.centerY - rect.height / 2
        applyRect(rect)
    }

    private func resetSize() {
        guard let current else { return }
        preview.beginCanvasInteraction()
        var rect = current.rect(at: editTime)
        let x = rect.centerX, y = rect.centerY
        let crop = project.crop.rect(source: project.metadata.size, at: editTime)
        rect.width = min(0.28, crop.width * 0.65)
        rect.height = min(0.28, crop.height * 0.65)
        rect.x = x - rect.width / 2
        rect.y = y - rect.height / 2
        applyRect(rect)
    }

    private func effectSize(_ overlay: OverlayItem) -> String {
        let size = FrameRenderer.overlayPixelMeasure(kind: overlay.kind, strength: overlay.strength, project: project)
        return String(format: "%.1f px at export", size)
    }

    private func dimension(_ fraction: Double, pixels: Int) -> String {
        String(format: "%.1f%% · %.0f px", fraction * 100, fraction * Double(pixels))
    }

    private func addKeyframe(_ overlay: OverlayItem) {
        preview.beginCanvasInteraction()
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let time = editTime
        let rect = overlay.rect(at: time)
        if project.overlays[index].keyframes.isEmpty {
            project.overlays[index].setKeyframe(at: max(project.trimStart, overlay.startTime), rect: rect)
            project.overlays[index].setKeyframe(at: min(project.trimEnd, overlay.endTime), rect: rect)
        }
        project.overlays[index].setKeyframe(at: time, rect: rect)
    }

    private func track(_ overlay: OverlayItem) {
        preview.beginCanvasInteraction()
        dismissKeyboard()
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let anchor = min(min(project.trimEnd, overlay.endTime), max(max(project.trimStart, overlay.startTime), editTime))
        var target = overlay
        target.rect = overlay.rect(at: anchor)
        target.keyframes = []
        project.overlays[index].trackingEnabled = true
        project.overlays[index].trackingNeedsReview = true
        let snapshot = project
        Task {
            do {
                let keys = try await store.track(project: snapshot, overlay: target, anchorTime: anchor)
                guard let i = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
                project.overlays[i].keyframes = keys
                project.overlays[i].trackingEnabled = true
                project.overlays[i].trackingNeedsReview = false
            } catch is CancellationError { }
            catch LoopError.cancelled { }
            catch { store.error = error.localizedDescription }
        }
    }

    private func field<T>(_ path: WritableKeyPath<OverlayItem, T>, fallback: T) -> Binding<T> {
        Binding(get: { current?[keyPath: path] ?? fallback }, set: { set(path, $0) })
    }

    private func set<T>(_ path: WritableKeyPath<OverlayItem, T>, _ value: T) {
        guard let index = project.overlays.firstIndex(where: { $0.id == selected }) else { return }
        project.overlays[index][keyPath: path] = value
    }

    private func applyRect(_ rect: NormalizedRect) {
        guard let index = project.overlays.firstIndex(where: { $0.id == selected }) else { return }
        if project.overlays[index].keyframes.isEmpty {
            project.overlays[index].rect = rect.clamped()
        } else {
            project.overlays[index].setKeyframe(at: editTime, rect: rect.clamped())
        }
    }

    private func rectField(_ path: WritableKeyPath<NormalizedRect, Double>) -> Binding<Double> {
        Binding(get: { current?.rect(at: editTime)[keyPath: path] ?? 0.3 }, set: { value in
            // Accessibility can set a slider without a drag-began callback.
            if !geometryGestureActive { preview.beginCanvasInteraction() }
            guard let current else { return }
            var rect = current.rect(at: editTime)
            let x = rect.centerX, y = rect.centerY
            rect[keyPath: path] = value
            rect.x = x - rect.width / 2
            rect.y = y - rect.height / 2
            applyRect(rect)
        })
    }

    private func geometrySlider(title: String, path: WritableKeyPath<NormalizedRect, Double>,
                                pixels: Int, accessibilityID: String) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(dimension(current?.rect(at: editTime)[keyPath: path] ?? 0.3, pixels: pixels))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: rectField(path), in: 0.005...1, step: 0.001, onEditingChanged: { editing in
                if editing { preview.beginCanvasInteraction() }
                geometryGestureActive = editing
            })
            .accessibilityLabel(title)
            .accessibilityIdentifier(accessibilityID)
        }
    }
}
