import XCTest
import CoreGraphics
@testable import Loop

final class CanvasViewportTests: XCTestCase {
    private let canvas = CGSize(width: 400, height: 300)
    private let aspect = 16.0 / 9

    func testFitCentersTheVideoWithoutCroppingOrStretching() {
        let rect = CanvasViewport().imageRect(in: canvas, sourceAspect: aspect)
        XCTAssertEqual(rect.width, 400, accuracy: 0.000001)
        XCTAssertEqual(rect.height, 225, accuracy: 0.000001)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 37.5, accuracy: 0.000001)
        XCTAssertEqual(rect.width / rect.height, aspect, accuracy: 0.000001)
    }

    func testPortraitSourceFitsWithoutUsingLandscapeCoordinates() {
        let rect = CanvasViewport().imageRect(in: canvas, sourceAspect: 9.0 / 16)
        XCTAssertEqual(rect.width, 168.75, accuracy: 0.000001)
        XCTAssertEqual(rect.height, 300, accuracy: 0.000001)
        XCTAssertEqual(rect.midX, 200, accuracy: 0.000001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.000001)
    }

    func testSourceAndViewportPointsRoundTripAtDifferentZoomsAndPans() {
        for zoom in [1.0, 1.5, 4, 12] {
            let viewport = CanvasViewport(zoom: zoom, centerX: 0.42, centerY: 0.61)
            for x in [0.0, 0.005, 0.37, 0.95, 1] {
                for y in [0.0, 0.19, 0.8, 1] {
                    let source = CGPoint(x: x, y: y)
                    let point = viewport.viewPoint(for: source, in: canvas, sourceAspect: aspect)
                    let recovered = viewport.sourcePoint(for: point, in: canvas, sourceAspect: aspect)
                    XCTAssertEqual(recovered.x, source.x, accuracy: 0.0000001)
                    XCTAssertEqual(recovered.y, source.y, accuracy: 0.0000001)
                }
            }
        }
    }

    func testPinchKeepsTheSameSourcePointUnderItsAnchor() {
        let initial = CanvasViewport()
        let anchor = CGPoint(x: 300, y: 190)
        let source = initial.sourcePoint(for: anchor, in: canvas, sourceAspect: aspect)
        let zoomed = initial.zoomed(to: 4, from: anchor, in: canvas, sourceAspect: aspect)
        let destination = zoomed.viewPoint(for: source, in: canvas, sourceAspect: aspect)
        XCTAssertEqual(destination.x, anchor.x, accuracy: 0.000001)
        XCTAssertEqual(destination.y, anchor.y, accuracy: 0.000001)
    }

    func testMovingPinchCentroidPansTheSameSourcePoint() {
        let initial = CanvasViewport(zoom: 2, centerX: 0.5, centerY: 0.5)
        let anchor = CGPoint(x: 180, y: 140)
        let destination = CGPoint(x: 240, y: 185)
        let source = initial.sourcePoint(for: anchor, in: canvas, sourceAspect: aspect)
        let changed = initial.zoomed(to: 3.5, from: anchor, to: destination, in: canvas, sourceAspect: aspect)
        let actual = changed.viewPoint(for: source, in: canvas, sourceAspect: aspect)
        XCTAssertEqual(actual.x, destination.x, accuracy: 0.000001)
        XCTAssertEqual(actual.y, destination.y, accuracy: 0.000001)
    }

    func testOverlayDragDeltaGetsMorePreciseAsViewZoomIncreases() {
        let translation = CGSize(width: 24, height: 18)
        let fitted = CanvasViewport().sourceDelta(for: translation, in: canvas, sourceAspect: aspect)
        let magnified = CanvasViewport(zoom: 8).sourceDelta(for: translation, in: canvas, sourceAspect: aspect)
        XCTAssertEqual(fitted.width / magnified.width, 8, accuracy: 0.000001)
        XCTAssertEqual(fitted.height / magnified.height, 8, accuracy: 0.000001)
        XCTAssertEqual(magnified.width, 0.0075, accuracy: 0.000001)
        XCTAssertEqual(magnified.height, 0.01, accuracy: 0.000001)
    }

    func testTinyOverlayPlacementRemainsAttachedAfterZoomingBackOut() {
        var rect = NormalizedRect(x: 0.48, y: 0.52, width: 0.005, height: 0.005)
        let magnified = CanvasViewport(zoom: 10, centerX: 0.48, centerY: 0.52)
        let delta = magnified.sourceDelta(for: CGSize(width: 31, height: -14), in: canvas, sourceAspect: aspect)
        rect.x += delta.width; rect.y += delta.height
        let original = rect
        for viewport in [magnified, CanvasViewport(zoom: 3), CanvasViewport()] {
            let displayed = viewport.viewRect(for: rect, in: canvas, sourceAspect: aspect)
            let source = viewport.sourcePoint(for: displayed.origin, in: canvas, sourceAspect: aspect)
            XCTAssertEqual(source.x, original.x, accuracy: 0.000001)
            XCTAssertEqual(source.y, original.y, accuracy: 0.000001)
            XCTAssertEqual(rect, original, "Viewing transforms must never mutate the saved overlay.")
        }
    }

    func testPanIsBoundedToTheImageAtEveryEdge() {
        let initial = CanvasViewport(zoom: 4)
        for translation in [CGSize(width: 10000, height: 10000), CGSize(width: -10000, height: -10000)] {
            let moved = initial.panned(by: translation, in: canvas, sourceAspect: aspect)
            let rect = moved.imageRect(in: canvas, sourceAspect: aspect)
            XCTAssertLessThanOrEqual(rect.minX, 0.000001)
            XCTAssertLessThanOrEqual(rect.minY, 0.000001)
            XCTAssertGreaterThanOrEqual(rect.maxX, canvas.width - 0.000001)
            XCTAssertGreaterThanOrEqual(rect.maxY, canvas.height - 0.000001)
        }
    }

    func testPanningFittedVideoDoesNotMoveLetterboxing() {
        let initial = CanvasViewport()
        let attempted = initial.panned(by: CGSize(width: 50, height: 70), in: canvas, sourceAspect: aspect)
        XCTAssertEqual(attempted, initial)
    }

    func testZoomLimitsAndInvalidValuesHaveSafeGeometry() {
        let huge = CanvasViewport(zoom: 500, centerX: -20, centerY: 99).clamped(in: canvas, sourceAspect: aspect)
        XCTAssertEqual(huge.zoom, 12)
        XCTAssertGreaterThan(huge.centerX, 0)
        XCTAssertLessThan(huge.centerY, 1)
        let invalid = CanvasViewport(zoom: .nan, centerX: .infinity, centerY: .nan).clamped(in: canvas, sourceAspect: aspect)
        XCTAssertEqual(invalid, CanvasViewport())
        let below = CanvasViewport(zoom: 0.1).clamped(in: canvas, sourceAspect: aspect)
        XCTAssertEqual(below.zoom, 1)
    }

    func testTinyEdgeOverlayHasTwoVisibleNonOverlapping44PointHandles() {
        let size = CGSize(width: 390, height: 240)
        let cases = [CGRect(x: 1, y: 1, width: 1, height: 1),
                     CGRect(x: 389, y: 239, width: 1, height: 1),
                     CGRect(x: 194, y: 119, width: 2, height: 2),
                     CGRect(x: -500, y: -500, width: 400, height: 400)]
        for rect in cases {
            let centers = CanvasViewport.handleCenters(for: rect, in: size)
            let deletion = CGRect(x: centers.delete.x - 22, y: centers.delete.y - 22, width: 44, height: 44)
            let resize = CGRect(x: centers.resize.x - 22, y: centers.resize.y - 22, width: 44, height: 44)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(deletion))
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(resize))
            XCTAssertFalse(deletion.intersects(resize))
        }
    }

    func testKeyboardHeightStillKeepsBothHandlesInsideTheCanvas() {
        let size = CGSize(width: 390, height: 100)
        let centers = CanvasViewport.handleCenters(for: CGRect(x: 389, y: 99, width: 1, height: 1), in: size, topInset: 4, bottomInset: 4)
        let deletion = CGRect(x: centers.delete.x - 22, y: centers.delete.y - 22, width: 44, height: 44)
        let resize = CGRect(x: centers.resize.x - 22, y: centers.resize.y - 22, width: 44, height: 44)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(deletion))
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(resize))
        XCTAssertFalse(deletion.intersects(resize))
    }
}
