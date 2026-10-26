import SwiftUI
import UIKit

enum EditorTool: String, CaseIterable, Identifiable {
    case clip, crop, overlays, effects, export
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self { case .clip: return "scissors"; case .crop: return "crop"; case .overlays: return "square.on.circle"; case .effects: return "camera.filters"; case .export: return "square.and.arrow.up" }
    }
}

struct EditorCanvas: View {
    @Binding var project: LoopProject
    @Binding var selectedOverlay: UUID?
    @ObservedObject var preview: EditorPreview
    var tool: EditorTool
    var showingResult: Bool
    var height: CGFloat = 240
    var selectingCropSubject: Bool = false
    @State private var sourceViewport = CanvasViewport()
    @State private var resultViewport = CanvasViewport()

    private var showSource: Bool { !showingResult && (tool == .crop || tool == .overlays) }
    private var aspect: Double { showSource ? project.metadata.size.aspect : project.crop.aspect.ratio(source: project.metadata.size) }
    private var viewport: Binding<CanvasViewport> { showSource ? $sourceViewport : $resultViewport }
    private var image: CGImage? {
        if !showSource { return preview.renderedFrame }
        return tool == .overlays ? preview.editingFrame : preview.sourceFrame
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.94)
                PrecisionCanvasSurface(project: $project, selectedOverlay: $selectedOverlay,
                                       viewport: viewport, image: image, tool: showSource ? tool : .clip,
                                       sourceAspect: aspect, time: preview.displayedTime,
                                       selectingCropSubject: selectingCropSubject,
                                       onInteraction: { preview.beginCanvasInteraction() })
                if image == nil { ProgressView().tint(.white).allowsHitTesting(false) }
                VStack {
                    if height >= 140 { HStack {
                        Text(showSource ? (tool == .overlays ? "EDIT" : selectingCropSubject ? "SELECT SUBJECT" : "SOURCE") : "RESULT")
                            .font(.system(size: 9, weight: .bold)).tracking(1.3)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.58), in: .capsule)
                        Spacer()
                        Text(LoopFormat.time(preview.displayedTime)).font(.caption2.monospacedDigit())
                            .accessibilityIdentifier("previewDisplayedTime")
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.58), in: .capsule)
                    }.allowsHitTesting(false) }
                    Spacer(minLength: 0)
                    if let error = preview.error {
                        Text(error).font(.caption).multilineTextAlignment(.center)
                            .padding(10).background(.black.opacity(0.82), in: .rect(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                    if height >= 140 { zoomControls(size: geometry.size) }
                }.foregroundStyle(.white).padding(8)
            }.clipShape(.rect(cornerRadius: 20))
        }.frame(height: height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editorCanvas")
    }

    private func zoomControls(size: CGSize) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                Button { changeZoom(viewport.wrappedValue.zoom / 1.5, size: size) } label: {
                    Image(systemName: "minus.magnifyingglass").frame(width: 44, height: 44)
                }.accessibilityLabel("Zoom out of video").accessibilityIdentifier("canvasZoomOut")
                    .disabled(viewport.wrappedValue.zoom <= 1.001)
                Button { viewport.wrappedValue = CanvasViewport() } label: {
                    Text(String(format: "%.1f×", viewport.wrappedValue.zoom)).font(.caption.monospacedDigit().weight(.semibold))
                        .frame(minWidth: 52, minHeight: 44)
                }.accessibilityLabel("Reset video view zoom").accessibilityIdentifier("canvasZoomReset")
                    .accessibilityValue(String(format: "zoom=%.6f", viewport.wrappedValue.zoom))
                Button { changeZoom(viewport.wrappedValue.zoom * 1.5, size: size) } label: {
                    Image(systemName: "plus.magnifyingglass").frame(width: 44, height: 44)
                }.accessibilityLabel("Zoom into video").accessibilityIdentifier("canvasZoomIn")
                    .disabled(viewport.wrappedValue.zoom >= CanvasViewport.maximumZoom - 0.001)
            }.buttonStyle(.plain)
                .background(.black.opacity(0.72), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7) }
        }
    }

    private func changeZoom(_ zoom: Double, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        viewport.wrappedValue = viewport.wrappedValue.zoomed(to: zoom, from: center, in: size, sourceAspect: aspect)
    }
}

/// The native surface keeps one set of gesture recognizers and layers while frames change.
/// Handles stay in viewport points; only the image and normalized geometry are transformed.
private struct PrecisionCanvasSurface: UIViewRepresentable {
    @Binding var project: LoopProject
    @Binding var selectedOverlay: UUID?
    @Binding var viewport: CanvasViewport
    var image: CGImage?
    var tool: EditorTool
    var sourceAspect: Double
    var time: Double
    var selectingCropSubject: Bool
    var onInteraction: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PrecisionCanvasView {
        let view = PrecisionCanvasView()
        let coordinator = context.coordinator
        view.onViewportChange = { [weak coordinator] in coordinator?.parent.viewport = $0 }
        view.onSelection = { [weak coordinator] in coordinator?.parent.selectedOverlay = $0 }
        view.onOverlayRect = { [weak coordinator] id, rect in coordinator?.setOverlay(id: id, rect: rect) }
        view.onCropCenter = { [weak coordinator] x, y in
            guard let coordinator else { return }
            coordinator.parent.project.crop.centerX = x
            coordinator.parent.project.crop.centerY = y
        }
        view.onSubjectRect = { [weak coordinator] rect in
            guard let coordinator else { return }
            var tracking = coordinator.parent.project.crop.tracking ?? CropTrackingSettings()
            tracking.subjectRect = rect.clamped()
            tracking.anchorTime = coordinator.parent.time
            tracking.enabled = false
            tracking.keyframes = []
            tracking.needsReview = false
            coordinator.parent.project.crop.tracking = tracking
        }
        view.onDelete = { [weak coordinator] id in
            guard let coordinator else { return }
            coordinator.parent.project.overlays.removeAll { $0.id == id }
            coordinator.parent.selectedOverlay = nil
        }
        view.onInteraction = { [weak coordinator] in coordinator?.parent.onInteraction() }
        return view
    }
    func updateUIView(_ view: PrecisionCanvasView, context: Context) {
        context.coordinator.parent = self
        view.update(project: project, selection: selectedOverlay, viewport: viewport,
                    image: image, tool: tool, aspect: sourceAspect, time: time,
                    selectingCropSubject: selectingCropSubject)
    }

    final class Coordinator {
        var parent: PrecisionCanvasSurface
        init(_ parent: PrecisionCanvasSurface) { self.parent = parent }
        func setOverlay(id: UUID, rect: NormalizedRect) {
            guard let index = parent.project.overlays.firstIndex(where: { $0.id == id }) else { return }
            if parent.project.overlays[index].keyframes.isEmpty {
                parent.project.overlays[index].rect = rect.clamped()
            } else {
                parent.project.overlays[index].setKeyframe(at: parent.time, rect: rect.clamped())
            }
        }
    }
}

private final class CanvasAccessibilityElement: UIAccessibilityElement {
    var activation: (() -> Void)?
    override func accessibilityActivate() -> Bool { activation?(); return activation != nil }
}

private final class PrecisionCanvasView: UIView, UIGestureRecognizerDelegate {
    var onViewportChange: ((CanvasViewport) -> Void)?
    var onSelection: ((UUID?) -> Void)?
    var onOverlayRect: ((UUID, NormalizedRect) -> Void)?
    var onCropCenter: ((Double, Double) -> Void)?
    var onSubjectRect: ((NormalizedRect) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?
    private var project: LoopProject?
    private var selection: UUID?
    private var viewport = CanvasViewport()
    private var aspect = 1.0
    private var time = 0.0
    private var tool: EditorTool = .clip
    private var selectingCropSubject = false
    private let imageLayer = CALayer()
    private let cropMask = CAShapeLayer()
    private let cropBorder = CAShapeLayer()
    private let cropGrid = CAShapeLayer()
    private let selectionOutline = CAShapeLayer()
    private let subjectOutline = CAShapeLayer()
    private let subjectLabel = UILabel()
    private let deleteButton = UIButton(type: .system)
    private let resizeButton = UIButton(type: .system)
    private let subjectResizeButton = UIButton(type: .system)
    private var overlayAccessibility: [UUID: CanvasAccessibilityElement] = [:]
    private lazy var cropAccessibility = CanvasAccessibilityElement(accessibilityContainer: self)
    private lazy var subjectAccessibility = CanvasAccessibilityElement(accessibilityContainer: self)
    private var lastImage: CGImage?
    private var pinchStart = CanvasViewport()
    private var pinchAnchor = CGPoint.zero
    private var panStart = CanvasViewport()
    private var panMode = PanMode.viewport
    private var dragRect = NormalizedRect.centered
    private var cropStart = CGPoint.zero
    private var cropDragScale = 1.0
    private var gestureOverlay: UUID?
    private var resizing = false
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    private lazy var resizePan = UIPanGestureRecognizer(target: self, action: #selector(resized(_:)))
    private lazy var subjectResizePan = UIPanGestureRecognizer(target: self, action: #selector(subjectResized(_:)))
    private enum PanMode: Equatable { case viewport, overlay, crop, subject, none }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        accessibilityIdentifier = "canvasViewport"
        accessibilityHint = "Pinch to zoom. Drag empty video to pan, or use two fingers to pan across a layer."
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        layer.addSublayer(imageLayer)
        cropMask.fillRule = .evenOdd
        cropMask.fillColor = UIColor.black.withAlphaComponent(0.64).cgColor
        layer.addSublayer(cropMask)
        cropBorder.strokeColor = UIColor.white.cgColor
        cropBorder.fillColor = nil
        cropBorder.lineWidth = 1.5
        layer.addSublayer(cropBorder)
        cropGrid.strokeColor = UIColor.white.withAlphaComponent(0.45).cgColor
        cropGrid.fillColor = nil
        cropGrid.lineWidth = 0.65
        layer.addSublayer(cropGrid)
        selectionOutline.strokeColor = UIColor(LoopTheme.lime).cgColor
        selectionOutline.fillColor = nil
        selectionOutline.lineWidth = 2
        selectionOutline.lineDashPattern = [6, 3]
        layer.addSublayer(selectionOutline)
        subjectOutline.strokeColor = UIColor(LoopTheme.lime).cgColor
        subjectOutline.fillColor = UIColor(LoopTheme.lime).withAlphaComponent(0.06).cgColor
        subjectOutline.lineWidth = 2
        layer.addSublayer(subjectOutline)
        subjectLabel.text = " SUBJECT "
        subjectLabel.font = .systemFont(ofSize: 9, weight: .bold)
        subjectLabel.textColor = UIColor(LoopTheme.deep)
        subjectLabel.backgroundColor = UIColor(LoopTheme.lime)
        subjectLabel.layer.cornerRadius = 4
        subjectLabel.clipsToBounds = true
        subjectLabel.isUserInteractionEnabled = false
        subjectLabel.isAccessibilityElement = false
        addSubview(subjectLabel)
        configureHandle(deleteButton, symbol: "xmark", color: .black.withAlphaComponent(0.86))
        deleteButton.accessibilityIdentifier = "overlayDelete"
        deleteButton.accessibilityLabel = "Delete selected overlay"
        deleteButton.addTarget(self, action: #selector(deleteSelected), for: .touchUpInside)
        configureHandle(resizeButton, symbol: "arrow.up.left.and.arrow.down.right", color: UIColor(LoopTheme.teal))
        resizeButton.accessibilityIdentifier = "overlayResize"
        resizeButton.accessibilityLabel = "Resize selected overlay"
        resizeButton.addGestureRecognizer(resizePan)
        resizeButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Make overlay smaller", target: self, selector: #selector(makeSmaller)),
            UIAccessibilityCustomAction(name: "Make overlay larger", target: self, selector: #selector(makeLarger))
        ]
        configureHandle(subjectResizeButton, symbol: "arrow.up.left.and.arrow.down.right", color: UIColor(LoopTheme.teal))
        subjectResizeButton.accessibilityIdentifier = "cropSubjectResize"
        subjectResizeButton.accessibilityLabel = "Resize crop tracking subject"
        subjectResizeButton.addGestureRecognizer(subjectResizePan)
        subjectResizeButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Make subject selection smaller", target: self, selector: #selector(subjectSmaller)),
            UIAccessibilityCustomAction(name: "Make subject selection larger", target: self, selector: #selector(subjectLarger))
        ]
        pan.maximumNumberOfTouches = 2
        let recognizers: [UIGestureRecognizer] = [pinch, pan, tap]
        for recognizer in recognizers { recognizer.delegate = self; addGestureRecognizer(recognizer) }
        tap.require(toFail: pan)
        resizePan.delegate = self
        subjectResizePan.delegate = self
        cropAccessibility.accessibilityIdentifier = "cropSelection"
        cropAccessibility.accessibilityLabel = "Crop selection. Drag to reframe."
        cropAccessibility.accessibilityTraits = .image
        subjectAccessibility.accessibilityIdentifier = "cropSubject"
        subjectAccessibility.accessibilityLabel = "Crop tracking subject"
        subjectAccessibility.accessibilityTraits = .image
    }
    required init?(coder: NSCoder) { nil }

    private func configureHandle(_ button: UIButton, symbol: String, color: UIColor) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.background.cornerRadius = 22
        configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        configuration.contentInsets = .zero
        button.configuration = configuration
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = CGSize(width: 0, height: 2)
        button.isHidden = true
        addSubview(button)
    }

    func update(project: LoopProject, selection: UUID?, viewport: CanvasViewport,
                image: CGImage?, tool: EditorTool, aspect: Double, time: Double,
                selectingCropSubject: Bool) {
        self.project = project; self.selection = selection; self.viewport = viewport
        self.tool = tool; self.aspect = aspect; self.time = time
        self.selectingCropSubject = selectingCropSubject
        if lastImage !== image { lastImage = image; imageLayer.contents = image }
        renderGeometry()
    }

    override func layoutSubviews() { super.layoutSubviews(); renderGeometry() }

    private func renderGeometry() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        viewport = viewport.clamped(in: bounds.size, sourceAspect: aspect)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.frame = viewport.imageRect(in: bounds.size, sourceAspect: aspect)
        for shape in [cropMask, cropBorder, cropGrid, selectionOutline, subjectOutline] { shape.frame = bounds }
        cropMask.isHidden = tool != .crop
        cropBorder.isHidden = tool != .crop
        cropGrid.isHidden = tool != .crop
        cropMask.fillColor = UIColor.black.withAlphaComponent(selectingCropSubject ? 0.32 : 0.64).cgColor
        if let project, tool == .crop {
            let crop = project.crop.rect(source: project.metadata.size, at: time)
            let rect = viewport.viewRect(for: crop, in: bounds.size, sourceAspect: aspect)
            let path = CGMutablePath(); path.addRect(imageLayer.frame); path.addRect(rect)
            cropMask.path = path
            cropBorder.path = CGPath(rect: rect, transform: nil)
            let grid = CGMutablePath()
            for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                grid.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
                grid.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
                grid.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
            }
            cropGrid.path = grid
            cropAccessibility.accessibilityFrameInContainerSpace = rect.intersection(bounds)
            cropAccessibility.accessibilityValue = String(format: "x=%.6f;y=%.6f;width=%.6f;height=%.6f;time=%.6f", crop.x, crop.y, crop.width, crop.height, time)
        }
        subjectOutline.isHidden = true; subjectLabel.isHidden = true; subjectResizeButton.isHidden = true
        if tool == .crop, let tracking = project?.crop.tracking,
           selectingCropSubject || tracking.enabled {
            let subject = selectingCropSubject ? tracking.subjectRect : tracking.rect(at: time)
            let rect = viewport.viewRect(for: subject, in: bounds.size, sourceAspect: aspect)
            let visibleRect = rect.intersection(bounds)
            if !visibleRect.isNull && !visibleRect.isEmpty {
                subjectOutline.isHidden = false
                subjectOutline.path = CGPath(rect: rect, transform: nil)
                subjectOutline.lineDashPattern = selectingCropSubject ? nil : [4, 3]
                subjectOutline.lineWidth = selectingCropSubject ? 2 : 1.5
                subjectLabel.isHidden = false
                subjectLabel.text = selectingCropSubject ? " SUBJECT " : " FOLLOWING "
                subjectLabel.sizeToFit()
                let labelWidth = subjectLabel.bounds.width + 4
                subjectLabel.frame = CGRect(x: min(bounds.width - labelWidth - 4, max(4, rect.minX)),
                                            y: min(bounds.height - 22, max(bounds.height < 140 ? 4 : 36, rect.minY - 19)),
                                            width: labelWidth, height: 17)
                subjectAccessibility.accessibilityFrameInContainerSpace = visibleRect
                subjectAccessibility.accessibilityValue = String(format: "x=%.6f;y=%.6f;width=%.6f;height=%.6f;time=%.6f", subject.x, subject.y, subject.width, subject.height, time)
                subjectAccessibility.accessibilityHint = selectingCropSubject ? "Drag to move. Use the corner handle or subject size controls to resize." : "The crop follows this subject through the clip."
                if selectingCropSubject {
                    let compact = bounds.height < 140
                    let handles = CanvasViewport.handleCenters(for: rect, in: bounds.size,
                                                                topInset: compact ? 4 : 36, bottomInset: compact ? 4 : 56)
                    subjectResizeButton.frame = CGRect(x: handles.resize.x - 22, y: handles.resize.y - 22, width: 44, height: 44)
                    subjectResizeButton.isHidden = false
                }
            }
        }
        selectionOutline.isHidden = true; deleteButton.isHidden = true; resizeButton.isHidden = true
        if tool == .overlays, let overlay = selectedItem(), overlay.isActive(at: time) {
            let rect = viewport.viewRect(for: overlay.rect(at: time), in: bounds.size, sourceAspect: aspect)
            selectionOutline.isHidden = false
            selectionOutline.path = overlay.kind.isRedaction && overlay.shape == .ellipse
                ? CGPath(ellipseIn: rect, transform: nil) : CGPath(rect: rect, transform: nil)
            let compact = bounds.height < 140
            let handles = CanvasViewport.handleCenters(for: rect, in: bounds.size,
                                                        topInset: compact ? 4 : 36, bottomInset: compact ? 4 : 56)
            deleteButton.frame = CGRect(x: handles.delete.x - 22, y: handles.delete.y - 22, width: 44, height: 44)
            resizeButton.frame = CGRect(x: handles.resize.x - 22, y: handles.resize.y - 22, width: 44, height: 44)
            deleteButton.isHidden = false; resizeButton.isHidden = false
            deleteButton.accessibilityLabel = "Delete selected " + overlay.kind.title.lowercased()
        }
        CATransaction.commit()
        updateAccessibility()
    }

    private func selectedItem() -> OverlayItem? { project?.overlays.first { $0.id == selection } }
    private func activeItems() -> [OverlayItem] { project?.overlays.filter { $0.isActive(at: time) } ?? [] }
    private func touchRect(for overlay: OverlayItem) -> CGRect {
        let rect = viewport.viewRect(for: overlay.rect(at: time), in: bounds.size, sourceAspect: aspect)
        return rect.insetBy(dx: -max(0, (44 - rect.width) / 2), dy: -max(0, (44 - rect.height) / 2))
    }
    private func overlay(at point: CGPoint) -> OverlayItem? {
        let active = activeItems()
        if let exact = active.reversed().first(where: {
            viewport.viewRect(for: $0.rect(at: time), in: bounds.size, sourceAspect: aspect).contains(point)
        }) { return exact }
        return active.filter { touchRect(for: $0).contains(point) }.min {
            let a = touchRect(for: $0), b = touchRect(for: $1)
            return hypot(a.midX - point.x, a.midY - point.y) < hypot(b.midX - point.x, b.midY - point.y)
        }
    }

    private func updateAccessibility() {
        accessibilityValue = String(format: "zoom=%.6f;centerX=%.6f;centerY=%.6f", viewport.zoom, viewport.centerX, viewport.centerY)
        var elements: [Any] = []
        if tool == .crop {
            elements.append(cropAccessibility)
            if !subjectOutline.isHidden { elements.append(subjectAccessibility) }
            if !subjectResizeButton.isHidden { elements.append(subjectResizeButton) }
        }
        if tool == .overlays {
            let active = activeItems()
            let ids = Set(active.map(\.id))
            overlayAccessibility = overlayAccessibility.filter { ids.contains($0.key) }
            for overlay in active {
                let rect = overlay.rect(at: time)
                let hitRect = touchRect(for: overlay).intersection(bounds)
                guard !hitRect.isNull, !hitRect.isEmpty else { continue }
                let element = overlayAccessibility[overlay.id] ?? CanvasAccessibilityElement(accessibilityContainer: self)
                element.accessibilityIdentifier = "overlay-" + overlay.kind.rawValue
                element.accessibilityLabel = overlay.title + " overlay"
                element.accessibilityValue = String(format: "x=%.6f;y=%.6f;width=%.6f;height=%.6f;zoom=%.6f", rect.x, rect.y, rect.width, rect.height, viewport.zoom)
                element.accessibilityTraits = overlay.id == selection ? [.button, .selected] : .button
                element.accessibilityFrameInContainerSpace = hitRect
                element.activation = { [weak self] in self?.select(overlay.id) }
                overlayAccessibility[overlay.id] = element
                elements.append(element)
            }
            if !deleteButton.isHidden { elements.append(deleteButton); elements.append(resizeButton) }
        }
        accessibilityElements = elements
    }

    private func select(_ id: UUID?) {
        selection = id; onSelection?(id); renderGeometry()
    }
    private func applyViewport(_ value: CanvasViewport) {
        viewport = value.clamped(in: bounds.size, sourceAspect: aspect)
        renderGeometry(); onViewportChange?(viewport)
    }
    private func applyOverlayRect(_ rect: NormalizedRect, id: UUID) {
        guard var project, let index = project.overlays.firstIndex(where: { $0.id == id }) else { return }
        if project.overlays[index].keyframes.isEmpty { project.overlays[index].rect = rect.clamped() }
        else { project.overlays[index].setKeyframe(at: time, rect: rect.clamped()) }
        self.project = project
        renderGeometry(); onOverlayRect?(id, rect.clamped())
    }

    private func applySubjectRect(_ rect: NormalizedRect) {
        guard var project, selectingCropSubject else { return }
        var tracking = project.crop.tracking ?? CropTrackingSettings()
        tracking.subjectRect = rect.clamped()
        tracking.anchorTime = time
        tracking.enabled = false
        tracking.keyframes = []
        tracking.needsReview = false
        project.crop.tracking = tracking
        self.project = project
        renderGeometry(); onSubjectRect?(tracking.subjectRect)
    }

    private func subjectTouchRect() -> CGRect? {
        guard let subject = project?.crop.tracking?.subjectRect else { return nil }
        let rect = viewport.viewRect(for: subject, in: bounds.size, sourceAspect: aspect)
        return rect.insetBy(dx: -max(0, (44 - rect.width) / 2), dy: -max(0, (44 - rect.height) / 2))
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if tool == .crop, selectingCropSubject, var rect = project?.crop.tracking?.subjectRect {
            let point = recognizer.location(in: self)
            guard imageLayer.frame.contains(point) else { return }
            onInteraction?()
            let source = viewport.sourcePoint(for: point, in: bounds.size, sourceAspect: aspect)
            rect.x = source.x - rect.width / 2
            rect.y = source.y - rect.height / 2
            applySubjectRect(rect)
            return
        }
        guard tool == .overlays else { return }
        onInteraction?()
        select(overlay(at: recognizer.location(in: self))?.id)
    }
    @objc private func pinched(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onInteraction?()
            // A resize gesture may already be active under the first finger. Its
            // source transform is obsolete once a pinch changes the viewport.
            resizing = false; gestureOverlay = nil
            pinchStart = viewport; pinchAnchor = recognizer.location(in: self); panMode = .none
        case .changed:
            applyViewport(pinchStart.zoomed(to: pinchStart.zoom * recognizer.scale, from: pinchAnchor,
                                           to: recognizer.location(in: self), in: bounds.size, sourceAspect: aspect))
        default: break
        }
    }
    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        if pinch.state == .began || pinch.state == .changed { return }
        switch recognizer.state {
        case .began:
            onInteraction?(); panStart = viewport
            let point = recognizer.location(in: self)
            if recognizer.numberOfTouches > 1 { panMode = .viewport }
            else if tool == .overlays, let overlay = overlay(at: point) {
                panMode = .overlay; gestureOverlay = overlay.id; dragRect = overlay.rect(at: time); select(overlay.id)
            } else if tool == .crop, selectingCropSubject, subjectTouchRect()?.contains(point) == true,
                      let subject = project?.crop.tracking?.subjectRect {
                panMode = .subject; dragRect = subject
            } else if tool == .crop, !selectingCropSubject, let project,
                      viewport.viewRect(for: project.crop.rect(source: project.metadata.size, at: time), in: bounds.size, sourceAspect: aspect).contains(point) {
                panMode = .crop
                let crop = project.crop.rect(source: project.metadata.size)
                cropStart = CGPoint(x: crop.centerX, y: crop.centerY)
                cropDragScale = max(0.001, project.crop.framingScale(source: project.metadata.size, at: time))
            } else { panMode = .viewport }
        case .changed:
            if recognizer.numberOfTouches > 1 && panMode != .viewport {
                panMode = .viewport; panStart = viewport; recognizer.setTranslation(.zero, in: self)
            }
            let translation = recognizer.translation(in: self)
            let delta = panStart.sourceDelta(for: CGSize(width: translation.x, height: translation.y), in: bounds.size, sourceAspect: aspect)
            switch panMode {
            case .viewport: applyViewport(panStart.panned(by: CGSize(width: translation.x, height: translation.y), in: bounds.size, sourceAspect: aspect))
            case .overlay:
                if let id = gestureOverlay {
                    var rect = dragRect; rect.x += delta.width; rect.y += delta.height
                    applyOverlayRect(rect, id: id)
                }
            case .crop:
                guard var project else { return }
                let crop = project.crop.rect(source: project.metadata.size)
                let x = min(1 - crop.width / 2, max(crop.width / 2, cropStart.x + delta.width / cropDragScale))
                let y = min(1 - crop.height / 2, max(crop.height / 2, cropStart.y + delta.height / cropDragScale))
                project.crop.centerX = x; project.crop.centerY = y
                self.project = project; renderGeometry(); onCropCenter?(x, y)
            case .subject:
                var rect = dragRect; rect.x += delta.width; rect.y += delta.height
                applySubjectRect(rect)
            case .none: break
            }
        default: gestureOverlay = nil; panMode = .viewport
        }
    }
    @objc private func resized(_ recognizer: UIPanGestureRecognizer) {
        if pinch.state == .began || pinch.state == .changed {
            resizing = false; gestureOverlay = nil
            return
        }
        switch recognizer.state {
        case .began:
            guard let overlay = selectedItem() else { return }
            onInteraction?(); resizing = true; dragRect = overlay.rect(at: time); gestureOverlay = overlay.id; panStart = viewport
        case .changed:
            guard resizing, let id = gestureOverlay else { return }
            let translation = recognizer.translation(in: self)
            let delta = panStart.sourceDelta(for: CGSize(width: translation.x, height: translation.y), in: bounds.size, sourceAspect: aspect)
            var rect = dragRect
            rect.width = min(1 - rect.x, max(0.005, rect.width + delta.width))
            rect.height = min(1 - rect.y, max(0.005, rect.height + delta.height))
            applyOverlayRect(rect, id: id)
        default: resizing = false; gestureOverlay = nil
        }
    }
    @objc private func deleteSelected() {
        guard let id = selection else { return }
        onInteraction?()
        project?.overlays.removeAll { $0.id == id }
        selection = nil
        renderGeometry(); onDelete?(id)
    }

    @objc private func subjectResized(_ recognizer: UIPanGestureRecognizer) {
        if pinch.state == .began || pinch.state == .changed {
            resizing = false
            return
        }
        switch recognizer.state {
        case .began:
            guard selectingCropSubject, let subject = project?.crop.tracking?.subjectRect else { return }
            onInteraction?(); resizing = true; dragRect = subject; panStart = viewport
        case .changed:
            guard resizing, selectingCropSubject else { return }
            let translation = recognizer.translation(in: self)
            let delta = panStart.sourceDelta(for: CGSize(width: translation.x, height: translation.y), in: bounds.size, sourceAspect: aspect)
            var rect = dragRect
            rect.width = min(1 - rect.x, max(0.02, rect.width + delta.width))
            rect.height = min(1 - rect.y, max(0.02, rect.height + delta.height))
            applySubjectRect(rect)
        default: resizing = false
        }
    }
    @objc private func subjectSmaller() -> Bool { resizeSubjectAccessibly(by: 0.85) }
    @objc private func subjectLarger() -> Bool { resizeSubjectAccessibly(by: 1.15) }
    private func resizeSubjectAccessibly(by scale: Double) -> Bool {
        guard selectingCropSubject, var rect = project?.crop.tracking?.subjectRect else { return false }
        onInteraction?()
        let center = CGPoint(x: rect.centerX, y: rect.centerY)
        rect.width = min(1, max(0.02, rect.width * scale))
        rect.height = min(1, max(0.02, rect.height * scale))
        rect.x = center.x - rect.width / 2
        rect.y = center.y - rect.height / 2
        applySubjectRect(rect); return true
    }
    @objc private func makeSmaller() -> Bool { resizeAccessibly(by: 0.85) }
    @objc private func makeLarger() -> Bool { resizeAccessibly(by: 1.15) }
    private func resizeAccessibly(by scale: Double) -> Bool {
        guard let overlay = selectedItem() else { return false }
        var rect = overlay.rect(at: time)
        rect.width *= scale; rect.height *= scale
        applyOverlayRect(rect, id: overlay.id); return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A pinch can begin over a handle. It cancels the button touch; a one-finger
        // X tap still goes exclusively to the button, never to background selection.
        if gestureRecognizer === pinch { return true }
        if gestureRecognizer === resizePan || gestureRecognizer === subjectResizePan { return true }
        var ancestor = touch.view
        while let view = ancestor, view !== self {
            if view is UIButton { return false }
            ancestor = view.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === pinch && otherGestureRecognizer === pan) ||
        (gestureRecognizer === pan && otherGestureRecognizer === pinch) ||
        (gestureRecognizer === pinch && otherGestureRecognizer === resizePan) ||
        (gestureRecognizer === resizePan && otherGestureRecognizer === pinch) ||
        (gestureRecognizer === pinch && otherGestureRecognizer === subjectResizePan) ||
        (gestureRecognizer === subjectResizePan && otherGestureRecognizer === pinch)
    }
}
