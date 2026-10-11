import CoreImage
import CoreVideo
import Metal
import XCTest
@testable import DepthCheck

final class RendererGeometryTests: XCTestCase {
    private let width = 120
    private let height = 80

    func testNearAndFarSurfacesHaveOppositeStereoDisparity() throws {
        let renderer = try makeRenderer()
        let stripe = CIImage(color: CIColor(red: 0, green: 1, blue: 0))
            .cropped(to: CGRect(x: 54, y: 0, width: 12, height: height))
        let image = stripe.composited(over: blackBackground())

        // With this width and amount, depth 1 / 0 gives a three-pixel
        // shift in each eye and therefore +6 / -6 pixels of total disparity.
        for (value, expectedDisparity) in [(Float(1), 6.0), (Float(0), -6.0)] {
            let depth = DepthMap(width: 2, height: 2, values: Array(repeating: value, count: 4))
            let pair = try renderer.render(source: image, depth: depth, options: geometryOptions())
            let left = try stripeCentroid(in: pair.left, rows: 12..<68, channel: .green)
            let right = try stripeCentroid(in: pair.right, rows: 12..<68, channel: .green)

            if value > 0.5 {
                XCTAssertGreaterThan(left, right, "Near content must have crossed disparity: left-eye X > right-eye X.")
            } else {
                XCTAssertLessThan(left, right, "Far content must have uncrossed disparity: left-eye X < right-eye X.")
            }
            XCTAssertEqual(left - right, expectedDisparity, accuracy: 0.75,
                           "The renderer must apply the specified disparity to both eyes.")
            XCTAssertEqual((left + right) / 2, 59.5, accuracy: 0.5,
                           "The two eye projections must remain centered on the source stripe.")
        }
    }

    func testDepthMapFirstRowAlignsWithTopOfTheSourceImage() throws {
        let renderer = try makeRenderer()
        // Core Image's upper half has larger Y coordinates. In the returned
        // BGRA buffers it must occupy the first rows, matching DepthMap row 0.
        let top = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 54, y: 40, width: 12, height: 40))
        let bottom = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 54, y: 0, width: 12, height: 40))
        let image = top.composited(over: bottom.composited(over: blackBackground()))
        let depth = DepthMap(width: 2, height: 2, values: [1, 1, 0, 0])
        let pair = try renderer.render(source: image, depth: depth, options: geometryOptions())

        // Stay away from the boundary where linear depth sampling deliberately
        // interpolates between the two rows. Color masks also detect a Y flip
        // in the source image itself instead of accepting a matching depth flip.
        let topLeft = try stripeCentroid(in: pair.left, rows: 8..<24, channel: .red)
        let topRight = try stripeCentroid(in: pair.right, rows: 8..<24, channel: .red)
        let bottomLeft = try stripeCentroid(in: pair.left, rows: 56..<72, channel: .blue)
        let bottomRight = try stripeCentroid(in: pair.right, rows: 56..<72, channel: .blue)

        XCTAssertGreaterThan(topLeft - topRight, 2,
                             "The first depth row must place the red top of the image in front of the screen plane.")
        XCTAssertLessThan(bottomLeft - bottomRight, -2,
                          "The last depth row must place the blue bottom of the image behind the screen plane.")
    }

    private func makeRenderer() throws -> StereoRenderer {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("This host does not expose a Metal device.")
        }
        return try StereoRenderer()
    }

    private func geometryOptions() -> ConversionOptions {
        var options = ConversionOptions()
        options.depthAmount = 0.10
        options.convergence = 0.5
        options.swapEyes = false
        return options
    }

    private func blackBackground() -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private enum BGRAChannel: Int { case blue = 0, green = 1, red = 2 }

    private func stripeCentroid(in buffer: CVPixelBuffer, rows: Range<Int>, channel: BGRAChannel,
                                file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              rows.lowerBound >= 0, rows.upperBound <= height else {
            throw DepthCheckError.message("The geometry test received an unexpected pixel-buffer format or size.")
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw DepthCheckError.message("The geometry test could not read the rendered pixels.")
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer), file: file, line: line)
            .assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var count = 0
        var sumX = 0.0
        for y in rows {
            for x in 0..<width {
                let pixel = y * stride + x * 4
                if base[pixel + channel.rawValue] >= 192,
                   base[pixel + (channel.rawValue + 1) % 3] <= 32,
                   base[pixel + (channel.rawValue + 2) % 3] <= 32 {
                    count += 1
                    sumX += Double(x)
                }
            }
        }
        XCTAssertGreaterThan(count, rows.count * 6,
                             "The expected colored stripe must occupy the requested image rows.", file: file, line: line)
        let denominator = try XCTUnwrap(count > 0 ? Double(count) : nil,
                                       "No pixels matched the expected stripe color.", file: file, line: line)
        return sumX / denominator
    }
}
