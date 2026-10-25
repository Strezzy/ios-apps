import Foundation
import CoreGraphics

/// A view-only transform. Its scale and center never change the saved crop or overlays.
/// Source coordinates are normalized to the upright image, before crop or mirroring.
struct CanvasViewport: Equatable, Sendable {
    static let minimumZoom = 1.0
    static let maximumZoom = 12.0
    var zoom: Double = 1
    var centerX: Double = 0.5
    var centerY: Double = 0.5

    static func fittedImageSize(in viewport: CGSize, sourceAspect: Double) -> CGSize {
        let width = max(1, viewport.width.isFinite ? viewport.width : 1)
        let height = max(1, viewport.height.isFinite ? viewport.height : 1)
        let aspect = max(0.0001, sourceAspect.isFinite ? sourceAspect : 1)
        let imageWidth = min(Double(width), Double(height) * aspect)
        return CGSize(width: imageWidth, height: imageWidth / aspect)
    }

    func clamped(in viewport: CGSize, sourceAspect: Double) -> Self {
        var result = self
        result.zoom = min(Self.maximumZoom, max(Self.minimumZoom, zoom.isFinite ? zoom : 1))
        let fitted = Self.fittedImageSize(in: viewport, sourceAspect: sourceAspect)
        let width = Double(fitted.width) * result.zoom
        let height = Double(fitted.height) * result.zoom
        let halfX = min(0.5, max(1, Double(viewport.width)) / (2 * width))
        let halfY = min(0.5, max(1, Double(viewport.height)) / (2 * height))
        result.centerX = min(1 - halfX, max(halfX, centerX.isFinite ? centerX : 0.5))
        result.centerY = min(1 - halfY, max(halfY, centerY.isFinite ? centerY : 0.5))
        return result
    }

    func imageRect(in viewport: CGSize, sourceAspect: Double) -> CGRect {
        let safe = clamped(in: viewport, sourceAspect: sourceAspect)
        let fitted = Self.fittedImageSize(in: viewport, sourceAspect: sourceAspect)
        let width = Double(fitted.width) * safe.zoom
        let height = Double(fitted.height) * safe.zoom
        return CGRect(x: Double(viewport.width) / 2 - safe.centerX * width,
                      y: Double(viewport.height) / 2 - safe.centerY * height,
                      width: width, height: height)
    }

    func viewPoint(for sourcePoint: CGPoint, in viewport: CGSize, sourceAspect: Double) -> CGPoint {
        let image = imageRect(in: viewport, sourceAspect: sourceAspect)
        return CGPoint(x: image.minX + sourcePoint.x * image.width,
                       y: image.minY + sourcePoint.y * image.height)
    }

    func sourcePoint(for viewPoint: CGPoint, in viewport: CGSize, sourceAspect: Double) -> CGPoint {
        let image = imageRect(in: viewport, sourceAspect: sourceAspect)
        return CGPoint(x: (viewPoint.x - image.minX) / image.width,
                       y: (viewPoint.y - image.minY) / image.height)
    }

    func viewRect(for sourceRect: NormalizedRect, in viewport: CGSize, sourceAspect: Double) -> CGRect {
        let image = imageRect(in: viewport, sourceAspect: sourceAspect)
        return CGRect(x: image.minX + sourceRect.x * image.width,
                      y: image.minY + sourceRect.y * image.height,
                      width: sourceRect.width * image.width,
                      height: sourceRect.height * image.height)
    }

    func sourceDelta(for translation: CGSize, in viewport: CGSize, sourceAspect: Double) -> CGSize {
        let image = imageRect(in: viewport, sourceAspect: sourceAspect)
        return CGSize(width: translation.width / image.width, height: translation.height / image.height)
    }

    func panned(by translation: CGSize, in viewport: CGSize, sourceAspect: Double) -> Self {
        let delta = sourceDelta(for: translation, in: viewport, sourceAspect: sourceAspect)
        var result = self
        result.centerX -= delta.width; result.centerY -= delta.height
        return result.clamped(in: viewport, sourceAspect: sourceAspect)
    }

    /// Preserves the source point under the fingers as both pinch scale and centroid change.
    /// Near an image edge, clamping prevents empty space from being dragged into the viewport.
    func zoomed(to newZoom: Double, from anchor: CGPoint, to destination: CGPoint? = nil,
                in viewport: CGSize, sourceAspect: Double) -> Self {
        let source = sourcePoint(for: anchor, in: viewport, sourceAspect: sourceAspect)
        let target = destination ?? anchor
        var result = self
        result.zoom = min(Self.maximumZoom, max(Self.minimumZoom, newZoom.isFinite ? newZoom : 1))
        let fitted = Self.fittedImageSize(in: viewport, sourceAspect: sourceAspect)
        let width = Double(fitted.width) * result.zoom
        let height = Double(fitted.height) * result.zoom
        result.centerX = source.x - (target.x - viewport.width / 2) / width
        result.centerY = source.y - (target.y - viewport.height / 2) / height
        return result.clamped(in: viewport, sourceAspect: sourceAspect)
    }

    struct HandleCenters: Equatable, Sendable {
        var delete: CGPoint
        var resize: CGPoint
    }

    /// Buttons remain 44 points, including when the overlay itself is only a few pixels.
    /// The reserved top/bottom bands contain the fixed status and zoom controls.
    static func handleCenters(for rectangle: CGRect, in viewport: CGSize,
                              topInset: CGFloat = 42, bottomInset: CGFloat = 52) -> HandleCenters {
        let half: CGFloat = 22
        let minX = half + 4, maxX = max(minX, viewport.width - half - 4)
        let minY = min(viewport.height / 2, topInset + half)
        let maxY = max(minY, viewport.height - bottomInset - half)
        func bounded(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(maxX, max(minX, point.x)), y: min(maxY, max(minY, point.y)))
        }
        let deletion = bounded(CGPoint(x: rectangle.maxX + half, y: rectangle.minY - half))
        let preferredResize = CGPoint(x: rectangle.maxX + half, y: rectangle.maxY + half)
        let candidates = [
            bounded(preferredResize),
            bounded(CGPoint(x: rectangle.minX - half, y: rectangle.maxY + half)),
            bounded(CGPoint(x: deletion.x, y: deletion.y + 48)),
            bounded(CGPoint(x: deletion.x, y: deletion.y - 48)),
            bounded(CGPoint(x: deletion.x - 48, y: deletion.y)),
            bounded(CGPoint(x: deletion.x + 48, y: deletion.y))
        ]
        // Non-overlapping axis-aligned 44-point touch targets; a diagonal-only gap is not enough.
        let resize = candidates.first {
            abs($0.x - deletion.x) >= 46 || abs($0.y - deletion.y) >= 46
        } ?? CGPoint(x: deletion.x < viewport.width / 2 ? maxX : minX, y: maxY)
        return HandleCenters(delete: deletion, resize: resize)
    }
}
