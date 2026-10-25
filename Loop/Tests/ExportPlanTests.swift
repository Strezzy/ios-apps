import XCTest
@testable import Loop

final class ExportPlanTests: XCTestCase {
    func project(duration: Double = 1, fps: Double = 60) -> LoopProject {
        var p = LoopProject(name: "Test", sourceFilename: "input.mov", metadata: VideoMetadata(
            name: "Input", duration: duration, size: PixelSize(width: 3840, height: 2160),
            nominalFrameRate: fps, isHDR: false, byteCount: 1000))
        p.trimEnd = duration
        p.export.frameRate = fps
        return p
    }

    func testSixtyFramesHaveOneSecondOfGIFTimeWithoutDrift() throws {
        let plan = try ExportPlan(project: project())
        XCTAssertEqual(plan.frames.count, 60)
        XCTAssertEqual(plan.frames.map(\.gifDelayCentiseconds).reduce(0, +), 100)
        XCTAssertEqual(Set(plan.frames.map(\.gifDelayCentiseconds)), Set([1, 2]))
        XCTAssertEqual(plan.duration, 1, accuracy: 0.000001)
    }
    func testTwentyFourFPSTimingDoesNotAccumulateRoundingError() throws {
        let plan = try ExportPlan(project: project(duration: 60, fps: 24))
        XCTAssertEqual(plan.frames.count, 1440)
        XCTAssertEqual(plan.duration, 60, accuracy: 0.005)
    }
    func testAPNGUsesExactSixtiethSeconds() throws {
        var p = project(); p.export.format = .apng
        let plan = try ExportPlan(project: p)
        XCTAssertEqual(plan.frames[0].delay, 1.0 / 60, accuracy: 0.00000001)
        XCTAssertEqual(plan.duration, 1, accuracy: 0.000001)
    }
    func testHighFrameRateSourceCanBeSlowedAndSampled() throws {
        var p = project(duration: 2, fps: 240)
        p.export.frameRate = 60; p.export.speed = 0.25
        let plan = try ExportPlan(project: p)
        XCTAssertEqual(plan.frames.count, 480)
        XCTAssertEqual(plan.duration, 8, accuracy: 0.001)
        XCTAssertEqual(plan.frames[1].sourceTime, 1.0 / 240, accuracy: 0.000001)
    }
    func testNominalFrameRateIsNotUsedForSampling() throws {
        var p = project(duration: 1, fps: 24)
        p.metadata.nominalFrameRate = 29.97
        let a = try ExportPlan(project: p)
        p.metadata.nominalFrameRate = 0
        let b = try ExportPlan(project: p)
        XCTAssertEqual(a.frames.map(\.sourceTime), b.frames.map(\.sourceTime))
    }
    func testPortraitCropKeepsRequestedAspectAndMovesWithinSource() throws {
        var p = project(); p.crop.aspect = .portrait; p.crop.centerX = 1
        p.export.maximumDimension = 2160
        let r = p.crop.rect(source: p.metadata.size)
        XCTAssertEqual(r.x + r.width, 1, accuracy: 0.000001)
        XCTAssertEqual(r.height, 1, accuracy: 0.000001)
        let result = try ExportPlan(project: p).size
        XCTAssertEqual(result, PixelSize(width: 1215, height: 2160))
    }
    func testNativeResolutionIsBoundedAndDoesNotUpscaleByDefault() throws {
        var p = project(); p.export.maximumDimension = 0
        XCTAssertEqual(try ExportPlan(project: p).size, p.metadata.size)
        p.metadata.size = PixelSize(width: 7680, height: 4320)
        XCTAssertEqual(try ExportPlan(project: p).size, PixelSize(width: 4096, height: 2304))
        p.metadata.size = PixelSize(width: 320, height: 180)
        p.export.maximumDimension = 3840
        XCTAssertEqual(try ExportPlan(project: p).size, p.metadata.size)
        p.export.allowUpscaling = true
        XCTAssertEqual(try ExportPlan(project: p).size.longEdge, 3840)
    }
    func testReverseRetainsFrameCountAndReversesSampling() throws {
        var p = project(duration: 1, fps: 4); p.export.playback = .reverse
        XCTAssertEqual(try ExportPlan(project: p).frames.map(\.sourceTime), [0.75, 0.5, 0.25, 0])
    }
    func testPingPongDoesNotDuplicateTurnaroundFrames() throws {
        var p = project(duration: 1, fps: 4); p.export.playback = .bounce
        XCTAssertEqual(try ExportPlan(project: p).frames.map(\.sourceTime), [0, 0.25, 0.5, 0.75, 0.5, 0.25])
    }
    func testTrimAndSpeedPreserveSourceBounds() throws {
        var p = project(duration: 10, fps: 30)
        p.trimStart = 2; p.trimEnd = 3.1; p.export.speed = 2
        let plan = try ExportPlan(project: p)
        XCTAssertEqual(plan.frames.count, 17)
        XCTAssertEqual(plan.frames.first?.sourceTime, 2)
        XCTAssertLessThan(plan.frames.last!.sourceTime, 3.1)
        XCTAssertEqual(plan.duration, 0.55, accuracy: 0.011)
    }
    func testRejectsNonFiniteAndInvertedTrim() {
        var p = project(); p.trimStart = .nan
        XCTAssertThrowsError(try ExportPlan(project: p))
        p = project(); p.trimEnd = 2
        XCTAssertThrowsError(try ExportPlan(project: p))
        p = project(); p.export.frameRate = .infinity
        XCTAssertThrowsError(try ExportPlan(project: p))
        p = project(); p.export.speed = 0
        XCTAssertThrowsError(try ExportPlan(project: p))
    }
    func testExcessiveFrameCountRejectedBeforeAllocation() {
        let p = project(duration: 10000, fps: 60)
        XCTAssertThrowsError(try ExportPlan(project: p))
    }
    func testUnreviewedTrackingCannotBeExported() {
        var p = project()
        var overlay = OverlayItem(kind: .blur, startTime: 0, endTime: 1)
        overlay.trackingEnabled = true; overlay.trackingNeedsReview = true
        p.overlays = [overlay]
        XCTAssertThrowsError(try ExportPlan(project: p))
        p.overlays[0].trackingNeedsReview = false
        XCTAssertThrowsError(try ExportPlan(project: p), "An empty tracking path must not be accepted")
    }
    func testTrackedOverlayMustCoverItsEntireActiveRange() throws {
        var p = project()
        var overlay = OverlayItem(kind: .blur, startTime: 0, endTime: 1)
        overlay.trackingEnabled = true
        overlay.keyframes = [TrackingKeyframe(time: 0, rect: .centered), TrackingKeyframe(time: 1, rect: .centered)]
        p.overlays = [overlay]
        XCTAssertNoThrow(try ExportPlan(project: p))
        p.overlays[0].keyframes[1].time = 0.5
        XCTAssertThrowsError(try ExportPlan(project: p))
    }
    func testManualKeyframeInterpolatesAndReplacesExistingPosition() {
        var overlay = OverlayItem(kind: .emoji, startTime: 0, endTime: 2)
        overlay.setKeyframe(at: 0, rect: NormalizedRect(x: 0, y: 0, width: 0.2, height: 0.2))
        overlay.setKeyframe(at: 2, rect: NormalizedRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2))
        XCTAssertEqual(overlay.rect(at: 1).x, 0.4, accuracy: 0.001)
        overlay.setKeyframe(at: 2, rect: .centered)
        XCTAssertEqual(overlay.keyframes.count, 2)
        XCTAssertEqual(overlay.rect(at: 2), .centered)
    }
    func testProjectRoundTripRetainsEveryEdit() throws {
        var p = project(); p.crop.aspect = .portrait; p.crop.zoom = 2; p.crop.mirror = true
        p.export.playback = .bounce; p.export.format = .apng
        p.overlays = [OverlayItem(kind: .text, content: "On repeat", startTime: 0, endTime: 1)]
        p.overlays[0].setKeyframe(at: 0.2, rect: .centered)
        XCTAssertEqual(try JSONDecoder().decode(LoopProject.self, from: JSONEncoder().encode(p)), p)
    }
}
