import SwiftUI

struct CropEditorView: View {
    @EnvironmentObject private var store: LoopStore
    @Binding var project: LoopProject
    @ObservedObject var preview: EditorPreview
    @Binding var showingResult: Bool
    @Binding var selectingSubject: Bool
    @Binding var subjectDraft: CropSettings?
    @State private var geometryGestureActive = false
    @State private var trackingTask: Task<Void, Never>?

    private var tracking: CropTrackingSettings? { (subjectDraft ?? project.crop).tracking }
    private var hasPath: Bool { !(tracking?.keyframes.isEmpty ?? true) }
    private var needsReview: Bool {
        guard let tracking, let first = tracking.keyframes.first,
              let last = tracking.keyframes.last else { return false }
        // Full path validation happens at load/export. These endpoint checks stay
        // constant-time while the preview publishes each displayed frame.
        return tracking.needsReview || first.time > project.trimStart + 0.02 || last.time < project.trimEnd - 0.02
    }
    private var editTime: Double {
        min(project.trimEnd, max(project.trimStart, preview.displayedTime))
    }

    var body: some View {
        VStack(spacing: 16) {
            if selectingSubject {
                subjectSelection
            } else {
                if hasPath { trackingControls }
                aspectChoices
                if !hasPath { trackingControls }
                framingControls
            }
        }
        .onChange(of: selectingSubject) { _, selecting in
            if !selecting { clearSelectionDraft() }
        }
        .onDisappear {
            if trackingTask != nil { trackingTask?.cancel(); store.cancelTracking() }
            trackingTask = nil
            clearSelectionDraft()
            selectingSubject = false
        }
    }

    private var aspectChoices: some View {
        LoopCard {
            EditorSectionTitle(title: "Give it a frame", subtitle: "Drag the bright crop area over the part you want to keep. The shaded area is removed.")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CropAspect.allCases) { aspect in
                    Button {
                        preview.beginCanvasInteraction()
                        project.crop.aspect = aspect
                        showingResult = false
                    } label: {
                        Label(aspect.title, systemImage: aspect.symbol).font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 32).padding(5)
                    }.buttonStyle(.glass).tint(project.crop.aspect == aspect ? LoopTheme.teal : .secondary)
                        .accessibilityIdentifier("aspect-\(aspect.rawValue)")
                        .accessibilityAddTraits(project.crop.aspect == aspect ? .isSelected : [])
                }
            }
        }
    }

    private var trackingControls: some View {
        LoopCard {
            HStack {
                Label("Subject tracking", systemImage: "viewfinder").font(.headline)
                Spacer()
                if hasPath && !needsReview {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(LoopTheme.teal)
                        .accessibilityLabel("Crop motion path ready")
                }
            }
            if hasPath {
                Toggle("Follow subject", isOn: trackingField(\.enabled, fallback: false))
                    .accessibilityIdentifier("cropTrackingEnabled")
                Toggle("Follow subject size", isOn: trackingField(\.followScale, fallback: true))
                    .accessibilityIdentifier("cropFollowScale")
                Text(tracking?.followScale == true
                     ? "The crop follows position and adjusts its zoom as the subject comes closer or moves away, within the video’s edges."
                     : "The crop follows the subject’s position and keeps one zoom level.")
                    .font(.caption).foregroundStyle(.secondary)
                if needsReview {
                    Label("The selected clip changed or tracking needs attention. Choose the subject again to update its path.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("cropTrackingReview")
                } else {
                    Text("\(tracking?.keyframes.count ?? 0) positions · Blur, pixelation and emoji tracking stay attached to the original video.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button("Adjust subject", systemImage: "viewfinder") { chooseSubject() }
                        .buttonStyle(.glass).accessibilityIdentifier("chooseCropSubject")
                    Spacer(minLength: 0)
                    Button("Remove tracking", role: .destructive) {
                        preview.beginCanvasInteraction()
                        project.crop.tracking = nil
                    }.font(.caption).accessibilityIdentifier("removeCropTracking")
                }
            } else {
                Text("Keep a person or object in frame as it moves. Choose the subject on the video, then let the crop follow it.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { chooseSubject() } label: {
                    Label("Choose subject", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }.buttonStyle(.glassProminent).accessibilityIdentifier("chooseCropSubject")
                Text("Analyzed on your iPhone. Works together with every tracked overlay.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if project.crop.rect(source: project.metadata.size).width >= 0.999 &&
                project.crop.rect(source: project.metadata.size).height >= 0.999 {
                Text("This crop shows the full video. Choose a narrower frame or increase crop zoom to give it room to follow your subject.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cropTrackingControls")
    }

    private var subjectSelection: some View {
        LoopCard {
            HStack {
                EditorSectionTitle(title: "Choose what to follow", subtitle: "Fit the green box around your subject. Drag the box or its corner; tap the video to reposition it.")
                Spacer(minLength: 0)
                Button("Cancel") { cancelSelection() }
                    .font(.caption.weight(.semibold)).frame(minHeight: 44)
                    .accessibilityIdentifier("cancelCropSubject")
            }
            Button { trackSubject() } label: {
                Label("Track subject", systemImage: "scope")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }.buttonStyle(.glassProminent).accessibilityIdentifier("trackCropSubject")
            Text("The crop centers on this selection and follows it through the whole selected clip. Pinch the video to place the box precisely.")
                .font(.caption).foregroundStyle(.secondary)
            subjectSlider(title: "Subject width", path: \.width, pixels: project.metadata.size.width,
                          accessibilityID: "cropSubjectWidth")
            subjectSlider(title: "Subject height", path: \.height, pixels: project.metadata.size.height,
                          accessibilityID: "cropSubjectHeight")
            Toggle("Follow subject size", isOn: trackingField(\.followScale, fallback: true))
                .accessibilityIdentifier("cropFollowScale")
            Text("Adjust zoom as the subject approaches or moves away. The crop stays inside the source video.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cropSubjectControls")
    }

    private var framingControls: some View {
        LoopCard {
            EditorSectionTitle(title: "Framing", subtitle: tracking?.enabled == true
                               ? "Refine the composition while the subject keeps its motion path."
                               : "Adjust crop zoom and position. Pinching the preview only changes your editing view.")
            framingSlider(title: "Zoom", path: \.zoom, range: 1...5, step: 0.01,
                          display: String(format: "%.2f×", project.crop.zoom), accessibilityID: "cropZoom")
            framingSlider(title: "Horizontal position", path: \.centerX, range: 0...1, step: 0.005,
                          display: String(format: "%.0f%%", project.crop.centerX * 100), accessibilityID: "cropHorizontalPosition")
            framingSlider(title: "Vertical position", path: \.centerY, range: 0...1, step: 0.005,
                          display: String(format: "%.0f%%", project.crop.centerY * 100), accessibilityID: "cropVerticalPosition")
            Toggle("Mirror horizontally", isOn: $project.crop.mirror)
            Button("Reset crop and tracking", systemImage: "arrow.counterclockwise") {
                preview.beginCanvasInteraction()
                project.crop = CropSettings()
                showingResult = false
            }.font(.subheadline).accessibilityIdentifier("resetCrop")
        }
    }

    private func chooseSubject() {
        preview.beginCanvasInteraction()
        var draft = project.crop
        let crop = project.crop.rect(source: project.metadata.size, at: editTime)
        var settings = project.crop.tracking ?? CropTrackingSettings()
        if !settings.keyframes.isEmpty {
            settings.subjectRect = settings.rect(at: editTime)
        } else if project.crop.tracking == nil {
            let width = min(0.3, crop.width * 0.7)
            let height = min(0.5, crop.height * 0.65)
            settings.subjectRect = NormalizedRect(x: crop.centerX - width / 2,
                                                   y: crop.centerY - height / 2,
                                                   width: width, height: height).clamped()
        }
        settings.anchorTime = editTime
        settings.enabled = false
        settings.keyframes = []
        settings.needsReview = false
        draft.tracking = settings
        subjectDraft = draft
        showingResult = false
        selectingSubject = true
    }

    private func cancelSelection() {
        preview.beginCanvasInteraction()
        clearSelectionDraft()
        selectingSubject = false
    }

    private func clearSelectionDraft() {
        subjectDraft = nil
        geometryGestureActive = false
    }

    private func trackSubject() {
        preview.beginCanvasInteraction()
        guard var draft = subjectDraft, var settings = draft.tracking else { return }
        settings.subjectRect = settings.subjectRect.clamped()
        settings.anchorTime = editTime
        settings.keyframes = []
        settings.enabled = false
        settings.needsReview = false
        draft.centerX = settings.subjectRect.centerX
        draft.centerY = settings.subjectRect.centerY
        draft.tracking = settings
        subjectDraft = draft
        var snapshot = project
        snapshot.crop = draft
        let anchor = editTime
        trackingTask = Task {
            defer {
                preview.resumeAfterAnalysis(project: project, url: store.sourceURL(project))
                trackingTask = nil
            }
            do {
                _ = try await store.trackCrop(project: snapshot, anchorTime: anchor,
                    beforeAnalysis: { await preview.suspendForAnalysis() },
                    didCommit: { completed in
                        guard project.id == completed.id else { return }
                        // The result is already on disk, and the store is still busy.
                        project.crop = completed.crop
                        subjectDraft = nil
                        selectingSubject = false
                        showingResult = true
                    })
            } catch is CancellationError { }
            catch LoopError.cancelled { }
            catch {
                subjectDraft?.tracking?.needsReview = true
                store.error = error.localizedDescription
            }
        }
    }

    private func trackingField<T>(_ path: WritableKeyPath<CropTrackingSettings, T>, fallback: T) -> Binding<T> {
        Binding(get: { tracking?[keyPath: path] ?? fallback }, set: { value in
            var crop = selectingSubject ? (subjectDraft ?? project.crop) : project.crop
            var settings = crop.tracking ?? CropTrackingSettings()
            settings[keyPath: path] = value
            crop.tracking = settings
            if selectingSubject { subjectDraft = crop }
            else { project.crop = crop }
        })
    }

    private func subjectSlider(title: String, path: WritableKeyPath<NormalizedRect, Double>,
                               pixels: Int, accessibilityID: String) -> some View {
        let fraction = tracking?.subjectRect[keyPath: path] ?? 0.3
        return VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.0f px", fraction * Double(pixels)))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { tracking?.subjectRect[keyPath: path] ?? 0.3 }, set: { value in
                if !geometryGestureActive { preview.beginCanvasInteraction() }
                guard var draft = subjectDraft else { return }
                var settings = draft.tracking ?? CropTrackingSettings()
                var rect = settings.subjectRect
                let center = CGPoint(x: rect.centerX, y: rect.centerY)
                rect[keyPath: path] = value
                rect.x = center.x - rect.width / 2
                rect.y = center.y - rect.height / 2
                settings.subjectRect = rect.clamped()
                settings.anchorTime = editTime
                settings.keyframes = []
                settings.enabled = false
                draft.tracking = settings
                subjectDraft = draft
            }), in: 0.02...1, step: 0.005, onEditingChanged: geometryEditingChanged)
                .accessibilityLabel(title).accessibilityIdentifier(accessibilityID)
        }
    }

    private func framingSlider(title: String, path: WritableKeyPath<CropSettings, Double>,
                               range: ClosedRange<Double>, step: Double, display: String,
                               accessibilityID: String) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(display).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { project.crop[keyPath: path] }, set: { value in
                if !geometryGestureActive { preview.beginCanvasInteraction() }
                project.crop[keyPath: path] = value
            }), in: range, step: step, onEditingChanged: geometryEditingChanged)
                .accessibilityLabel(title).accessibilityIdentifier(accessibilityID)
        }
    }

    private func geometryEditingChanged(_ editing: Bool) {
        if editing { preview.beginCanvasInteraction() }
        geometryGestureActive = editing
    }
}
