import XCTest
import CoreImage
import CoreVideo
import Metal
@testable import DepthCheck

final class RendererTests: XCTestCase {
    func testFullResolutionGeometry() {
        let source = PixelSize(width: 3840, height: 2160)
        XCTAssertEqual(OutputFormat.sideBySide.outputSize(for: source), PixelSize(width: 7680, height: 2160))
        XCTAssertEqual(OutputFormat.overUnder.outputSize(for: source), PixelSize(width: 3840, height: 4320))
        XCTAssertEqual(OutputFormat.spatial.outputSize(for: source), source)
        XCTAssertEqual(OutputFormat.separateEyes.outputSize(for: source), source)
    }

    func testStereoAndPackingKeepSourcePixelsAndDepthDirection() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw XCTSkip("This host does not expose a Metal device.") }
        let renderer = try StereoRenderer()
        let image = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8)).cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
        let depth = DepthMap(width: 8, height: 8, values: Array(repeating: 0.5, count: 64))
        let pair = try renderer.render(source: image, depth: depth, options: ConversionOptions())
        XCTAssertEqual(CVPixelBufferGetWidth(pair.left), 96)
        XCTAssertEqual(CVPixelBufferGetHeight(pair.right), 64)
        let sbs = try renderer.packed(pair: pair, format: .sideBySide)
        XCTAssertEqual(CVPixelBufferGetWidth(sbs), 192)
        XCTAssertEqual(CVPixelBufferGetHeight(sbs), 64)
        CVPixelBufferLockBaseAddress(sbs, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(sbs, .readOnly) }
        let stride = CVPixelBufferGetBytesPerRow(sbs)
        let bytes = CVPixelBufferGetBaseAddress(sbs)!.assumingMemoryBound(to: UInt8.self)
        for x in [12, 80, 108, 180] {
            let index = 20 * stride + x * 4
            XCTAssertEqual(Double(bytes[index]), 204, accuracy: 8)
            XCTAssertEqual(Double(bytes[index + 1]), 102, accuracy: 8)
            XCTAssertEqual(Double(bytes[index + 2]), 51, accuracy: 8)
        }
    }
}
