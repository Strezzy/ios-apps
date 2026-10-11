import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DepthCheck

final class PhotoMetadataTests: XCTestCase {
    func testTwoOrdinaryHEICImagesDoNotPassSpatialVerification() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ordinary-multi-image.heic")
        let size = PixelSize(width: 128, height: 72)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: size.width, height: size.height,
                                              bitsPerComponent: 8, bytesPerRow: size.width * 4,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.heic.identifier as CFString, 2, nil))
        for color in [CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGColor(red: 0, green: 0, blue: 1, alpha: 1)] {
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
            let image = try XCTUnwrap(context.makeImage())
            // Deliberately omit stereo groups and camera metadata. Merely
            // containing two full-size images cannot make a HEIC spatial.
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyHasAlpha: false] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2, "This fixture must contain two ordinary images.")
        for index in 0..<CGImageSourceGetCount(source) {
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])
            XCTAssertEqual((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, size.width)
            XCTAssertEqual((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, size.height)
        }
        XCTAssertThrowsError(try PhotoExporter.verify(url, expectedSize: size, spatial: true)) { error in
            XCTAssertTrue(error.localizedDescription.contains("stereo-pair metadata"),
                          "The rejection must be for missing stereo membership, not an unrelated encoding failure.")
        }
    }
}
