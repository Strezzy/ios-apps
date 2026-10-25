import XCTest
import CoreGraphics
import ImageIO
@testable import Loop

final class EncoderTests: XCTestCase {
    func testGIFSinglePixelRoundTrip() throws {
        try withFile("gif") { url in
            let fixture = try makeImage(width: 1, height: 1) { _, _ in [255, 0, 0, 255] }
            let writer = try GIFEncoder(destination: url, size: .init(width: 1, height: 1), frameCount: 1, settings: .init())
            try writer.add(fixture.image, delay: 0.02, gifDelayCentiseconds: 2)
            try writer.finish()
            let source = try imageSource(url)
            XCTAssertEqual(CGImageSourceGetCount(source), 1)
            try assertPixels(source, index: 0, expected: fixture.pixels)
        }
    }

    func testGIF64ColorLZWWidthTransitionsAndDictionaryResets() throws { try checkGIFPaletteRoundTrip(64) }
    func testGIF128ColorLZWWidthTransitionsAndDictionaryResets() throws { try checkGIFPaletteRoundTrip(128) }
    func testGIF256ColorLZWWidthTransitionsAndDictionaryResets() throws { try checkGIFPaletteRoundTrip(256) }

    func testGIFPreservesAsymmetricOrientation() throws {
        try checkOrientation(format: .gif)
    }

    func testAPNGPreservesAsymmetricOrientation() throws {
        try checkOrientation(format: .apng)
    }

    func testGIFSixtyFPSUsesUnclampedCentisecondCadence() throws {
        try withFile("gif") { url in
            let fixture = try makeImage(width: 8, height: 8) { _, _ in [30, 80, 220, 255] }
            let ticks = [2, 1, 2, 2, 1, 2]
            let writer = try GIFEncoder(destination: url, size: .init(width: 8, height: 8), frameCount: ticks.count, settings: .init())
            for tick in ticks { try writer.add(fixture.image, delay: Double(tick) / 100, gifDelayCentiseconds: tick) }
            try writer.finish()
            let source = try imageSource(url)
            XCTAssertEqual(CGImageSourceGetCount(source), ticks.count)
            for index in ticks.indices {
                let properties = try frameProperties(source, index: index, dictionary: kCGImagePropertyGIFDictionary)
                let delay = try XCTUnwrap(properties[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)
                XCTAssertEqual(delay.doubleValue, Double(ticks[index]) / 100, accuracy: 0.000001)
            }
        }
    }

    func testGIFPlayOnceOmitsLoopExtension() throws { try checkGIFLoop(totalPlays: 1, encodedRepeats: nil) }
    func testGIFInfiniteLoopWritesZero() throws { try checkGIFLoop(totalPlays: 0, encodedRepeats: 0) }
    func testGIFFiniteLoopCountUsesAdditionalPlays() throws { try checkGIFLoop(totalPlays: 4, encodedRepeats: 3) }

    func testGIFDitheringChangesGradientAndRemainsDecodable() throws {
        let fixture = try makeImage(width: 191, height: 97) { x, y in
            [UInt8(x * 255 / 190), UInt8(y * 255 / 96), UInt8((x + y) * 255 / 286), 255]
        }
        var outputs: [Data] = []
        for dither in [false, true] {
            try withFile("gif") { url in
                var settings = ExportSettings()
                settings.paletteSize = 64
                settings.dither = dither
                let writer = try GIFEncoder(destination: url, size: .init(width: 191, height: 97), frameCount: 1, settings: settings)
                try writer.add(fixture.image, delay: 0.04, gifDelayCentiseconds: 4)
                try writer.finish()
                let source = try imageSource(url)
                let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(decoded.width, 191)
                XCTAssertEqual(decoded.height, 97)
                outputs.append(try Data(contentsOf: url))
            }
        }
        XCTAssertNotEqual(outputs[0], outputs[1], "Dithering must change the encoded image, not just metadata.")
    }

    func testGIFDoesNotRetainPaletteBetweenFrames() throws {
        try withFile("gif") { url in
            var settings = ExportSettings()
            settings.dither = false
            let writer = try GIFEncoder(destination: url, size: .init(width: 9, height: 7), frameCount: 3, settings: settings)
            var fixtures: [(image: CGImage, pixels: [UInt8])] = []
            let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]]
            for color in colors {
                let fixture = try makeImage(width: 9, height: 7) { _, _ in color }
                fixtures.append(fixture)
                try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10)
            }
            try writer.finish()
            let source = try imageSource(url)
            for index in fixtures.indices { try assertPixels(source, index: index, expected: fixtures[index].pixels) }
        }
    }

    func testGIFRejectsIncompleteFrameCount() throws {
        try checkIncompleteWriter(format: .gif)
    }

    func testAPNGRejectsIncompleteFrameCount() throws {
        try checkIncompleteWriter(format: .apng)
    }

    func testGIFRejectsExcessFrames() throws {
        try checkExcessFrames(format: .gif)
    }

    func testAPNGRejectsExcessFrames() throws {
        try checkExcessFrames(format: .apng)
    }

    func testWritersRejectMismatchedDimensions() throws {
        let fixture = try makeImage(width: 2, height: 2) { _, _ in [255, 255, 255, 255] }
        for format in AnimationFormat.allCases {
            try withFile(format.fileExtension) { url in
                let writer = try makeWriter(format, url: url, size: .init(width: 3, height: 2), count: 1)
                XCTAssertThrowsError(try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10))
                XCTAssertThrowsError(try writer.finish())
            }
        }
    }

    func testGIFRejectsUnrepresentableFrameDelay() throws {
        let fixture = try makeImage(width: 2, height: 2) { _, _ in [255, 0, 255, 255] }
        for tick in [0, -1, 65536] {
            try withFile("gif") { url in
                let writer = try GIFEncoder(destination: url, size: .init(width: 2, height: 2), frameCount: 1, settings: .init())
                XCTAssertThrowsError(try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: tick))
            }
        }
    }

    func testGIFRejectsUnsupportedPalette() throws {
        try withFile("gif") { url in
            var settings = ExportSettings()
            settings.paletteSize = 17
            XCTAssertThrowsError(try GIFEncoder(destination: url, size: .init(width: 2, height: 2), frameCount: 1, settings: settings))
        }
    }

    func testAPNGRoundTripFramesAndPreciseDelays() throws {
        try withFile("png") { url in
            var settings = ExportSettings()
            settings.loopCount = 3
            let writer = try APNGEncoder(destination: url, size: .init(width: 13, height: 9), frameCount: 3, settings: settings)
            let delays = [1.0 / 60, 1.0 / 24, 1001.0 / 30000]
            let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255]]
            var fixtures: [(image: CGImage, pixels: [UInt8])] = []
            for index in delays.indices {
                let fixture = try makeImage(width: 13, height: 9) { _, _ in colors[index] }
                fixtures.append(fixture)
                try writer.add(fixture.image, delay: delays[index], gifDelayCentiseconds: 2)
            }
            try writer.finish()
            let source = try imageSource(url)
            XCTAssertEqual(CGImageSourceGetCount(source), 3)
            for index in delays.indices {
                try assertPixels(source, index: index, expected: fixtures[index].pixels)
                let metadata = try frameProperties(source, index: index, dictionary: kCGImagePropertyPNGDictionary)
                let stored = (metadata[kCGImagePropertyAPNGUnclampedDelayTime as String] as? NSNumber) ??
                    (metadata[kCGImagePropertyAPNGDelayTime as String] as? NSNumber)
                XCTAssertEqual(try XCTUnwrap(stored).doubleValue, delays[index], accuracy: 0.000001)
            }
            let chunks = try pngChunks(Data(contentsOf: url))
            let animation = try XCTUnwrap(chunks.first { $0.name == "acTL" })
            XCTAssertEqual(read32(animation.payload, 0), 3)
            XCTAssertEqual(read32(animation.payload, 4), 3, "APNG stores total plays directly.")
        }
    }

    func testAPNGChunkCRCAndSequenceNumbers() throws {
        try withFile("png") { url in
            let writer = try APNGEncoder(destination: url, size: .init(width: 41, height: 37), frameCount: 4, settings: .init())
            for frame in 0..<4 {
                let fixture = try makeImage(width: 41, height: 37) { x, y in
                    [UInt8((x * 7 + frame * 53) % 256), UInt8((y * 13) % 256), UInt8(frame * 60), 255]
                }
                try writer.add(fixture.image, delay: 1.0 / 30, gifDelayCentiseconds: 3)
            }
            try writer.finish()
            let chunks = try pngChunks(Data(contentsOf: url))
            var sequence: UInt32 = 0
            for chunk in chunks {
                XCTAssertEqual(referenceCRC(Data(chunk.name.utf8) + chunk.payload), chunk.crc, "Invalid \(chunk.name) CRC")
                if chunk.name == "fcTL" || chunk.name == "fdAT" {
                    XCTAssertEqual(read32(chunk.payload, 0), sequence)
                    sequence += 1
                }
            }
            XCTAssertEqual(chunks.filter { $0.name == "fcTL" }.count, 4)
            XCTAssertEqual(chunks.last?.name, "IEND")
            XCTAssertEqual(CGImageSourceGetCount(try imageSource(url)), 4)
        }
    }

    func testAPNGPreservesTransparency() throws {
        try withFile("png") { url in
            let fixture = try makeImage(width: 19, height: 13) { x, _ in
                x < 6 ? [0, 0, 0, 0] : x < 12 ? [128, 0, 0, 128] : [0, 0, 255, 255]
            }
            let writer = try APNGEncoder(destination: url, size: .init(width: 19, height: 13), frameCount: 2, settings: .init())
            for _ in 0..<2 { try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10) }
            try writer.finish()
            let source = try imageSource(url)
            try assertPixels(source, index: 0, expected: fixture.pixels)
            try assertPixels(source, index: 1, expected: fixture.pixels)
        }
    }

    func testAPNGRepresentsCommonFrameRatesExactly() throws {
        for denominator in [1, 10, 24, 25, 30, 50, 60, 100, 120] {
            let fraction = try APNGDelay.fraction(1 / Double(denominator))
            XCTAssertEqual(Double(fraction.numerator) / Double(fraction.denominator), 1 / Double(denominator), accuracy: 1e-12)
        }
        for denominator in [24000, 30000, 60000] {
            let value = 1001.0 / Double(denominator)
            let fraction = try APNGDelay.fraction(value)
            XCTAssertEqual(Double(fraction.numerator) / Double(fraction.denominator), value, accuracy: 1e-12)
        }
    }

    func testAPNGRejectsInvalidDelay() throws {
        for value in [0.0, -1, .infinity, .nan, 65536] {
            XCTAssertThrowsError(try APNGDelay.fraction(value))
        }
    }

    func testWritersRejectZeroDimensionsAndFrameCounts() throws {
        for format in AnimationFormat.allCases {
            try withFile(format.fileExtension) { url in
                XCTAssertThrowsError(try makeWriter(format, url: url, size: .init(width: 0, height: 1), count: 1))
                XCTAssertThrowsError(try makeWriter(format, url: url, size: .init(width: 1, height: 1), count: 0))
            }
        }
    }

    func test4KRoundTripPreservesDimensionsAndCornerPixels() throws {
        let size = PixelSize(width: 3840, height: 2160)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: size.width, height: size.height,
                                            bitsPerComponent: 8, bytesPerRow: size.width * 4, space: space,
                                            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                                CGImageAlphaInfo.premultipliedLast.rawValue))
        let halfWidth = CGFloat(size.width / 2), halfHeight = CGFloat(size.height / 2)
        let colors: [[CGFloat]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [1, 1, 0]]
        for index in colors.indices {
            let color = colors[index]
            context.setFillColor(red: color[0], green: color[1], blue: color[2], alpha: 1)
            context.fill(CGRect(x: index.isMultiple(of: 2) ? 0 : halfWidth,
                                y: index < 2 ? 0 : halfHeight, width: halfWidth, height: halfHeight))
        }
        let original = try XCTUnwrap(context.makeImage())
        let corners = [(8, 8), (size.width - 9, 8), (8, size.height - 9), (size.width - 9, size.height - 9)]
        func pixel(_ image: CGImage, at point: (Int, Int)) throws -> [UInt8] {
            let crop = try XCTUnwrap(image.cropping(to: CGRect(x: CGFloat(point.0), y: CGFloat(point.1), width: 1, height: 1)))
            var bytes = [UInt8](repeating: 0, count: 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let pixelContext = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                         bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                                         bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                                             CGImageAlphaInfo.premultipliedLast.rawValue))
                pixelContext.setBlendMode(.copy)
                pixelContext.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return bytes
        }
        let expected = try corners.map { try pixel(original, at: $0) }
        for format in AnimationFormat.allCases {
            try autoreleasepool {
                try withFile(format.fileExtension) { url in
                    var settings = ExportSettings()
                    settings.paletteSize = 64
                    settings.dither = false
                    let writer: any AnimationWriter
                    if format == .gif {
                        writer = try GIFEncoder(destination: url, size: size, frameCount: 1, settings: settings)
                    } else {
                        writer = try APNGEncoder(destination: url, size: size, frameCount: 1, settings: settings)
                    }
                    try writer.add(original, delay: 0.04, gifDelayCentiseconds: 4)
                    try writer.finish()
                    let source = try imageSource(url)
                    XCTAssertEqual(CGImageSourceGetCount(source), 1)
                    let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    XCTAssertEqual(decoded.width, size.width)
                    XCTAssertEqual(decoded.height, size.height)
                    for index in corners.indices {
                        XCTAssertEqual(try pixel(decoded, at: corners[index]), expected[index],
                                       "\(format.title) changed 4K corner \(index).")
                    }
                }
            }
        }
    }

    // MARK: Test helpers

    private func checkGIFPaletteRoundTrip(_ colorCount: Int) throws {
        try withFile("gif") { url in
            var seed: UInt32 = 0x1234abcd
            let width = 257, height = 193
            let redLevels = colorCount >= 128 ? 8 : 4
            let greenLevels = colorCount == 256 ? 8 : 4
            let fixture = try makeImage(width: width, height: height) { _, _ in
                seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
                let value = Int(seed) % colorCount
                return [UInt8((value % redLevels) * 255 / (redLevels - 1)),
                        UInt8(((value / redLevels) % greenLevels) * 255 / (greenLevels - 1)),
                        UInt8((value / (redLevels * greenLevels)) * 255 / 3), 255]
            }
            var settings = ExportSettings()
            settings.paletteSize = colorCount
            settings.dither = false
            let writer = try GIFEncoder(destination: url, size: .init(width: width, height: height), frameCount: 1, settings: settings)
            try writer.add(fixture.image, delay: 0.04, gifDelayCentiseconds: 4)
            try writer.finish()
            try assertPixels(try imageSource(url), index: 0, expected: fixture.pixels)
            XCTAssertEqual(try firstGIFPaletteSize(Data(contentsOf: url)), colorCount)
        }
    }

    private func checkOrientation(format: AnimationFormat) throws {
        try withFile(format.fileExtension) { url in
            let fixture = try makeImage(width: 17, height: 11) { x, y in
                if y < 4 { return x < 6 ? [255, 0, 0, 255] : [0, 255, 0, 255] }
                return x < 6 ? [0, 0, 255, 255] : [255, 255, 0, 255]
            }
            let writer = try makeWriter(format, url: url, size: .init(width: 17, height: 11), count: 1)
            try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10)
            try writer.finish()
            try assertPixels(try imageSource(url), index: 0, expected: fixture.pixels)
        }
    }

    private func checkGIFLoop(totalPlays: Int, encodedRepeats: UInt16?) throws {
        try withFile("gif") { url in
            var settings = ExportSettings()
            settings.loopCount = totalPlays
            let fixture = try makeImage(width: 2, height: 2) { _, _ in [0, 255, 255, 255] }
            let writer = try GIFEncoder(destination: url, size: .init(width: 2, height: 2), frameCount: 1, settings: settings)
            try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10)
            try writer.finish()
            let data = try Data(contentsOf: url)
            let marker = data.range(of: Data("NETSCAPE2.0".utf8))
            if let repeats = encodedRepeats {
                let start = try XCTUnwrap(marker).upperBound
                XCTAssertEqual(data[start], 3)
                XCTAssertEqual(data[start + 1], 1)
                XCTAssertEqual(UInt16(data[start + 2]) | (UInt16(data[start + 3]) << 8), repeats)
            } else {
                XCTAssertNil(marker)
            }
        }
    }

    private func checkIncompleteWriter(format: AnimationFormat) throws {
        try withFile(format.fileExtension) { url in
            let fixture = try makeImage(width: 3, height: 3) { _, _ in [255, 0, 255, 255] }
            let writer = try makeWriter(format, url: url, size: .init(width: 3, height: 3), count: 2)
            try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10)
            XCTAssertThrowsError(try writer.finish())
            XCTAssertThrowsError(try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10))
        }
    }

    private func checkExcessFrames(format: AnimationFormat) throws {
        try withFile(format.fileExtension) { url in
            let fixture = try makeImage(width: 3, height: 3) { _, _ in [255, 0, 255, 255] }
            let writer = try makeWriter(format, url: url, size: .init(width: 3, height: 3), count: 1)
            try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10)
            XCTAssertThrowsError(try writer.add(fixture.image, delay: 0.1, gifDelayCentiseconds: 10))
            try writer.finish()
            XCTAssertThrowsError(try writer.finish())
        }
    }

    private func makeWriter(_ format: AnimationFormat, url: URL, size: PixelSize, count: Int) throws -> any AnimationWriter {
        if format == .gif { return try GIFEncoder(destination: url, size: size, frameCount: count, settings: .init()) }
        return try APNGEncoder(destination: url, size: size, frameCount: count, settings: .init())
    }

    private func withFile(_ ext: String, body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoopEncoderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("animation.\(ext)"))
    }

    private func makeImage(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> (image: CGImage, pixels: [UInt8]) {
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height { for x in 0..<width { pixels.append(contentsOf: pixel(x, y)) } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: space,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue |
                                            CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return (image, pixels)
    }

    private func imageSource(_ url: URL) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary))
    }

    private func frameProperties(_ source: CGImageSource, index: Int, dictionary: CFString) throws -> [String: Any] {
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any])
        return try XCTUnwrap(metadata[dictionary as String] as? [String: Any])
    }

    private func assertPixels(_ source: CGImageSource, index: Int, expected: [UInt8], file: StaticString = #filePath, line: UInt = #line) throws {
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil), file: file, line: line)
        var decoded = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try decoded.withUnsafeMutableBytes { bytes in
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                                    CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        }
        XCTAssertEqual(decoded.count, expected.count, file: file, line: line)
        let mismatch = zip(decoded, expected).enumerated().first { $0.element.0 != $0.element.1 }
        XCTAssertNil(mismatch?.offset, "Decoded pixels differ at byte \(mismatch?.offset ?? -1)", file: file, line: line)
    }

    private func firstGIFPaletteSize(_ data: Data) throws -> Int {
        var offset = 13
        if data[10] & 0x80 != 0 { offset += (2 << Int(data[10] & 7)) * 3 }
        while offset < data.count {
            if data[offset] == 0x2c { return data[offset + 9] & 0x80 != 0 ? 2 << Int(data[offset + 9] & 7) : 0 }
            guard data[offset] == 0x21 else { throw LoopError.encoding("Unexpected GIF block in test output.") }
            offset += 2
            while offset < data.count, data[offset] != 0 { offset += 1 + Int(data[offset]) }
            offset += 1
        }
        throw LoopError.encoding("No GIF image descriptor in test output.")
    }

    private struct TestPNGChunk {
        var name: String
        var payload: Data
        var crc: UInt32
    }

    private func pngChunks(_ data: Data) throws -> [TestPNGChunk] {
        var offset = 8
        var chunks: [TestPNGChunk] = []
        while offset + 12 <= data.count {
            let length = Int(read32(data, offset))
            guard offset + length + 12 <= data.count else { throw LoopError.encoding("Truncated test PNG.") }
            let name = try XCTUnwrap(String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii))
            let payload = Data(data[(offset + 8)..<(offset + 8 + length)])
            chunks.append(.init(name: name, payload: payload, crc: read32(data, offset + 8 + length)))
            offset += length + 12
        }
        XCTAssertEqual(offset, data.count)
        return chunks
    }

    private func read32(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }

    private func referenceCRC(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ 0xffffffff
    }
}
