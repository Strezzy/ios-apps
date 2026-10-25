import SwiftUI

enum EditorTool: String, CaseIterable, Identifiable {
    case clip, crop, overlays, export
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .clip: return "scissors"; case .crop: return "crop"; case .overlays: return "square.on.circle"; case .export: return "square.and.arrow.up" }
    }
}

struct EditorCanvas: View {
    @Binding var project: LoopProject
    @Binding var selectedOverlay: UUID?
    @ObservedObject var preview: EditorPreview
    var tool: EditorTool
    var showingResult: Bool
    @State private var cropOrigin: CGPoint?
    @State private var overlayOrigin: NormalizedRect?
    @State private var resizeOrigin: NormalizedRect?

    private var showSource: Bool { !showingResult && (tool == .crop || tool == .overlays) }
    private var aspect: Double {
        if showSource { return project.metadata.size.aspect }
        return project.crop.aspect.ratio(source: project.metadata.size)
    }

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size
            let width = min(available.width, available.height * aspect)
            let height = width / max(0.01, aspect)
            let imageSize = CGSize(width: width, height: height)
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.94))
                if let image = showSource ? preview.sourceFrame : preview.renderedFrame {
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().frame(width: width, height: height)
                        if showSource, tool == .crop { cropSelection(size: imageSize) }
                        if showSource, tool == .overlays { overlaySelections(size: imageSize) }
                    }.frame(width: width, height: height)
                        .clipped()
                } else {
                    ProgressView().tint(.white)
                }
                VStack {
                    HStack {
                        Text(showSource ? "SOURCE" : "RESULT")
                            .font(.system(size: 9, weight: .bold)).tracking(1.3)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: .capsule)
                        Spacer()
                        Text(LoopFormat.time(preview.time)).font(.caption2.monospacedDigit())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: .capsule)
                    }
                    Spacer()
                    if let error = preview.error {
                        Text(error).font(.caption).multilineTextAlignment(.center)
                            .padding(12).background(.black.opacity(0.8), in: .rect(cornerRadius: 12))
                    }
                }.foregroundStyle(.white).padding(12).allowsHitTesting(false)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(.rect(cornerRadius: 20))
        }.frame(height: 270)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editorCanvas")
    }

    private func cropSelection(size: CGSize) -> some View {
        let rect = project.crop.rect(source: project.metadata.size)
        let box = CGRect(x: rect.x * size.width, y: rect.y * size.height, width: rect.width * size.width, height: rect.height * size.height)
        return ZStack(alignment: .topLeading) {
            Path { path in path.addRect(CGRect(origin: .zero, size: size)); path.addRect(box) }
                .fill(.black.opacity(0.64), style: FillStyle(eoFill: true)).allowsHitTesting(false)
            Rectangle().stroke(.white, lineWidth: 1.5)
                .overlay {
                    Canvas { context, canvas in
                        var grid = Path()
                        for fraction in [1.0 / 3, 2.0 / 3] {
                            grid.move(to: CGPoint(x: canvas.width * fraction, y: 0))
                            grid.addLine(to: CGPoint(x: canvas.width * fraction, y: canvas.height))
                            grid.move(to: CGPoint(x: 0, y: canvas.height * fraction))
                            grid.addLine(to: CGPoint(x: canvas.width, y: canvas.height * fraction))
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.4)), lineWidth: 0.65)
                    }.allowsHitTesting(false)
                }
                .frame(width: box.width, height: box.height).contentShape(Rectangle())
                .position(x: box.midX, y: box.midY)
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    preview.stop()
                    if cropOrigin == nil { cropOrigin = CGPoint(x: rect.centerX, y: rect.centerY) }
                    guard let origin = cropOrigin else { return }
                    project.crop.centerX = min(1 - rect.width / 2, max(rect.width / 2, origin.x + value.translation.width / size.width))
                    project.crop.centerY = min(1 - rect.height / 2, max(rect.height / 2, origin.y + value.translation.height / size.height))
                }.onEnded { _ in cropOrigin = nil })
                .accessibilityLabel("Crop area. Drag to reframe.")
                .accessibilityIdentifier("cropSelection")
        }.frame(width: size.width, height: size.height)
    }

    private func overlaySelections(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(project.overlays.filter { $0.isActive(at: preview.time) }) { overlay in
                let rect = overlay.rect(at: preview.time)
                let width = rect.width * size.width
                let height = rect.height * size.height
                let selected = selectedOverlay == overlay.id
                ZStack {
                    overlayVisual(overlay, selected: selected)
                    if selected {
                        Rectangle().strokeBorder(LoopTheme.lime, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        VStack {
                            HStack { Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold)).padding(5).background(LoopTheme.lime, in: .circle).foregroundStyle(LoopTheme.deep) }
                            Spacer()
                        }.allowsHitTesting(false)
                    }
                }.frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .position(x: rect.centerX * size.width, y: rect.centerY * size.height)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        preview.stop(); selectedOverlay = overlay.id
                        if overlayOrigin == nil { overlayOrigin = rect }
                        guard var moved = overlayOrigin else { return }
                        moved.x += value.translation.width / size.width
                        moved.y += value.translation.height / size.height
                        setRect(moved.clamped(), id: overlay.id)
                    }.onEnded { _ in overlayOrigin = nil })
                    .accessibilityLabel("\(overlay.title) overlay. Drag to reposition.")
                    .accessibilityIdentifier("overlay-\(overlay.kind.rawValue)")
                if selected {
                    Circle().fill(LoopTheme.lime).frame(width: 26, height: 26)
                        .overlay { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .bold)).foregroundStyle(LoopTheme.deep) }
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .position(x: (rect.x + rect.width) * size.width, y: (rect.y + rect.height) * size.height)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            preview.stop()
                            if resizeOrigin == nil { resizeOrigin = rect }
                            guard var resized = resizeOrigin else { return }
                            resized.width = min(1 - resized.x, max(0.03, resized.width + value.translation.width / size.width))
                            resized.height = min(1 - resized.y, max(0.03, resized.height + value.translation.height / size.height))
                            setRect(resized.clamped(), id: overlay.id)
                        }.onEnded { _ in resizeOrigin = nil })
                        .accessibilityLabel("Resize selected overlay")
                }
            }
        }.frame(width: size.width, height: size.height)
    }

    @ViewBuilder private func overlayVisual(_ overlay: OverlayItem, selected: Bool) -> some View {
        if overlay.kind == .emoji || overlay.kind == .text {
            Text(overlay.content).font(.system(size: 65, weight: .bold)).minimumScaleFactor(0.08)
                .multilineTextAlignment(.center).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 2).padding(4)
        } else {
            let fill = overlay.kind == .cover ? Color.black : LoopTheme.teal.opacity(0.35)
            if overlay.shape == .ellipse {
                Ellipse().fill(fill).overlay { Ellipse().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            } else {
                Rectangle().fill(fill).overlay { Rectangle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            }
            Image(systemName: overlay.kind.symbol).font(.title3).foregroundStyle(.white)
        }
    }

    private func setRect(_ rect: NormalizedRect, id: UUID) {
        guard let index = project.overlays.firstIndex(where: { $0.id == id }) else { return }
        if !project.overlays[index].keyframes.isEmpty {
            project.overlays[index].setKeyframe(at: preview.time, rect: rect)
        } else {
            project.overlays[index].rect = rect
        }
    }
}
