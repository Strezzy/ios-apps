import XCTest
import CoreGraphics
@testable import Loop

final class TrackingResourceTests: XCTestCase {
    func testReal4K60CropTrackingCompletesBothDirectionsAndRendersTheResult() async throws {
        // Use an actual 3840×2160 / 60 FPS encoded source, not 4K metadata on a
        // small fixture. Analyze from the middle to exercise both Vision sessions.
        let source = try await DebugFixture.make4K60TrackingVideo(frameCount: 60)
        defer { try? FileManager.default.removeItem(at: source) }
        let metadata = try await MediaEngine.inspect(url: source)
        XCTAssertEqual(metadata.size, PixelSize(width: 3840, height: 2160))
        XCTAssertEqual(metadata.nominalFrameRate, 60, accuracy: 0.1)
        XCTAssertEqual(metadata.duration, 1, accuracy: 0.02)

        var project = LoopProject(name: "4K60 tracking", sourceFilename: source.lastPathComponent, metadata: metadata)
        project.trimEnd = metadata.duration
        project.crop.aspect = .portrait
        project.export.maximumDimension = 2160
        let subject = DebugFixture.trackingSubjectRect(frame: 30, frameCount: 60)
        project.crop.centerX = subject.centerX
        project.crop.centerY = subject.centerY
        project.crop.tracking = CropTrackingSettings(subjectRect: subject, anchorTime: 0.5)
        let tracked = try await TrackingEngine.trackCrop(sourceURL: source, project: project,
            anchorTime: 0.5, control: ExportControl(), progress: { _ in })
        XCTAssertTrue(tracked.enabled)
        XCTAssertFalse(tracked.needsReview)
        XCTAssertTrue(tracked.covers(start: project.trimStart, end: project.trimEnd))
        XCTAssertEqual(try XCTUnwrap(tracked.keyframes.first).time, 0, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(tracked.keyframes.last).time, metadata.duration, accuracy: 0.00001)
        XCTAssertEqual(tracked.rect(at: 0.5), subject)
        XCTAssertGreaterThan(tracked.rect(at: metadata.duration).centerX - tracked.rect(at: 0).centerX, 0.1)
        XCTAssertTrue(tracked.keyframes.allSatisfy { $0.confidence >= 0.3 })

        project.crop.tracking = tracked
        // Completion immediately transitions to the result preview on device.
        // Check that transition with the real decoder's bounded image and source
        // geometry; the project's selected high-resolution export is retained.
        let image = try await MediaEngine.thumbnail(url: source, time: 0.75,
            maximumDimension: TrackingEngine.analysisMaximumDimension)
        XCTAssertLessThanOrEqual(image.width, TrackingEngine.analysisMaximumDimension)
        XCTAssertLessThanOrEqual(image.height, TrackingEngine.analysisMaximumDimension)
        let result = try FrameRenderer.render(image, project: project, time: 0.75, maximumDimension: 480)
        XCTAssertEqual(result.height, 480)
        XCTAssertEqual(Double(result.width) / Double(result.height), 9.0 / 16, accuracy: 0.005)
        XCTAssertEqual(try ExportPlan(project: project).size.height, 2160)
        XCTAssertEqual(metadata.size, project.metadata.size)
    }
}
