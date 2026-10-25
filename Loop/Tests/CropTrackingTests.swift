import XCTest
import CoreGraphics
import CoreVideo
import ImageIO
@preconcurrency import AVFoundation
@testable import Loop

final class CropTrackingTests: XCTestCase {
    func testLegacySavedCropDecodesWithoutTracking() throws {
        let old = Data(#"{"aspect":"portrait","centerX":0.3,"centerY":0.6,"zoom":1.8,"mirror":true}"#.utf8)
        let crop = try JSONDecoder().decode(CropSettings.self, from: old)
        XCTAssertNil(crop.tracking)
        XCTAssertEqual(crop.aspect, .portrait)
        XCTAssertEqual(crop.zoom, 1.8)
        XCTAssertTrue(crop.mirror)
    }

    func testTrackedProjectRoundTripPreservesIndependentOverlayPaths() throws {
        var project = fixture()
        project.crop = trackedCrop()
        var overlay = OverlayItem(kind: .pixelate, startTime: 0, endTime: 1)
        overlay.keyframes = [key(0, centerX: 0.2), key(1, centerX: 0.8)]
        overlay.trackingEnabled = true
        project.overlays = [overlay]
        let data = try JSONEncoder().encode(project)
        let restored = try JSONDecoder().decode(LoopProject.self, from: data)
        XCTAssertEqual(restored, project)
        XCTAssertEqual(restored.overlays[0].keyframes, overlay.keyframes)
        XCTAssertNotEqual(restored.overlays[0].keyframes, restored.crop.tracking?.keyframes)
    }

    func testTrackedCropPreservesAnchorCompositionAndFollowsAcrossSource() {
        var crop = trackedCrop()
        crop.centerX = 0.30
        let source = PixelSize(width: 400, height: 200)
        let anchor = crop.rect(source: source, at: 0)
        XCTAssertEqual(anchor, crop.rect(source: source))
        let later = crop.rect(source: source, at: 1)
        XCTAssertEqual(later.centerX - anchor.centerX, 0.50, accuracy: 0.00001)
        XCTAssertEqual(later.width, anchor.width, accuracy: 0.00001)
        XCTAssertEqual(later.height, anchor.height, accuracy: 0.00001)
    }

    func testTrackedCropClampsToSourceEdgesWithoutChangingAspect() {
        var crop = trackedCrop()
        crop.tracking?.keyframes = [key(0, centerX: 0.25), key(1, centerX: 0.95)]
        let source = PixelSize(width: 3840, height: 2160)
        let rect = crop.rect(source: source, at: 1)
        XCTAssertEqual(rect.x + rect.width, 1, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
        XCTAssertLessThanOrEqual(rect.y + rect.height, 1.000001)
        XCTAssertEqual(rect.width * Double(source.width) / (rect.height * Double(source.height)), 9.0 / 16, accuracy: 0.00001)
    }

    func testScaleFollowKeepsCompositionAsSubjectApproachesAndRecedes() {
        var crop = trackedCrop()
        crop.zoom = 2
        crop.tracking?.keyframes = [key(0, centerX: 0.25), key(0.5, centerX: 0.5, scale: 1.5), key(1, centerX: 0.75, scale: 0.5)]
        let source = PixelSize(width: 400, height: 200)
        let start = crop.rect(source: source, at: 0)
        let approaching = crop.rect(source: source, at: 0.5)
        let receding = crop.rect(source: source, at: 1)
        XCTAssertEqual(approaching.width / start.width, 1.5, accuracy: 0.00001)
        XCTAssertEqual(receding.width / start.width, 0.5, accuracy: 0.00001)
        XCTAssertEqual(approaching.centerX, 0.5, accuracy: 0.00001)
        XCTAssertEqual(receding.centerX, 0.75, accuracy: 0.00001)
        XCTAssertEqual(crop.framingScale(source: source, at: 0.5), 1.5, accuracy: 0.00001)
    }

    func testScaleFollowLimitsZoomAndCanBeDisabledIndependently() {
        var crop = trackedCrop()
        crop.zoom = 2
        crop.tracking?.keyframes = [key(0, centerX: 0.25), key(0.5, centerX: 0.5, scale: 5), key(1, centerX: 0.75, scale: 0.1)]
        let source = PixelSize(width: 400, height: 200)
        XCTAssertEqual(crop.rect(source: source, at: 0.5).height, 1, accuracy: 0.00001)
        XCTAssertEqual(crop.rect(source: source, at: 1).height, 0.125, accuracy: 0.00001)
        crop.tracking?.followScale = false
        XCTAssertEqual(crop.rect(source: source, at: 1).height, 0.5, accuracy: 0.00001)
        XCTAssertEqual(crop.rect(source: source, at: 1).centerX, 0.75, accuracy: 0.00001)
        crop.tracking?.enabled = false
        XCTAssertEqual(crop.rect(source: source, at: 1), crop.rect(source: source))
    }

    func testCropDragConvertsVisibleDistanceBackToAnchorFraming() {
        var crop = trackedCrop(); crop.zoom = 2
        crop.tracking?.keyframes[1] = key(1, centerX: 0.6, scale: 1.5)
        let source = PixelSize(width: 400, height: 200)
        let before = crop.rect(source: source, at: 1)
        let visibleDelta = 0.035
        crop.centerX += visibleDelta / crop.framingScale(source: source, at: 1)
        let after = crop.rect(source: source, at: 1)
        XCTAssertEqual(after.centerX - before.centerX, visibleDelta, accuracy: 0.00001)
        XCTAssertEqual(after.width, before.width, accuracy: 0.00001)
    }

    func testInterpolationAndReverseReadTheSameDeterministicPath() {
        let crop = trackedCrop()
        let source = PixelSize(width: 400, height: 200)
        let times = (0...20).map { Double($0) / 20 }
        let forward = times.map { crop.rect(source: source, at: $0) }
        let reverse = times.reversed().map { crop.rect(source: source, at: $0) }
        XCTAssertEqual(forward, Array(reverse.reversed()))
        XCTAssertEqual(crop.tracking?.rect(at: 0.5).centerX ?? 0, 0.5, accuracy: 0.00001)
        XCTAssertEqual(crop.rect(source: source, at: 0.5).centerX, 0.5, accuracy: 0.00001)
    }

    func testPathSmoothingReducesJitterButPreservesAnchorAndEndpoints() {
        let keys = (0...20).map { index -> TrackingKeyframe in
            let jitter = index.isMultiple(of: 2) ? 0.01 : -0.01
            return key(Double(index) / 30, centerX: 0.4 + jitter)
        }
        let smoothed = CropTrackingPath.smoothed(keys, anchorTime: keys[10].time)
        XCTAssertEqual(smoothed.first, keys.first)
        XCTAssertEqual(smoothed.last, keys.last)
        XCTAssertEqual(smoothed[10], keys[10])
        XCTAssertLessThan(abs(smoothed[5].rect.centerX - 0.4), abs(keys[5].rect.centerX - 0.4))
        XCTAssertEqual(smoothed.map(\.time), keys.map(\.time))
        XCTAssertEqual(smoothed.map(\.confidence), keys.map(\.confidence))
    }

    func testExportRequiresFullValidCropTrackAndAllowsDisablingIt() throws {
        var project = fixture()
        project.crop = trackedCrop()
        XCTAssertNoThrow(try ExportPlan(project: project))
        project.trimEnd = 1.4
        XCTAssertThrowsError(try ExportPlan(project: project))
        project.trimEnd = 1
        project.crop.tracking?.needsReview = true
        XCTAssertThrowsError(try ExportPlan(project: project))
        project.crop.tracking?.needsReview = false
        project.crop.tracking?.keyframes[1].confidence = 0.1
        XCTAssertThrowsError(try ExportPlan(project: project))
        project.crop.tracking?.keyframes[1].confidence = 1
        project.crop.tracking?.keyframes[1].time = 0
        XCTAssertThrowsError(try ExportPlan(project: project))
        project.crop.tracking?.enabled = false
        XCTAssertNoThrow(try ExportPlan(project: project))
    }

    func testCropTrackingAndOverlayTrackingStackInSourceCoordinates() throws {
        let source = try image(width: 400, height: 200) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        var project = fixture()
        project.crop = trackedCrop()
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 1)
        overlay.shape = .rectangle
        overlay.keyframes = [key(0, centerX: 0.25), key(1, centerX: 0.75)]
        overlay.trackingEnabled = true
        project.overlays = [overlay]
        let originalKeys = overlay.keyframes
        let expected = try ExportPlan(project: project).size
        for time in [0.0, 0.25, 0.75, 1.0] {
            let rendered = try FrameRenderer.render(source, project: project, time: time)
            XCTAssertEqual(PixelSize(width: rendered.width, height: rendered.height), expected)
            XCTAssertLessThan(try pixel(rendered, x: rendered.width / 2, y: rendered.height / 2), 5)
            XCTAssertGreaterThan(try pixel(rendered, x: 5, y: 5), 245)
        }
        XCTAssertEqual(project.overlays[0].keyframes, originalKeys)
    }

    func testRealBlurAndPixelationRemainAttachedThroughMovingCrop() throws {
        let source = try image(width: 400, height: 200) { context in
            for y in 0..<40 { for x in 0..<80 {
                context.setFillColor(CGColor(gray: (x + y).isMultiple(of: 2) ? 1 : 0, alpha: 1))
                context.fill(CGRect(x: x * 5, y: y * 5, width: 5, height: 5))
            } }
        }
        var project = fixture()
        project.crop = trackedCrop()
        for kind in [OverlayKind.blur, .pixelate] {
            var overlay = OverlayItem(kind: kind, startTime: 0, endTime: 1)
            overlay.shape = .rectangle; overlay.strength = 1
            overlay.keyframes = [key(0, centerX: 0.25, scale: 2), key(1, centerX: 0.75, scale: 2)]
            overlay.trackingEnabled = true
            project.overlays = [overlay]
            for time in [0.0, 1.0] {
                let rendered = try FrameRenderer.render(source, project: project, time: time)
                var unfiltered = project; unfiltered.overlays = []
                let plain = try FrameRenderer.render(source, project: unfiltered, time: time)
                let x = rendered.width / 2, y = rendered.height / 2
                let differences = try (-8...8).map { offset in
                    abs(try pixel(rendered, x: x + offset, y: y) - pixel(plain, x: x + offset, y: y))
                }
                XCTAssertGreaterThan(differences.reduce(0, +), 100, "\(kind) must render inside its tracked source region")
                let outside = try pixel(rendered, x: 5, y: 5)
                let unfilteredOutside = try pixel(plain, x: 5, y: 5)
                XCTAssertLessThanOrEqual(abs(outside - unfilteredOutside), 3)
            }
        }
    }

    func testMirrorAppliesAfterCropAndIndependentOverlayTracking() throws {
        let source = try image(width: 400, height: 200) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        var project = fixture(); project.crop = trackedCrop(); project.crop.mirror = true
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 1)
        overlay.shape = .rectangle
        overlay.keyframes = [
            TrackingKeyframe(time: 0, rect: .init(x: 0.29, y: 0.45, width: 0.04, height: 0.1)),
            TrackingKeyframe(time: 1, rect: .init(x: 0.79, y: 0.45, width: 0.04, height: 0.1))
        ]
        project.overlays = [overlay]
        let rendered = try FrameRenderer.render(source, project: project, time: 1)
        let crop = project.crop.rect(source: project.metadata.size, at: 1)
        let unmirroredFraction = (overlay.rect(at: 1).centerX - crop.x) / crop.width
        let mirroredX = Int((1 - unmirroredFraction) * Double(rendered.width))
        let unmirroredX = Int(unmirroredFraction * Double(rendered.width))
        XCTAssertLessThan(try pixel(rendered, x: mirroredX, y: rendered.height / 2), 5)
        XCTAssertGreaterThan(try pixel(rendered, x: unmirroredX, y: rendered.height / 2), 245)
    }

    func testEditingKeepsFullSourceWhileFinalCropMoves() throws {
        let source = try image(width: 400, height: 200) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }
        var project = fixture(); project.crop = trackedCrop()
        var cover = OverlayItem(kind: .cover, startTime: 0, endTime: 1)
        cover.shape = .rectangle; cover.keyframes = [key(0, centerX: 0.25), key(1, centerX: 0.75)]
        project.overlays = [cover]
        let editing = try FrameRenderer.renderEditing(source, project: project, time: 1)
        XCTAssertEqual(editing.width, 400); XCTAssertEqual(editing.height, 200)
        XCTAssertLessThan(try pixel(editing, x: 300, y: 100), 5)
        XCTAssertGreaterThan(try pixel(editing, x: 100, y: 100), 245)
    }

    func testOutputCanvasStaysFixedAndDecodingAccountsForTighterTrackedZoom() throws {
        var project = fixture(width: 3840, height: 2160)
        project.export.maximumDimension = 480
        project.crop = trackedCrop()
        let basePlan = try ExportPlan(project: project)
        project.crop.tracking?.keyframes[1] = key(1, centerX: 0.75, scale: 0.25)
        let trackedPlan = try ExportPlan(project: project)
        XCTAssertEqual(trackedPlan.size, basePlan.size)
        XCTAssertGreaterThan(trackedPlan.estimatedWorkingBytes, basePlan.estimatedWorkingBytes)
        let tightest = project.crop.minimumRect(source: project.metadata.size, from: 0, through: 1)
        XCTAssertEqual(tightest.width, project.crop.rect(source: project.metadata.size, at: 1).width, accuracy: 0.00001)
    }

    func testVisionCropTrackingFollowsRealVideoAndPreservesOverlayTracks() async throws {
        let url = try await makeTrackingVideo()
        defer { try? FileManager.default.removeItem(at: url) }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Subject", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.8; project.crop.aspect = .portrait
        let anchor = 0.4
        let subject = subjectRect(index: 12)
        project.crop.centerX = subject.centerX; project.crop.centerY = subject.centerY
        project.crop.tracking = CropTrackingSettings(subjectRect: subject, anchorTime: anchor)
        var overlay = OverlayItem(kind: .pixelate, startTime: 0, endTime: 0.8)
        overlay.rect = subject; overlay.keyframes = [TrackingKeyframe(time: 0, rect: subject)]
        project.overlays = [overlay]
        let savedOverlays = project.overlays
        let tracked = try await TrackingEngine.trackCrop(sourceURL: url, project: project, anchorTime: anchor,
            control: ExportControl(), progress: { _ in })
        XCTAssertTrue(tracked.enabled)
        XCTAssertFalse(tracked.needsReview)
        XCTAssertTrue(tracked.covers(start: 0, end: 0.8))
        XCTAssertEqual(tracked.rect(at: anchor), subject)
        XCTAssertGreaterThan(tracked.rect(at: 0.8).centerX - tracked.rect(at: 0).centerX, 0.25)
        XCTAssertEqual(project.overlays, savedOverlays)
        project.crop.tracking = tracked
        XCTAssertGreaterThan(project.crop.rect(source: metadata.size, at: 0.8).centerX,
                             project.crop.rect(source: metadata.size, at: 0).centerX + 0.25)
    }

    func testActualGIFExportCombinesTrackedCropAndTrackedOverlay() async throws {
        let url = try await makeTrackingVideo()
        let destination = url.deletingPathExtension().appendingPathExtension("gif")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: destination)
        }
        let metadata = try await MediaEngine.inspect(url: url)
        var project = LoopProject(name: "Stacked", sourceFilename: url.lastPathComponent, metadata: metadata)
        project.trimEnd = 0.8; project.crop.aspect = .portrait
        project.export.maximumDimension = 180; project.export.frameRate = 10
        let anchor = 0.4, subject = subjectRect(index: 12)
        project.crop.centerX = subject.centerX; project.crop.centerY = subject.centerY
        project.crop.tracking = CropTrackingSettings(subjectRect: subject, anchorTime: anchor, followScale: false)
        project.crop.tracking = try await TrackingEngine.trackCrop(sourceURL: url, project: project,
            anchorTime: anchor, control: ExportControl(), progress: { _ in })
        var overlay = OverlayItem(kind: .cover, startTime: 0, endTime: 0.8)
        overlay.shape = .rectangle; overlay.rect = subject
        overlay.keyframes = try await TrackingEngine.track(sourceURL: url, project: project, overlay: overlay,
            anchorTime: anchor, control: ExportControl(), progress: { _ in })
        overlay.trackingEnabled = true
        project.overlays = [overlay]
        let result = try await ExportEngine().export(sourceURL: url, project: project, destination: destination,
            control: ExportControl(), progress: { _ in })
        let decoded = try XCTUnwrap(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(decoded), 8)
        for index in [0, 4, 7] {
            let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoded, index, nil))
            XCTAssertEqual(PixelSize(width: frame.width, height: frame.height), result.size)
            XCTAssertLessThan(try pixel(frame, x: frame.width / 2, y: frame.height / 2), 15,
                              "The independently tracked cover must remain centered in the moving crop")
            XCTAssertGreaterThan(try pixel(frame, x: 3, y: 3), 180)
        }
    }

    private func fixture(width: Int = 400, height: Int = 200) -> LoopProject {
        var project = LoopProject(name: "Crop", sourceFilename: "fixture.mov", metadata: VideoMetadata(
            name: "Fixture", duration: 2, size: PixelSize(width: width, height: height),
            nominalFrameRate: 30, isHDR: false, byteCount: 0))
        project.trimEnd = 1; project.export.maximumDimension = 0
        return project
    }

    private func key(_ time: Double, centerX: Double, scale: Double = 1) -> TrackingKeyframe {
        TrackingKeyframe(time: time, rect: NormalizedRect(x: centerX - 0.05 * scale,
            y: 0.5 - 0.10 * scale, width: 0.1 * scale, height: 0.2 * scale).clamped())
    }

    private func trackedCrop() -> CropSettings {
        var crop = CropSettings()
        crop.aspect = .portrait; crop.centerX = 0.25
        let anchor = key(0, centerX: 0.25)
        crop.tracking = CropTrackingSettings(enabled: true, subjectRect: anchor.rect, anchorTime: 0,
            keyframes: [anchor, key(1, centerX: 0.75)])
        return crop
    }

    private func image(width: Int, height: Int, drawing: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        drawing(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let bytes = try EncoderRaster.rgba(image, size: PixelSize(width: image.width, height: image.height), opaque: true)
        return Int(bytes[(y * image.width + x) * 4])
    }

    private func subjectRect(index: Int) -> NormalizedRect {
        let fraction = Double(index) / 23
        let scale = 0.85 + fraction * 0.30
        let width = 64 * scale, height = 84 * scale
        let centerX = 70 + fraction * 174
        return NormalizedRect(x: (centerX - width / 2) / 320,
            y: (90 - height / 2) / 180, width: width / 320, height: height / 180)
    }

    private func makeTrackingVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LoopCropTrack-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
            AVVideoCompressionPropertiesKey: [AVVideoAllowFrameReorderingKey: false]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? LoopError.encoding("Fixture writer failed") }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<24 {
            let began = Date()
            while !input.isReadyForMoreMediaData {
                if let error = writer.error { throw error }
                guard Date().timeIntervalSince(began) < 10 else { throw LoopError.encoding("Fixture writer timed out") }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var rawBuffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &rawBuffer)
            XCTAssertEqual(status, kCVReturnSuccess)
            let buffer = try XCTUnwrap(rawBuffer)
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = try XCTUnwrap(CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 320, height: 180,
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
            context.setFillColor(CGColor(red: 0.9, green: 0.8, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            let rect = subjectRect(index: index)
            let box = CGRect(x: rect.x * 320, y: (1 - rect.y - rect.height) * 180,
                             width: rect.width * 320, height: rect.height * 180)
            for row in 0..<6 { for column in 0..<5 {
                let value = (row + column).isMultiple(of: 2) ? 0.05 : 0.97
                context.setFillColor(CGColor(gray: value, alpha: 1))
                context.fill(CGRect(x: box.minX + Double(column) * box.width / 5,
                    y: box.minY + Double(row) * box.height / 6, width: box.width / 5 + 0.5, height: box.height / 6 + 0.5))
            } }
            // An asymmetric mark prevents the tracker from confusing neighboring checks.
            context.setFillColor(CGColor(red: 0.95, green: 0.1, blue: 0.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: box.minX + 3, y: box.minY + 3, width: box.width * 0.22, height: box.width * 0.22))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? LoopError.encoding("Fixture frame failed")
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 0.8, preferredTimescale: 60_000))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? LoopError.encoding("Fixture video failed") }
        return url
    }
}
