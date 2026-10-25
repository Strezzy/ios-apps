import XCTest
import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
@preconcurrency import AVFoundation
@testable import Loop

final class EngineTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoopEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLandscapeToPortraitCropAndMirrorUseSameGeometry() throws {
        let source = try image(width: 320, height: 180) { context in
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 180))
            context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 160, y: 0, width: 160, height: 180))
        }
        var project = project(width: 320, height: 180)
        project.crop.aspect = .portrait
        project.export.maximumDimension = 180
        let rendered = try FrameRenderer.render(source, project: project, time: 0)
        XCTAssertEqual(rendered.width, 101)
        XCTAssertEqual(rendered.height, 180)
        XCTAssertGreaterThan(pixel(rendered, x: 10, y: 90).r, 230)
        XCTAssertGreaterThan(pixel(rendered, x: 90, y: 90).b, 230)
        project.crop.mirror = true
        let mirrored = try FrameRenderer.render(source, project: project, time: 0)
        XCTAssertGreaterThan(pixel(mirrored, x: 10, y: 90).b, 230)
        XCTAssertGreaterThan(pixel(mirrored, x: 90, y: 90).r, 230)
    }

    func testRectangleAndCircleCoversStayAtSourceCoordinates() throws {
        let source = try solidImage(width: 200, height: 200, color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        var project = project(width: 200, height: 200)
        var cover = OverlayItem(kind: .cover, startTime: 0, endTime: 1)
        cover.rect = NormalizedRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        cover.shape = .rectangle
        project.overlays = [cover]
        let rectangle = try FrameRenderer.render(source, project: project, time: 0.5)
        XCTAssertLessThan(pixel(rectangle, x: 22, y: 22).r, 10)
        XCTAssertGreaterThan(pixel(rectangle, x: 150, y: 150).r, 245)
        project.overlays[0].shape = .ellipse
        let circle = try FrameRenderer.render(source, project: project, time: 0.5)
        XCTAssertGreaterThan(pixel(circle, x: 22, y: 22).r, 245)
        XCTAssertLessThan(pixel(circle, x: 60, y: 60).r, 10)
    }

    func testTimedCoverDoesNotChangeFramesOutsideItsRange() throws {
        let source = try solidImage(width: 128, height: 128, color: .init(red: 1, green: 0, blue: 0, alpha: 1))
        var project = project(width: 128, height: 128)
        var cover = OverlayItem(kind: .cover, startTime: 0.3, endTime: 0.7)
        cover.rect = NormalizedRect(x: 0, y: 0, width: 1, height: 1)
        cover.shape = .rectangle
        project.overlays = [cover]
        XCTAssertGreaterThan(pixel(try FrameRenderer.render(source, project: project, time: 0.2), x: 64, y: 64).r, 245)
        XCTAssertLessThan(pixel(try FrameRenderer.render(source, project: project, time: 0.5), x: 64, y: 64).r, 10)
        XCTAssertGreaterThan(pixel(try FrameRenderer.render(source, project: project, time: 0.8), x: 64, y: 64).r, 245)
    }

    func testTrackedOverlayMovesBetweenKeyframes() throws {
        let source = try solidImage(width: 200, height: 100, color: .init(red: 1, green: 1, blue: 1, alpha: 1))
        var project = project(width: 200, height: 100)
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 1)
        overlay.shape = .rectangle
        overlay.keyframes = [
            TrackingKeyframe(time: 0, rect: .init(x: 0.1, y: 0.3, width: 0.2, height: 0.4)),
            TrackingKeyframe(time: 1, rect: .init(x: 0.7, y: 0.3, width: 0.2, height: 0.4))
        ]
        project.overlays = [overlay]
        let result = try FrameRenderer.render(source, project: project, time: 0.5)
        XCTAssertLessThan(pixel(result, x: 100, y: 50).r, 10)
        XCTAssertGreaterThan(pixel(result, x: 40, y: 50).r, 245)
    }

    func testBlurChangesDetailButNotOutsideSelection() throws {
        let source = try image(width: 200, height: 200) { context in
            for y in 0..<20 {
                for x in 0..<20 {
                    context.setFillColor(CGColor(gray: (x + y) % 2 == 0 ? 1 : 0, alpha: 1))
                    context.fill(CGRect(x: x * 10, y: y * 10, width: 10, height: 10))
                }
            }
        }
        var project = project(width: 200, height: 200)
        var overlay = OverlayItem(kind: .blur, startTime: 0, endTime: 1)
        overlay.shape = .rectangle
        overlay.rect = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        overlay.strength = 1
        project.overlays = [overlay]
        let result = try FrameRenderer.render(source, project: project, time: 0.5)
        let inside = pixel(result, x: 95, y: 95).r
        XCTAssertGreaterThan(inside, 40)
        XCTAssertLessThan(inside, 240)
        XCTAssertEqual(Double(pixel(result, x: 5, y: 5).r), Double(pixel(source, x: 5, y: 5).r), accuracy: 3)
    }

    func testTextIsCompositedAtOutputResolution() throws {
        let source = try solidImage(width: 320, height: 180, color: .init(gray: 0, alpha: 1))
        var project = project(width: 320, height: 180)
        var text = OverlayItem(kind: .text, startTime: 0, endTime: 1)
        text.content = "LOOP"
        text.rect = NormalizedRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4)
        project.overlays = [text]
        let rendered = try FrameRenderer.render(source, project: project, time: 0.5)
        let bytes = try EncoderRaster.rgba(rendered, size: PixelSize(width: rendered.width, height: rendered.height), opaque: true)
        var brightPixels = 0
        for y in stride(from: 50, to: 130, by: 3) {
            for x in stride(from: 30, to: 290, by: 3) where bytes[(y * rendered.width + x) * 4] > 180 { brightPixels += 1 }
        }
        XCTAssertGreaterThan(brightPixels, 100)
    }

    func testVisionCoordinatesFlipVerticallyExactlyOnce() {
        let rect = NormalizedRect(x: 0.2, y: 0.1, width: 0.3, height: 0.2)
        let vision = TrackingEngine.visionRect(rect)
        XCTAssertEqual(vision.minX, 0.2, accuracy: 0.00001)
        XCTAssertEqual(vision.minY, 0.7, accuracy: 0.00001)
        XCTAssertEqual(vision.width, 0.3, accuracy: 0.00001)
    }

    func testVisionTrackingCoversBothSidesOfTheAnchor() async throws {
        let source = try await makeVideo(name: "tracking", frameTimes: (0..<12).map { Double($0) / 30 },
                                         duration: 0.4, trackingFixture: true)
        let metadata = try await MediaEngine.inspect(url: source)
        var project = LoopProject(name: "Tracking", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.4
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 0.4)
        overlay.rect = NormalizedRect(x: 0.25, y: 0.2, width: 0.42, height: 0.6)
        let keyframes = try await TrackingEngine.track(sourceURL: source, project: project, overlay: overlay,
            anchorTime: 0.2, control: ExportControl(), progress: { _ in })
        XCTAssertEqual(try XCTUnwrap(keyframes.first).time, 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(keyframes.last).time, 0.4, accuracy: 0.0001)
        XCTAssertGreaterThan(keyframes.count, 8)
        XCTAssertTrue(keyframes.allSatisfy { $0.confidence >= 0.3 })
        XCTAssertTrue(zip(keyframes, keyframes.dropFirst()).allSatisfy { pair in pair.0.time <= pair.1.time })
    }

    func testMetadataAndThumbnailRespectPortraitTransform() async throws {
        let url = try await makeVideo(name: "portrait", frameTimes: (0..<12).map { Double($0) / 60 },
                                      duration: 0.2, portrait: true)
        let metadata = try await MediaEngine.inspect(url: url)
        XCTAssertEqual(metadata.size, PixelSize(width: 96, height: 128))
        XCTAssertGreaterThan(metadata.nominalFrameRate, 1)
        let thumbnail = try await MediaEngine.thumbnail(url: url, time: 0.1)
        XCTAssertEqual(thumbnail.width, 96)
        XCTAssertEqual(thumbnail.height, 128)
        // The end scrub position should select the last frame instead of failing at end-of-file.
        _ = try await MediaEngine.thumbnail(url: url, time: metadata.duration)
    }

    func testActualGIFExportFrom60FPSVideoPreservesDurationAndFrameCount() async throws {
        let source = try await makeVideo(name: "sixty", frameTimes: (0..<18).map { Double($0) / 60 }, duration: 0.3)
        let metadata = try await MediaEngine.inspect(url: source)
        var project = LoopProject(name: "Test", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.3
        project.export.frameRate = 60
        project.export.maximumDimension = 128
        let destination = directory.appendingPathComponent("sixty.gif")
        let output = try await ExportEngine().export(sourceURL: source, project: project, destination: destination,
                                                     control: ExportControl(), progress: { _ in })
        XCTAssertEqual(output.frameCount, 18)
        XCTAssertEqual(output.duration, 0.3, accuracy: 0.005)
        XCTAssertGreaterThan(output.byteCount, 200)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(decoded), 18)
        var duration = 0.0
        for index in 0..<18 {
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, index, nil) as? [String: Any])
            let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary as String] as? [String: Any])
            duration += (gif[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime as String] as? Double) ?? 0
            XCTAssertNotNil(CGImageSourceCreateImageAtIndex(decoded, index, nil))
        }
        XCTAssertEqual(duration, 0.3, accuracy: 0.005)
    }

    func testVariableFrameRateVideoExportsByTime() async throws {
        let source = try await makeVideo(name: "variable", frameTimes: [0, 0.02, 0.06, 0.14, 0.20, 0.28], duration: 0.4)
        let metadata = try await MediaEngine.inspect(url: source)
        var project = LoopProject(name: "VFR", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.4
        project.export.frameRate = 25
        project.export.maximumDimension = 128
        let output = try await ExportEngine().export(sourceURL: source, project: project,
            destination: directory.appendingPathComponent("vfr.gif"), control: ExportControl(), progress: { _ in })
        XCTAssertEqual(output.frameCount, 10)
        XCTAssertEqual(output.duration, 0.4, accuracy: 0.005)
    }

    func testReverseAndPingPongExportWithoutAccumulatingFrames() async throws {
        let source = try await makeVideo(name: "reverse", frameTimes: (0..<6).map { Double($0) / 10 }, duration: 0.6)
        let metadata = try await MediaEngine.inspect(url: source)
        var project = LoopProject(name: "Reverse", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.6
        project.export.frameRate = 10
        project.export.maximumDimension = 128
        project.export.playback = .reverse
        let reverse = try await ExportEngine().export(sourceURL: source, project: project,
            destination: directory.appendingPathComponent("reverse.gif"), control: ExportControl(), progress: { _ in })
        XCTAssertEqual(reverse.frameCount, 6)
        project.export.playback = .bounce
        let bounce = try await ExportEngine().export(sourceURL: source, project: project,
            destination: directory.appendingPathComponent("bounce.gif"), control: ExportControl(), progress: { _ in })
        XCTAssertEqual(bounce.frameCount, 10)
    }

    func testActualAPNGExport() async throws {
        let source = try await makeVideo(name: "apng", frameTimes: (0..<6).map { Double($0) / 30 }, duration: 0.2)
        let metadata = try await MediaEngine.inspect(url: source)
        var project = LoopProject(name: "APNG", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.2
        project.export.frameRate = 30
        project.export.format = .apng
        project.export.maximumDimension = 128
        let output = try await ExportEngine().export(sourceURL: source, project: project,
            destination: directory.appendingPathComponent("test.png"), control: ExportControl(), progress: { _ in })
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(output.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(decoded), 6)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(decoded, 5, nil))
    }

    func testCancellationRemovesIncompleteOutput() async throws {
        let source = try await makeVideo(name: "cancel", frameTimes: (0..<12).map { Double($0) / 30 }, duration: 0.4)
        let metadata = try await MediaEngine.inspect(url: source)
        let project = LoopProject(name: "Cancel", sourceFilename: source.lastPathComponent, metadata: metadata)
        let control = ExportControl()
        let destination = directory.appendingPathComponent("cancel.gif")
        do {
            _ = try await ExportEngine().export(sourceURL: source, project: project, destination: destination,
                control: control, progress: { progress in if progress.completedFrames >= 1 { control.cancel() } })
            XCTFail("Export should throw after cancellation")
        } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasSuffix(".partial") })
    }

    func testPreCancelledControlAndUnavailableSourceFailCleanly() async throws {
        let control = ExportControl()
        control.pause()
        control.cancel()
        do { try await control.checkpoint(); XCTFail("Cancellation must interrupt a paused operation") } catch { }
        let destination = directory.appendingPathComponent("missing.gif")
        do {
            _ = try await ExportEngine().export(sourceURL: directory.appendingPathComponent("missing.mov"),
                project: project(width: 128, height: 96), destination: destination,
                control: ExportControl(), progress: { _ in })
            XCTFail("Missing input must fail")
        } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func project(width: Int, height: Int) -> LoopProject {
        var result = LoopProject(name: "Fixture", sourceFilename: "fixture.mov",
            metadata: VideoMetadata(name: "Fixture", duration: 1, size: PixelSize(width: width, height: height),
                                    nominalFrameRate: 30, isHDR: false, byteCount: 0))
        result.export.maximumDimension = 0
        return result
    }

    private func solidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
        try image(width: width, height: height) { context in
            context.setFillColor(color)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func image(width: Int, height: Int, drawing: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        drawing(context)
        return try XCTUnwrap(context.makeImage())
    }

    /// Returns display-space pixels, origin at top left.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        return (Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2]))
    }

    private func makeVideo(name: String, frameTimes: [Double], duration: Double,
                           portrait: Bool = false, trackingFixture: Bool = false) async throws -> URL {
        let url = directory.appendingPathComponent(name + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128, AVVideoHeightKey: 96,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false]
        ])
        if portrait { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 96, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 96,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for (index, time) in frameTimes.enumerated() {
            let began = Date()
            while !input.isReadyForMoreMediaData {
                if let error = writer.error { throw error }
                guard Date().timeIntervalSince(began) < 10 else { throw LoopError.encoding("Fixture writer timed out") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 128, 96, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
            XCTAssertEqual(status, kCVReturnSuccess)
            let frame = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(frame, [])
            if let address = CVPixelBufferGetBaseAddress(frame) {
                let context = try XCTUnwrap(CGContext(data: address, width: 128, height: 96, bitsPerComponent: 8,
                    bytesPerRow: CVPixelBufferGetBytesPerRow(frame), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
                let fraction = Double(index) / Double(max(1, frameTimes.count - 1))
                context.setFillColor(trackingFixture ? CGColor(gray: 0.1, alpha: 1)
                    : CGColor(red: fraction, green: 0.2, blue: 1 - fraction, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
                if trackingFixture {
                    for y in 0..<4 {
                        for x in 0..<4 {
                            context.setFillColor(CGColor(gray: (x + y) % 2 == 0 ? 1 : 0.4, alpha: 1))
                            context.fill(CGRect(x: 36 + Double(index) * 0.5 + Double(x) * 10,
                                                y: 28 + Double(y) * 10, width: 10, height: 10))
                        }
                    }
                } else {
                    context.setFillColor(CGColor(gray: 1, alpha: 1))
                    context.fill(CGRect(x: 10 + index, y: 20, width: 20, height: 30))
                }
            }
            CVPixelBufferUnlockBaseAddress(frame, [])
            guard adaptor.append(frame, withPresentationTime: CMTime(seconds: time, preferredTimescale: 60_000)) else {
                throw writer.error ?? LoopError.encoding("Fixture frame failed")
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 60_000))
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? LoopError.encoding("Fixture encoding failed") }
        return url
    }
}
