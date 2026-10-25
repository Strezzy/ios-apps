import XCTest
import CoreGraphics
import CoreVideo
@preconcurrency import AVFoundation
@testable import Loop

final class PreviewTests: XCTestCase {
    @MainActor func testContinuousRequestsPublishBeforeInputStopsAndKeepOnlyLatestPending() async throws {
        let gate = PreviewTestGate()
        var presented: [Int] = []
        let pipeline = LatestPreviewWork<Int, Int>(operation: { await gate.run($0) },
            didProduce: { presented.append($0) }, didFail: { _ in XCTFail("Unexpected render error") })
        pipeline.submit(0)
        try await waitUntil { gate.running != nil }
        for value in 1...100 { pipeline.submit(value) }
        XCTAssertEqual(pipeline.queuedCount, 1)
        gate.finish()
        try await waitUntil { presented == [0] && gate.running?.value == 100 }
        // Further input is still arriving: the completed frame must remain visible.
        for value in 101...200 { pipeline.submit(value) }
        XCTAssertEqual(presented, [0])
        gate.finish()
        try await waitUntil { presented == [0, 100] && gate.running?.value == 200 }
        gate.finish()
        try await waitUntil { presented == [0, 100, 200] && !pipeline.isWorking }
        XCTAssertEqual(gate.maximumConcurrent, 1)
        XCTAssertEqual(pipeline.queuedCount, 0)
    }

    @MainActor func testOldSessionCannotPresentAfterClear() async throws {
        let gate = PreviewTestGate()
        var presented: [Int] = []
        let pipeline = LatestPreviewWork<Int, Int>(operation: { await gate.run($0) },
            didProduce: { presented.append($0) }, didFail: { _ in XCTFail("Unexpected render error") })
        pipeline.submit(1)
        try await waitUntil { gate.running != nil }
        pipeline.invalidate()
        pipeline.submit(2)
        gate.finish()
        try await waitUntil { gate.running?.value == 2 }
        XCTAssertTrue(presented.isEmpty)
        gate.finish()
        try await waitUntil { presented == [2] }
        XCTAssertEqual(gate.maximumConcurrent, 1)
    }

    func testPreviewCadenceUsesSourceRateSpeedAndDisplayCapability() {
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 60, speed: 1, displayMaximum: 120), 60)
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 120, speed: 1, displayMaximum: 120), 120)
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 240, speed: 1, displayMaximum: 60), 60)
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 24, speed: 0.5, displayMaximum: 120), 12)
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 60, speed: 2, displayMaximum: 120), 120)
        XCTAssertEqual(PreviewCadence.preferredRate(sourceRate: 29.97, speed: 1, displayMaximum: 60), 29.97, accuracy: 0.001)
    }

    @MainActor func testNativeScrubbingUpdatesContinuouslyBeforeRelease() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Scrub", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 2
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        let before = preview.presentationCount
        preview.beginScrubbing()
        for index in 0..<80 {
            preview.seek(to: 0.1 + Double(index) * 0.018, project: project, url: url)
            try await Task.sleep(nanoseconds: 12_000_000)
        }
        // This assertion runs while the finger is still down, before endScrubbing.
        XCTAssertGreaterThan(preview.presentationCount, before + 2)
        XCTAssertGreaterThan(preview.displayedTime, 0.2)
        let target = preview.time
        preview.endScrubbing(project: project, url: url)
        try await waitUntil(timeout: 10) { abs(preview.displayedTime - target) < 0.025 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertEqual(preview.displayedTime, target, accuracy: 0.025)
        XCTAssertGreaterThan(preview.nativeBufferCount, 0)
    }

    @MainActor func testPausedEffectEditRendersWithoutAnotherVideoDecode() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Paused edit", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 2
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.setPresentationMode(.editing)
        preview.time = 0.6
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        let count = preview.presentationCount
        let decodes = preview.nativeBufferCount + preview.fallbackFrameCount
        let original = try XCTUnwrap(preview.sourceFrame)
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 2)
        overlay.shape = .rectangle
        overlay.rect = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        project.overlays = [overlay]
        preview.refresh(project: project, url: url)
        try await waitUntil { preview.presentationCount > count || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertEqual(preview.nativeBufferCount + preview.fallbackFrameCount, decodes)
        XCTAssertFalse(preview.playing)
        XCTAssertEqual(preview.displayedTime, 0.6, accuracy: 0.001)
        let editing = try XCTUnwrap(preview.editingFrame)
        let bytes = try raster(editing)
        let middle = (editing.height / 2 * editing.width + editing.width / 2) * 4
        XCTAssertLessThan(bytes[middle], 5)
        XCTAssertLessThan(bytes[middle + 1], 5)
        XCTAssertEqual(preview.sourceFrame?.width, original.width)
        XCTAssertEqual(try raster(try XCTUnwrap(preview.sourceFrame)), try raster(original))
    }

    @MainActor func testNativePlaybackKeepsMovingWhileEffectsChange() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Live edit", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 2
        var blur = OverlayItem(kind: .blur, startTime: 0, endTime: 2)
        blur.rect = NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4)
        project.overlays = [blur]
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.setPresentationMode(.editing)
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        let count = preview.presentationCount
        let buffers = preview.nativeBufferCount
        preview.toggle(project: project, url: url)
        for index in 0..<30 {
            project.overlays[0].strength = Double(index) / 30
            preview.refresh(project: project, url: url)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(preview.playing)
        XCTAssertGreaterThan(preview.presentationCount, count + 4)
        XCTAssertGreaterThan(preview.nativeBufferCount, buffers + 4)
        XCTAssertGreaterThan(preview.displayedTime, 0.1)
        XCTAssertNil(preview.error)
    }

    @MainActor func testPlayAfterPausedTrimAndCropUpdatesNativePlaybackBounds() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Move the trimmed range", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.5
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)

        // Both handles move beyond the AVPlayerItem's original out point while paused.
        // Previously the item retained its 0.5-second bound and could not play here.
        project.trimStart = 1
        project.trimEnd = 1.8
        project.crop.aspect = .portrait
        project.crop.zoom = 1.3
        preview.time = 1
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { abs(preview.displayedTime - 1) < 0.025 || preview.error != nil }
        let buffers = preview.nativeBufferCount
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 5) { preview.displayedTime > 1.2 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
        XCTAssertGreaterThan(preview.nativeBufferCount, buffers + 2)
        let result = try XCTUnwrap(preview.renderedFrame)
        XCTAssertLessThan(result.width, result.height)
        XCTAssertLessThan(preview.displayedTime, project.trimEnd)
    }

    @MainActor func testPlayFromSelectedEndRestartsTheTrimmedLoop() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Play from end", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimStart = 0.4
        project.trimEnd = 1.2
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = project.trimEnd
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertGreaterThan(preview.displayedTime, 1.15)
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 5) { (preview.displayedTime > 0.45 && preview.displayedTime < 0.8) || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
        XCTAssertGreaterThan(preview.displayedTime, project.trimStart)
        XCTAssertLessThan(preview.displayedTime, 0.8)
    }

    @MainActor func testEditedTrimLoopsRepeatedlyWithoutFreezingAtTheOutPoint() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Repeat cropped loop", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.4
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        project.trimStart = 0.8
        project.trimEnd = 1.2
        project.crop.aspect = .square
        preview.seek(to: project.trimStart, project: project, url: url)
        try await waitUntil(timeout: 10) { abs(preview.displayedTime - 0.8) < 0.025 || preview.error != nil }
        XCTAssertNil(preview.error)
        var lastTime = preview.displayedTime
        var loops = 0
        var escapedRange = false
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 6) {
            let current = preview.displayedTime
            if current < lastTime - 0.15 { loops += 1 }
            if current < project.trimStart - 0.001 || current > project.trimEnd + 0.001 { escapedRange = true }
            lastTime = current
            return loops >= 2 || preview.error != nil
        }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
        XCTAssertEqual(loops, 2)
        XCTAssertFalse(escapedRange)
    }

    @MainActor func testReversePlaybackUsesEditedInPointInsteadOfOriginalBound() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Reverse edited trim", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimStart = 0.9
        project.trimEnd = 1.3
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = project.trimStart
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        project.trimStart = 0.4
        project.trimEnd = 1.7
        project.export.playback = .reverse
        preview.seek(to: 1.4, project: project, url: url)
        try await waitUntil(timeout: 10) { abs(preview.displayedTime - 1.4) < 0.025 || preview.error != nil }
        XCTAssertNil(preview.error)
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 5) { preview.displayedTime < 0.7 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
        XCTAssertLessThan(preview.displayedTime, 0.7)
        XCTAssertGreaterThanOrEqual(preview.displayedTime, project.trimStart)
    }

    @MainActor func testPingPongPlaybackReversesAndReturnsAfterBothTrimBoundaries() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Ping-pong cropped trim", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimStart = 0.6
        project.trimEnd = 1
        project.export.playback = .bounce
        project.crop.aspect = .portrait
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = project.trimStart
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 5) { preview.displayedTime > 0.88 || preview.error != nil }
        XCTAssertNil(preview.error)
        try await waitUntil(timeout: 5) { preview.displayedTime < 0.72 || preview.error != nil }
        XCTAssertNil(preview.error)
        try await waitUntil(timeout: 5) { preview.displayedTime > 0.88 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
    }

    @MainActor func testPlayAfterCanvasPinsAPendingScrubContinuesFromVisibleFrame() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Resume after positioning", sourceFilename: url.lastPathComponent, metadata: metadata)
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = 0.4
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        let visible = preview.displayedTime
        preview.beginScrubbing()
        preview.seek(to: 1.6, project: project, url: url)
        preview.beginCanvasInteraction()
        project.crop.aspect = .portrait
        project.crop.centerX = 0.7
        preview.refresh(project: project, url: url)
        preview.toggle(project: project, url: url)
        try await waitUntil(timeout: 5) { preview.displayedTime > visible + 0.15 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertTrue(preview.playing)
        XCTAssertLessThan(preview.displayedTime, 1.2, "The cancelled scrub target must not replace the pinned frame")
    }

    @MainActor func testPauseDuringPlaySeekDoesNotResumeFromItsCompletion() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        let project = LoopProject(name: "Pause pending play", sourceFilename: url.lastPathComponent, metadata: metadata)
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        preview.toggle(project: project, url: url)
        preview.stop()
        try await Task.sleep(nanoseconds: 350_000_000)
        let paused = preview.displayedTime
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(preview.playing)
        XCTAssertEqual(preview.displayedTime, paused, accuracy: 0.001)
        XCTAssertNil(preview.error)
    }

    @MainActor func testNativePortraitPreviewMatchesImageGeneratorOrientation() async throws {
        let url = try await makeVideo(portrait: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        let project = LoopProject(name: "Portrait", sourceFilename: url.lastPathComponent, metadata: metadata)
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = 0.3
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        XCTAssertGreaterThan(preview.nativeBufferCount, 0)
        let actual = try XCTUnwrap(preview.sourceFrame)
        let expected = try await MediaEngine.thumbnail(url: url, time: 0.3, maximumDimension: 960)
        XCTAssertEqual(actual.width, expected.width)
        XCTAssertEqual(actual.height, expected.height)
        let a = try raster(actual), b = try raster(expected)
        for fraction in [0.2, 0.4, 0.7, 0.85] {
            let x = Int(Double(actual.width) * fraction)
            let y = Int(Double(actual.height) * 0.35)
            let offset = (y * actual.width + x) * 4
            for channel in 0..<3 { XCTAssertEqual(Double(a[offset + channel]), Double(b[offset + channel]), accuracy: 25) }
        }
    }

    @MainActor func testCanvasInteractionPinsDisplayedPixelsAndRejectsPendingSeek() async throws {
        let url = try await makeVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        let project = LoopProject(name: "Place precisely", sourceFilename: url.lastPathComponent, metadata: metadata)
        let preview = EditorPreview()
        defer { preview.clear() }
        preview.time = 0.4
        preview.refresh(project: project, url: url)
        try await waitUntil(timeout: 10) { preview.presentationCount > 0 || preview.error != nil }
        XCTAssertNil(preview.error)
        let visible = preview.displayedTime
        preview.beginScrubbing()
        preview.seek(to: 1.6, project: project, url: url)
        preview.beginCanvasInteraction()
        XCTAssertEqual(preview.time, visible, accuracy: 0.001)
        // Allow cancelled native callbacks and in-flight rendering to return.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(preview.displayedTime, visible, accuracy: 0.001)
        XCTAssertEqual(preview.time, visible, accuracy: 0.001)
        XCTAssertFalse(preview.playing)
    }

    func testTinyEmojiRemainsRenderableAtPrecisionSize() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8,
            bytesPerRow: 640 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
        let source = try XCTUnwrap(context.makeImage())
        var project = LoopProject(name: "Tiny emoji", sourceFilename: "fixture.mov", metadata:
            VideoMetadata(name: "Fixture", duration: 2, size: PixelSize(width: 640, height: 360),
                          nominalFrameRate: 60, isHDR: false, byteCount: 0))
        var emoji = OverlayItem(kind: .emoji, startTime: 0, endTime: 2)
        emoji.content = "❤️"
        emoji.rect = NormalizedRect(x: 0.5, y: 0.5, width: 0.008, height: 0.014)
        project.overlays = [emoji]
        let rendered = try FrameRenderer.renderEditing(source, project: project, time: 0.5)
        let bytes = try raster(rendered)
        let changed = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0 + 1] < 230 }.count
        XCTAssertGreaterThan(changed, 0)
        XCTAssertLessThan(changed, 40)
    }

    func testEditingRenderShowsActualBlurAndPixelationInUncroppedSourceCoordinates() throws {
        let source = try checkerboard()
        var project = LoopProject(name: "Effects", sourceFilename: "fixture.mov", metadata:
            VideoMetadata(name: "Fixture", duration: 2, size: PixelSize(width: 320, height: 180),
                          nominalFrameRate: 60, isHDR: false, byteCount: 0))
        project.crop.aspect = .portrait
        project.crop.centerX = 0.75
        project.crop.mirror = true
        var effect = OverlayItem(kind: .blur, startTime: 0, endTime: 2)
        effect.shape = .rectangle
        effect.rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.6)
        effect.strength = 1
        project.overlays = [effect]
        let blurred = try FrameRenderer.renderEditing(source, project: project, time: 0.5)
        XCTAssertEqual(blurred.width, 320)
        XCTAssertEqual(blurred.height, 180)
        let original = try raster(source), blur = try raster(blurred)
        let interior = (90 * 320 + 80) * 4
        XCTAssertGreaterThan(abs(Int(original[interior]) - Int(blur[interior])), 20)
        let outside = (90 * 320 + 280) * 4
        XCTAssertEqual(Double(original[outside]), Double(blur[outside]), accuracy: 3)
        project.overlays[0].kind = .pixelate
        let pixelated = try raster(FrameRenderer.renderEditing(source, project: project, time: 0.5))
        let changed = stride(from: 0, to: original.count, by: 4).filter {
            abs(Int(original[$0]) - Int(pixelated[$0])) > 10
        }.count
        XCTAssertGreaterThan(changed, 100)
        XCTAssertEqual(Double(original[outside]), Double(pixelated[outside]), accuracy: 3)
    }

    @MainActor private func waitUntil(timeout: Double = 4, _ condition: @escaping @MainActor () -> Bool) async throws {
        let start = Date()
        while !condition() {
            guard Date().timeIntervalSince(start) < timeout else {
                XCTFail("The preview did not make progress before the deadline")
                throw LoopError.encoding("Preview test timed out")
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func raster(_ image: CGImage) throws -> [UInt8] {
        try EncoderRaster.rgba(image, size: PixelSize(width: image.width, height: image.height), opaque: true)
    }

    private func checkerboard() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 320, height: 180, bitsPerComponent: 8,
            bytesPerRow: 320 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for y in 0..<18 {
            for x in 0..<32 {
                context.setFillColor(CGColor(gray: (x + y) % 2 == 0 ? 1 : 0, alpha: 1))
                context.fill(CGRect(x: x * 10, y: y * 10, width: 10, height: 10))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    private func makeVideo(portrait: Bool = false) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LoopPreview-\(UUID().uuidString).mov")
        return try await Task.detached(priority: .userInitiated) {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 256, AVVideoHeightKey: 144,
                AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false,
                                                   AVVideoMaxKeyFrameIntervalKey: 30]])
            if portrait { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 144, ty: 0) }
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 256, kCVPixelBufferHeightKey as String: 144,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? LoopError.encoding("Fixture could not start") }
            writer.startSession(atSourceTime: .zero)
            for index in 0..<120 {
                let began = Date()
                while !input.isReadyForMoreMediaData {
                    guard Date().timeIntervalSince(began) < 10 else { throw LoopError.encoding("Fixture writer stalled") }
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                guard let pool = adaptor.pixelBufferPool else { throw LoopError.encoding("Missing pixel pool") }
                var created: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &created) == kCVReturnSuccess,
                      let buffer = created else { throw LoopError.encoding("Missing frame") }
                CVPixelBufferLockBaseAddress(buffer, [])
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 256, height: 144,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue |
                        CGImageAlphaInfo.premultipliedFirst.rawValue) else { throw LoopError.encoding("Missing frame context") }
                context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 128, height: 144))
                context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
                context.fill(CGRect(x: 128, y: 0, width: 128, height: 144))
                context.setFillColor(CGColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: 256, height: 24))
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(CGRect(x: 20 + index, y: 50, width: 24, height: 36))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60)) else {
                    throw writer.error ?? LoopError.encoding("Fixture frame failed")
                }
            }
            writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1))
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? LoopError.encoding("Fixture failed") }
            return url
        }.value
    }
}

@MainActor private final class PreviewTestGate {
    struct Running {
        var value: Int
        var continuation: CheckedContinuation<Int, Never>
    }
    var running: Running?
    private var concurrent = 0
    private(set) var maximumConcurrent = 0
    func run(_ value: Int) async -> Int {
        concurrent += 1
        maximumConcurrent = max(maximumConcurrent, concurrent)
        return await withCheckedContinuation { running = Running(value: value, continuation: $0) }
    }
    func finish() {
        guard let current = running else { return }
        running = nil; concurrent -= 1
        current.continuation.resume(returning: current.value)
    }
}
