import XCTest
import UIKit
import simd
@testable import Orbit

final class GeometryTests: XCTestCase {
    func testAspectFitAndFillPreserveVideoShape() {
        let source = CGSize(width: 1920, height: 1080)
        let viewport = CGSize(width: 390, height: 844)
        let fit = OrbitGeometry.contentScale(source: source, viewport: viewport, fill: false)
        let fill = OrbitGeometry.contentScale(source: source, viewport: viewport, fill: true)
        XCTAssertEqual(fit.x, 1, accuracy: 0.0001)
        XCTAssertLessThan(fit.y, 1)
        XCTAssertEqual(fill.y, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(fill.x, 1)
        for scale in [fit, fill] {
            XCTAssertEqual(Double(scale.x) * Double(viewport.width) / (Double(scale.y) * Double(viewport.height)),
                           Double(source.width / source.height), accuracy: 0.001)
        }
    }

    func testRotatedVideoUsesCorrectEncodedTextureCoordinates() {
        let source = CGSize(width: 1920, height: 1080)
        let transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let display = OrbitGeometry.displaySize(source: source, transform: transform)
        XCTAssertEqual(display.width, 1080, accuracy: 0.001)
        XCTAssertEqual(display.height, 1920, accuracy: 0.001)
        let matrix = OrbitGeometry.textureTransform(source: source, transform: transform)
        let topLeft = matrix * SIMD3<Float>(0, 0, 1)
        let topRight = matrix * SIMD3<Float>(1, 0, 1)
        let bottomLeft = matrix * SIMD3<Float>(0, 1, 1)
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 1, accuracy: 0.0001)
        XCTAssertEqual(topRight.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topRight.y, 0, accuracy: 0.0001)
        XCTAssertEqual(bottomLeft.x, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomLeft.y, 1, accuracy: 0.0001)
    }

    func testMotionAxesFollowInterfaceOrientation() {
        let value = SIMD2<Double>(0.3, -0.7)
        XCTAssertEqual(OrbitGeometry.screenTilt(value, orientation: .portrait), value)
        XCTAssertEqual(OrbitGeometry.screenTilt(value, orientation: .landscapeLeft), SIMD2(0.7, 0.3))
        XCTAssertEqual(OrbitGeometry.screenTilt(value, orientation: .landscapeRight), SIMD2(-0.7, -0.3))
        XCTAssertEqual(OrbitGeometry.screenTilt(value, orientation: .portraitUpsideDown), -value)
    }

    func testTiltStaysBoundedAndRejectsInvalidSensorValues() {
        XCTAssertEqual(OrbitGeometry.boundedTilt(SIMD2(4, -3)), SIMD2(1, -1))
        XCTAssertEqual(OrbitGeometry.boundedTilt(SIMD2(Double.nan, Double.infinity)), .zero)
        XCTAssertEqual(OrbitGeometry.boundedTilt(SIMD2(0.25, -0.6)), SIMD2(0.25, -0.6))
    }
}
