import XCTest
import Foundation
@testable import Loop

final class TrackingPersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LoopTrackingPersistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    @MainActor func testCompletedCropIsSavedBeforeReturnAndCannotBeReplacedByPendingAutosave() async throws {
        let seeded = try seedProject()
        let store = LoopStore(rootURL: directory)
        var snapshot = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(snapshot.id, seeded.id)
        snapshot.name = "The current edit"
        store.saveEdited(snapshot) // This old snapshot is waiting on the 350 ms debounce.
        snapshot.crop.centerX = 0.45
        let tracking = completedTrack()
        let committed = try store.commitCropTracking(tracking, for: snapshot)

        // Success must mean durable data already exists, before a result preview starts.
        let immediate = try readProject(committed.id)
        XCTAssertEqual(immediate.crop.tracking, tracking)
        XCTAssertEqual(immediate.crop.centerX, 0.45)
        XCTAssertEqual(immediate.overlays, snapshot.overlays)
        XCTAssertEqual(store.projects.first?.crop.tracking, tracking)
        XCTAssertEqual(committed.id, seeded.id)

        // Let the old autosave's deadline elapse, then reopen a fresh store from disk.
        try await Task.sleep(for: .milliseconds(650))
        let reopened = LoopStore(rootURL: directory)
        let restored = try XCTUnwrap(reopened.projects.first)
        XCTAssertEqual(restored.crop.tracking, tracking)
        XCTAssertEqual(restored.name, "The current edit")
        XCTAssertEqual(restored.overlays, snapshot.overlays)
        XCTAssertEqual(restored.crop.centerX, 0.45)
    }

    @MainActor func testFailedTrackingSaveDoesNotPublishAnUnsavedCropInMemory() throws {
        _ = try seedProject()
        let store = LoopStore(rootURL: directory)
        let original = try XCTUnwrap(store.projects.first)
        let projectDirectory = store.projectDirectory(original.id)
        let saved = directory.appendingPathComponent("ProjectBeforeFailure", isDirectory: true)
        try FileManager.default.moveItem(at: projectDirectory, to: saved)
        try Data([0]).write(to: projectDirectory)
        // A file in place of the parent directory produces a deterministic write
        // error, without relying on disk capacity or simulator permission behavior.
        XCTAssertThrowsError(try store.commitCropTracking(completedTrack(), for: original))
        XCTAssertEqual(store.projects.first?.crop, original.crop)
        XCTAssertEqual(store.projects.first?.overlays, original.overlays)

        try FileManager.default.removeItem(at: projectDirectory)
        try FileManager.default.moveItem(at: saved, to: projectDirectory)
        let reopened = LoopStore(rootURL: directory)
        XCTAssertEqual(reopened.projects.first?.crop, original.crop)
        XCTAssertEqual(reopened.projects.first?.overlays, original.overlays)
    }

    @MainActor func testLargeTrackingPathIsPersistedCompletelyBeforeReopening() throws {
        _ = try seedProject()
        let store = LoopStore(rootURL: directory)
        var project = try XCTUnwrap(store.projects.first)
        project.metadata.duration = 120
        project.trimEnd = 120
        var tracking = completedTrack()
        tracking.keyframes = (0...3600).map { index in
            let time = Double(index) / 30
            return TrackingKeyframe(time: time, rect: NormalizedRect(
                x: 0.2 + time / 120 * 0.5, y: 0.3, width: 0.15, height: 0.4))
        }
        tracking.subjectRect = tracking.keyframes[0].rect
        let committed = try store.commitCropTracking(tracking, for: project)
        let saved = try readProject(committed.id)
        XCTAssertEqual(saved.crop.tracking?.keyframes.count, 3601)
        XCTAssertEqual(saved.crop.tracking, tracking)
        let reopened = LoopStore(rootURL: directory)
        XCTAssertEqual(reopened.projects.first?.crop.tracking, tracking)
    }

    @MainActor func testCancellationDuringPreviewSuspensionNeverStartsAnalysisOrChangesSavedProject() async throws {
        _ = try seedProject()
        let store = LoopStore(rootURL: directory)
        let original = try XCTUnwrap(store.projects.first)
        var draft = original
        var selection = completedTrack()
        selection.enabled = false; selection.keyframes = []
        draft.crop.tracking = selection
        do {
            _ = try await store.trackCrop(project: draft, anchorTime: 0, beforeAnalysis: {
                XCTAssertNotNil(store.trackingProgress)
                store.cancelTracking()
                await Task.yield()
            })
            XCTFail("Canceling while the preview suspends must stop tracking.")
        } catch LoopError.cancelled {
            // The dummy source is deliberately unreadable. Reaching AVFoundation
            // instead would produce a decoding error, proving cancellation was late.
        } catch {
            XCTFail("Expected cancellation before decoding, received: \(error)")
        }
        XCTAssertNil(store.trackingProgress)
        XCTAssertEqual(store.projects.first, original)
        let saved = try readProject(original.id)
        XCTAssertEqual(saved, original)
    }

    @MainActor private func seedProject() throws -> LoopProject {
        let store = LoopStore(rootURL: directory)
        var project = LoopProject(name: "4K saved project", sourceFilename: "source.mov", metadata:
            VideoMetadata(name: "4K", duration: 2, size: PixelSize(width: 3840, height: 2160),
                          nominalFrameRate: 60, isHDR: false, byteCount: 1))
        project.trimEnd = 2
        project.crop.aspect = .portrait
        var overlay = OverlayItem(kind: .pixelate, startTime: 0, endTime: 2)
        overlay.trackingEnabled = true
        overlay.keyframes = [
            TrackingKeyframe(time: 0, rect: .init(x: 0.3, y: 0.3, width: 0.15, height: 0.3)),
            TrackingKeyframe(time: 2, rect: .init(x: 0.6, y: 0.3, width: 0.15, height: 0.3))
        ]
        project.overlays = [overlay]
        try FileManager.default.createDirectory(at: store.projectDirectory(project.id), withIntermediateDirectories: true)
        // Persistence tests only need a source file identity. Native decoding and
        // tracking are exercised separately using the actual 4K60 fixture.
        try Data([0]).write(to: store.sourceURL(project))
        store.flush(project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.projectDirectory(project.id).appendingPathComponent("project.json").path))
        return project
    }

    private func completedTrack() -> CropTrackingSettings {
        let first = NormalizedRect(x: 0.3, y: 0.25, width: 0.18, height: 0.45)
        return CropTrackingSettings(enabled: true, subjectRect: first, anchorTime: 0,
            keyframes: [TrackingKeyframe(time: 0, rect: first),
                        TrackingKeyframe(time: 1, rect: .init(x: 0.45, y: 0.25, width: 0.18, height: 0.45)),
                        TrackingKeyframe(time: 2, rect: .init(x: 0.6, y: 0.25, width: 0.18, height: 0.45))])
    }

    private func readProject(_ id: UUID) throws -> LoopProject {
        let url = directory.appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("project.json")
        return try JSONDecoder().decode(LoopProject.self, from: Data(contentsOf: url))
    }
}
