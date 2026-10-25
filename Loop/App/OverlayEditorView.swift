import SwiftUI

struct OverlayEditorView: View {
    @EnvironmentObject private var store: LoopStore
    @Binding var project: LoopProject
    @Binding var selected: UUID?
    @ObservedObject var preview: EditorPreview
    @State private var deleting = false
    private var current: OverlayItem? { project.overlays.first { $0.id == selected } }

    var body: some View {
        VStack(spacing: 16) {
            LoopCard {
                EditorSectionTitle(title: "Make it your own", subtitle: "Add a layer, then drag it on the source. Tap Preview to see the finished effect.")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(OverlayKind.allCases) { kind in
                            Button { add(kind) } label: {
                                VStack(spacing: 7) {
                                    Image(systemName: kind.symbol).font(.title3)
                                    Text(kind.title).font(.caption2.weight(.medium))
                                }.frame(width: 72, height: 61)
                            }.buttonStyle(.glass).accessibilityIdentifier("add-\(kind.rawValue)")
                        }
                    }.padding(3)
                }
                if !project.overlays.isEmpty {
                    Divider()
                    ForEach(project.overlays) { overlay in
                        Button { selected = overlay.id; preview.stop(); preview.time = min(project.trimEnd - 0.001, max(project.trimStart, overlay.startTime)) } label: {
                            HStack {
                                Image(systemName: overlay.kind.symbol).frame(width: 22)
                                Text(overlay.title).lineLimit(1)
                                Spacer()
                                if overlay.trackingEnabled { Image(systemName: "scope").font(.caption) }
                                if !overlay.keyframes.isEmpty { Text("\(overlay.keyframes.count)").font(.caption.monospacedDigit()) }
                                Image(systemName: selected == overlay.id ? "checkmark.circle.fill" : "circle")
                            }.font(.subheadline).padding(.vertical, 5)
                        }.buttonStyle(.plain).foregroundStyle(selected == overlay.id ? LoopTheme.teal : .primary)
                    }
                }
            }
            if let overlay = current {
                options(overlay)
                tracking(overlay)
            } else {
                Text("Blur something private, add a caption, or let an emoji follow the action.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(8)
            }
        }
        .confirmationDialog("Delete this overlay?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete overlay", role: .destructive) {
                project.overlays.removeAll { $0.id == selected }
                selected = project.overlays.last?.id
            }
        }
    }

    private func options(_ overlay: OverlayItem) -> some View {
        LoopCard {
            HStack {
                EditorSectionTitle(title: overlay.kind.title, subtitle: "Drag to position. Pull the corner handle to resize.")
                Spacer()
                Button(role: .destructive) { deleting = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Delete selected overlay")
            }
            if overlay.kind == .emoji || overlay.kind == .text {
                TextField(overlay.kind == .emoji ? "Emoji" : "Your caption", text: field(\.content, fallback: ""), axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .accessibilityIdentifier("overlayContent")
                if overlay.kind == .emoji {
                    HStack {
                        ForEach(["😎", "😂", "❤️", "🔥", "✨", "🙈"], id: \.self) { emoji in
                            Button(emoji) { set(\.content, emoji) }.font(.title2).frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Picker("Shape", selection: field(\.shape, fallback: .ellipse)) {
                    ForEach(OverlayShape.allCases) { shape in Text(shape.title).tag(shape) }
                }.pickerStyle(.segmented).accessibilityIdentifier("overlayShape")
                if overlay.kind != .cover {
                    ValueSlider(title: "Strength", value: field(\.strength, fallback: 0.7), range: 0.1...1,
                                display: String(format: "%.0f%%", overlay.strength * 100))
                }
            }
            ValueSlider(title: "Width", value: rectField(\.width), range: 0.03...1,
                        display: String(format: "%.0f%%", overlay.rect(at: preview.time).width * 100))
            ValueSlider(title: "Height", value: rectField(\.height), range: 0.03...1,
                        display: String(format: "%.0f%%", overlay.rect(at: preview.time).height * 100))
            if overlay.kind == .emoji || overlay.kind == .text {
                ValueSlider(title: "Opacity", value: field(\.opacity, fallback: 1), range: 0.1...1,
                            display: String(format: "%.0f%%", overlay.opacity * 100))
            }
            Divider()
            ValueSlider(title: "Appears", value: Binding(get: { current?.startTime ?? project.trimStart }, set: { value in
                set(\.startTime, min(value, (current?.endTime ?? project.trimEnd) - 0.01))
            }), range: project.trimStart...max(project.trimStart + 0.001, project.trimEnd - 0.01), step: 0.01, display: LoopFormat.time(overlay.startTime))
            ValueSlider(title: "Disappears", value: Binding(get: { current?.endTime ?? project.trimEnd }, set: { value in
                set(\.endTime, max(value, (current?.startTime ?? project.trimStart) + 0.01))
            }), range: min(project.trimStart + 0.01, project.trimEnd)...max(project.trimStart + 0.011, project.trimEnd), step: 0.01, display: LoopFormat.time(overlay.endTime))
            if overlay.kind.isRedaction {
                Label("Review every frame before sharing sensitive content. A solid cover is stronger than a soft blur.", systemImage: "eye")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tracking(_ overlay: OverlayItem) -> some View {
        LoopCard {
            EditorSectionTitle(title: "Follow the action", subtitle: "Place the layer over your subject at the current frame. Tracking follows it in both directions across the selected clip.")
            Button { track(overlay) } label: {
                Label(overlay.trackingEnabled ? "Track again from this frame" : "Track this subject", systemImage: "scope")
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
            }.buttonStyle(.glassProminent).accessibilityIdentifier("trackOverlay")
            if overlay.trackingNeedsReview {
                Label("The tracking path needs attention. Re-track it, or switch to manual keyframes and review the full clip.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else if overlay.trackingEnabled {
                Label("Motion path ready · \(overlay.keyframes.count) positions", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(LoopTheme.teal)
            }
            HStack {
                Button("Add position keyframe", systemImage: "diamond") { addKeyframe(overlay) }
                    .buttonStyle(.glass).font(.caption)
                if !overlay.keyframes.isEmpty {
                    Button("Remove here", systemImage: "diamond.slash") {
                        guard let index = project.overlays.firstIndex(where: { $0.id == selected }) else { return }
                        project.overlays[index].keyframes.removeAll { abs($0.time - preview.time) < 0.05 }
                    }.buttonStyle(.glass).font(.caption)
                }
            }
            Text("Scrub to another frame and move the layer to add a correction. Positions interpolate between keyframes.")
                .font(.caption).foregroundStyle(.secondary)
            if overlay.trackingEnabled || overlay.trackingNeedsReview {
                Button("Switch to manual keyframes") {
                    set(\.trackingEnabled, false); set(\.trackingNeedsReview, false)
                    addKeyframe(overlay)
                }.font(.caption)
            }
            if !overlay.keyframes.isEmpty {
                Button("Use one fixed position") {
                    let rect = overlay.rect(at: preview.time)
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
        preview.stop()
        var overlay = OverlayItem(kind: kind, startTime: project.trimStart, endTime: project.trimEnd)
        let crop = project.crop.rect(source: project.metadata.size)
        let width = min(0.28, crop.width * 0.65)
        let height = min(0.28, crop.height * 0.65)
        overlay.rect = NormalizedRect(x: crop.centerX - width / 2, y: crop.centerY - height / 2, width: width, height: height)
        if kind == .text { overlay.content = "Your moment"; overlay.shape = .rectangle }
        project.overlays.append(overlay); selected = overlay.id
    }

    private func addKeyframe(_ overlay: OverlayItem) {
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let rect = overlay.rect(at: preview.time)
        if project.overlays[index].keyframes.isEmpty {
            project.overlays[index].setKeyframe(at: max(project.trimStart, overlay.startTime), rect: rect)
            project.overlays[index].setKeyframe(at: min(project.trimEnd, overlay.endTime), rect: rect)
        }
        project.overlays[index].setKeyframe(at: preview.time, rect: rect)
    }

    private func track(_ overlay: OverlayItem) {
        preview.stop()
        guard let index = project.overlays.firstIndex(where: { $0.id == overlay.id }) else { return }
        let anchor = min(min(project.trimEnd, overlay.endTime), max(max(project.trimStart, overlay.startTime), preview.time))
        var target = overlay; target.rect = overlay.rect(at: anchor); target.keyframes = []
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
    private func rectField(_ path: WritableKeyPath<NormalizedRect, Double>) -> Binding<Double> {
        Binding(get: { current?.rect(at: preview.time)[keyPath: path] ?? 0.3 }, set: { value in
            guard let index = project.overlays.firstIndex(where: { $0.id == selected }) else { return }
            var rect = project.overlays[index].rect(at: preview.time)
            rect[keyPath: path] = value
            if project.overlays[index].keyframes.isEmpty { project.overlays[index].rect = rect.clamped() }
            else { project.overlays[index].setKeyframe(at: preview.time, rect: rect.clamped()) }
        })
    }
}
