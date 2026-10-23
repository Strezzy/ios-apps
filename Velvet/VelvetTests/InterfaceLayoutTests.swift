import SwiftUI
import UIKit
import Vision
import XCTest
@testable import Velvet

/// Synthetic empty-state render checks. These mount the production screens with
/// a locked, empty VaultStore; they never authenticate, inject media, open the
/// camera, or weaken the production lock screen. Viewport renders complement,
/// but do not replace, physical-device rotation and accessibility testing.
@MainActor
final class InterfaceLayoutTests: XCTestCase {
    private let compact = CGSize(width: 320, height: 568)
    private let standard = CGSize(width: 393, height: 852)
    private let landscape = CGSize(width: 852, height: 393)

    func testPhotoViewfinderPreservesAspectAndSpaceForControls() {
        for size in [compact, standard, CGSize(width: 430, height: 932), landscape] {
            let frame = CameraViewfinderLayout.frame(in: size, video: false)
            XCTAssertEqual(frame.width / frame.height, 3.0 / 4.0, accuracy: 0.0001)
            XCTAssertEqual(frame.midX, size.width / 2, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.01)
            XCTAssertEqual(frame.minY, CameraViewfinderLayout.topBarHeight)
            XCTAssertLessThanOrEqual(frame.maxY, size.height - CameraViewfinderLayout.photoControlsHeight + 0.01)
        }
    }

    func testVideoViewfinderPreservesFullFrameWithinViewport() {
        for size in [compact, standard, CGSize(width: 430, height: 932), landscape] {
            let frame = CameraViewfinderLayout.frame(in: size, video: true)
            XCTAssertEqual(frame.width / frame.height, 9.0 / 16.0, accuracy: 0.0001)
            XCTAssertEqual(frame.midX, size.width / 2, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, size.width + 0.01)
            XCTAssertEqual(frame.minY, CameraViewfinderLayout.topBarHeight)
            XCTAssertLessThanOrEqual(frame.maxY, size.height + 0.01)
        }
    }

    func testPhotosCompactPortraitEmptyState() async throws {
        let snapshot = try await render(name: "photos-compact-320x568", size: compact) { _ in GalleryScreen() }
        assertPhotoNavigation(in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testPhotosStandardPortraitEmptyState() async throws {
        let snapshot = try await render(name: "photos-portrait-393x852", size: standard) { _ in GalleryScreen() }
        assertPhotoNavigation(in: snapshot)
        assertVisible("No Photos or Videos", in: snapshot)
        assertVisible("Import Photos", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testPhotosAccessibilityTextSizeKeepsSearchAndBottomNavigationVisible() async throws {
        let snapshot = try await render(name: "photos-accessibility-320x568", size: compact, textSize: .accessibility2) { _ in GalleryScreen() }
        // The empty-state explanation may scroll below the viewport. Search and
        // library navigation must remain usable without requiring smaller text.
        assertPhotoNavigation(in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testPhotosLandscapeViewportHasNoHorizontalOverflow() async throws {
        let snapshot = try await render(name: "photos-landscape-852x393", size: landscape) { _ in GalleryScreen() }
        assertVisible("Photos", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testSearchCompactPortraitSuggestions() async throws {
        let snapshot = try await render(name: "search-compact-320x568", size: compact) { _ in SearchScreen() }
        assertVisible("Search", in: snapshot)
        assertVisible("Suggestions", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testSearchLandscapeViewportHasNoHorizontalOverflow() async throws {
        let snapshot = try await render(name: "search-landscape-852x393", size: landscape) { _ in SearchScreen() }
        assertVisible("Search", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testSearchAccessibilityTextSizeRemainsScrollable() async throws {
        let snapshot = try await render(name: "search-accessibility-320x568", size: compact, textSize: .accessibility2) { _ in SearchScreen() }
        assertVisible("Search", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testCameraCompactPortraitChromeWithoutCapture() async throws {
        let snapshot = try await render(name: "camera-photo-compact-320x568", size: compact) { model in
            CameraScreen(controller: model.camera, startsCaptureSession: false)
        }
        assertVisible("PHOTO", in: snapshot)
        assertVisible("VIDEO", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    func testCameraStandardPortraitChromeWithoutCapture() async throws {
        let snapshot = try await render(name: "camera-photo-portrait-393x852", size: standard) { model in
            CameraScreen(controller: model.camera, startsCaptureSession: false)
        }
        assertVisible("PHOTO", in: snapshot)
        assertVisible("VIDEO", in: snapshot)
        assertNoRetiredCopy(in: snapshot)
    }

    private struct RenderedSnapshot {
        let recognizedText: String
        let accessibilityText: String
        let textRegions: [TextRegion]
    }

    private struct TextRegion {
        let text: String
        /// Normalized screenshot coordinates, with the origin at the top left.
        let bounds: CGRect
    }

    private func render<Content: View>(name: String, size: CGSize, textSize: DynamicTypeSize = .large,
                                      @ViewBuilder content: (AppModel) -> Content) async throws -> RenderedSnapshot {
        let model = AppModel()
        XCTAssertFalse(model.vault.isUnlocked)
        XCTAssertTrue(model.vault.items.isEmpty)
        let root = content(model)
            .environmentObject(model)
            .environmentObject(model.vault)
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.locale, Locale(identifier: "en_US"))
            .preferredColorScheme(.dark)
            .tint(VelvetTheme.accent)
        let controller = UIHostingController(rootView: root)
        controller.overrideUserInterfaceStyle = .dark
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = controller
        window.backgroundColor = .black
        window.makeKeyAndVisible()
        defer {
            model.camera.stop()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        // Give SwiftUI's actual NavigationStack and task-driven initial state a
        // render turn; this does not wait for media or model inference.
        try await Task.sleep(for: .milliseconds(250))
        window.frame = CGRect(origin: .zero, size: size)
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(controller.view.bounds.width, size.width, accuracy: 0.5)
        XCTAssertEqual(controller.view.bounds.height, size.height, accuracy: 0.5)
        assertVerticalContentFitsHorizontally(controller.view, viewportWidth: size.width)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        var rendered = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            rendered = controller.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "UIKit could not render \(name)")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UITestSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)

        let cgImage = try XCTUnwrap(image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let textRegions = (request.results ?? []).compactMap { observation -> TextRegion? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return TextRegion(text: text, bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
        let recognizedText = textRegions.map(\.text).joined(separator: "\n")
        let accessibilityText = labels(in: controller.view).joined(separator: "\n")
        try ("RENDERED TEXT\n" + recognizedText + "\n\nUIKIT ACCESSIBILITY\n" + accessibilityText)
            .write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        XCTAssertFalse(recognizedText.isEmpty, "Snapshot must contain visible, legible interface text")
        XCTAssertFalse(model.vault.isUnlocked, "Rendering must not unlock the vault")
        XCTAssertTrue(model.vault.items.isEmpty, "Synthetic screenshots must contain no private media")
        XCTAssertFalse(model.camera.isReady, "Layout tests must not start a capture session")
        return RenderedSnapshot(recognizedText: recognizedText, accessibilityText: accessibilityText, textRegions: textRegions)
    }

    private func assertPhotoNavigation(in snapshot: RenderedSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        assertVisible("Photos", in: snapshot, file: file, line: line)
        assertVisible("Search", in: snapshot, file: file, line: line)
        assertVisible("Library", in: snapshot, file: file, line: line)
        assertVisible("Albums", in: snapshot, file: file, line: line)
        if let search = snapshot.textRegions.first(where: { normalized($0.text).contains("search") }) {
            XCTAssertLessThan(search.bounds.midY, 0.55, "Search should remain near the top of Photos", file: file, line: line)
        }
        for label in ["library", "albums"] {
            if let tab = snapshot.textRegions.first(where: { normalized($0.text).contains(label) }) {
                XCTAssertGreaterThan(tab.bounds.midY, 0.65, "\(label) should remain in the bottom navigation", file: file, line: line)
                XCTAssertLessThanOrEqual(tab.bounds.maxY, 1, "Bottom navigation must fit in the viewport", file: file, line: line)
            }
        }
    }

    private func assertVisible(_ text: String, in snapshot: RenderedSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        let recognized = normalized(snapshot.recognizedText)
        XCTAssertTrue(recognized.contains(normalized(text)), "Missing visible text ‘\(text)’ in screenshot: \(snapshot.recognizedText)", file: file, line: line)
    }

    private func assertNoRetiredCopy(in snapshot: RenderedSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        let text = normalized(snapshot.recognizedText + " " + snapshot.accessibilityText)
        for retired in ["only yours", "find the feeling", "a little more private", "describe a moment",
                        "encrypted on this iphone", "room for your memories", "no cloud inference"] {
            XCTAssertFalse(text.contains(retired), "Retired slogan remains visible: \(retired)", file: file, line: line)
        }
    }

    private func normalized(_ value: String) -> String {
        value.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func labels(in view: UIView) -> [String] {
        guard !view.isHidden, view.alpha > 0.01 else { return [] }
        var result: [String] = []
        if let label = view.accessibilityLabel, !label.isEmpty { result.append(label) }
        if let label = view as? UILabel, let text = label.text { result.append(text) }
        if let button = view as? UIButton, let title = button.title(for: .normal) { result.append(title) }
        if let field = view as? UITextField, let placeholder = field.placeholder { result.append(placeholder) }
        if let bar = view as? UINavigationBar, let title = bar.topItem?.title { result.append(title) }
        for child in view.subviews { result += labels(in: child) }
        return result
    }

    private func assertVerticalContentFitsHorizontally(_ root: UIView, viewportWidth: CGFloat,
                                                      file: StaticString = #filePath, line: UInt = #line) {
        // Small horizontal chips are intentional. A screen-height vertical
        // scrolling surface must not accidentally become a two-axis canvas.
        if let scroll = root as? UIScrollView,
           scroll.bounds.height > 150, scroll.bounds.width > viewportWidth * 0.6 {
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                "Primary content overflows its horizontal viewport", file: file, line: line)
        }
        for child in root.subviews {
            assertVerticalContentFitsHorizontally(child, viewportWidth: viewportWidth, file: file, line: line)
        }
    }
}
