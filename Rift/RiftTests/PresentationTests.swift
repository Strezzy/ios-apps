import XCTest
import SwiftUI
import UIKit
@testable import Rift

final class PresentationTests: XCTestCase {
    func testKeyboardResizeDoesNotTurnOffFollowing() {
        var state = ChatFollowingState()
        let old = ChatViewport(height: 650, contentHeight: 1200, bottomDistance: 0)
        let keyboard = ChatViewport(height: 320, contentHeight: 1200, bottomDistance: 330)
        XCTAssertTrue(state.observe(old: old, new: keyboard))
        XCTAssertTrue(state.followsLatest)
    }
    func testOnlyUserScrollingCanLeaveLatestReply() {
        var state = ChatFollowingState()
        let bottom = ChatViewport(height: 320, contentHeight: 1200, bottomDistance: 0)
        let earlier = ChatViewport(height: 320, contentHeight: 1200, bottomDistance: 300)
        state.interaction(true, viewport: bottom)
        XCTAssertFalse(state.observe(old: bottom, new: earlier))
        state.interaction(false, viewport: earlier)
        XCTAssertFalse(state.followsLatest)
        XCTAssertFalse(state.observe(old: earlier, new: .init(height: 600, contentHeight: 1210, bottomDistance: 30)))
        state.followLatest()
        XCTAssertTrue(state.followsLatest)
        XCTAssertFalse(state.userScrolling)
    }
    func testWrappingIncomingTextRequestsBottomAlignment() {
        var state = ChatFollowingState()
        XCTAssertTrue(state.observe(old: .init(height: 300, contentHeight: 800, bottomDistance: 0), new: .init(height: 300, contentHeight: 870, bottomDistance: 70)))
        XCTAssertTrue(state.followsLatest)
    }
    func testProgrammaticScrollDoesNotCreateAnEndlessRequestLoop() {
        var state = ChatFollowingState()
        XCTAssertFalse(state.observe(old: .init(height: 300, contentHeight: 800, bottomDistance: 80), new: .init(height: 300, contentHeight: 800, bottomDistance: 0)))
    }
    func testMemoryRemainingIsNotTotalProcessBudget() {
        let snapshot = AppMemorySnapshot(remaining: 3_000_000_000, footprint: 2_500_000_000)
        XCTAssertEqual(snapshot.estimatedBudget, 5_500_000_000)
        XCTAssertNil(AppMemorySnapshot(remaining: 0, footprint: 1).estimatedBudget)
        XCTAssertNil(AppMemorySnapshot(remaining: UInt64.max, footprint: 1).estimatedBudget)
    }
    func testRetiredOfflinePreferenceCannotBlockDownloads() throws {
        let name = "Rift-Privacy-Test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "rift.offline")
        defaults.set(false, forKey: "rift.cellular")
        PrivacyPreferences.migrate(defaults)
        XCTAssertNil(defaults.object(forKey: "rift.offline"))
        XCTAssertEqual(defaults.object(forKey: "rift.cellular") as? Bool, false)
    }
    func testEffectsAreDifferentAndSettleToIdenticalText() {
        let bloom = ReplyGlyphFrame.at(age: 0.03, style: .bloom)
        let fade = ReplyGlyphFrame.at(age: 0.03, style: .fade)
        XCTAssertNotEqual(bloom, fade)
        XCTAssertEqual(fade.scale, 1)
        XCTAssertEqual(fade.blur, 0)
        XCTAssertGreaterThan(bloom.blur, 0)
        XCTAssertEqual(ReplyGlyphFrame.at(age: 1, style: .bloom), ReplyGlyphFrame.at(age: 1, style: .instant))
        XCTAssertEqual(ReplyGlyphFrame.at(age: -1, style: .fade).opacity, 0)
    }
    func testAccessibilityFallbacksAndUnknownPreference() {
        XCTAssertEqual(ReplyAnimationStyle.resolved("unknown"), .ember)
        XCTAssertEqual(ReplyAnimationStyle.bloom.effective(reduceMotion: true, lowPower: false, voiceOver: false), .fade)
        XCTAssertEqual(ReplyAnimationStyle.bloom.effective(reduceMotion: false, lowPower: true, voiceOver: false), .fade)
        XCTAssertEqual(ReplyAnimationStyle.fade.effective(reduceMotion: false, lowPower: false, voiceOver: true), .instant)
    }
    @MainActor func testProductionRendererChangesPixelsNotJustAccessibilityLabels() throws {
        var schedule = RevealSchedule()
        let rich = AttributedString("Bloom flows softly")
        schedule.ingest(String(rich.characters), now: 100, animate: true)
        let text = ReplyTextComposition.make(rich, arrivals: schedule.arrivals)
        let before = try render(text, time: 99, style: .bloom)
        let bloom = try render(text, time: 100.07, style: .bloom)
        let fade = try render(text, time: 100.07, style: .fade)
        let complete = try render(text, time: 101, style: .bloom)
        let instant = try render(text, time: 100.07, style: .instant)
        XCTAssertEqual(before.ink, 0, "Future glyphs must actually be invisible")
        XCTAssertGreaterThan(bloom.ink, 0, "Bloom must draw visible intermediate glyphs")
        XCTAssertGreaterThan(complete.ink, bloom.ink)
        XCTAssertNotEqual(bloom.pixels, fade.pixels, "Bloom and Soft fade must visibly differ")
        XCTAssertEqual(complete.pixels, instant.pixels, "Settled text must match Instant")
    }
    @MainActor func testExpressiveStylesActuallyChangeRenderedPixels() throws {
        var schedule = RevealSchedule()
        let rich = AttributedString("Stars ripple softly")
        schedule.ingest(String(rich.characters), now: 100, animate: true)
        let text = ReplyTextComposition.make(rich, arrivals: schedule.arrivals)
        let instant = try render(text, time: 100.12, style: .instant)
        var snapshots = Set<Data>()
        for style in [ReplyAnimationStyle.starlight, .wave, .bounce, .ember, .portal, .cipher] {
            let intermediate = try render(text, time: 100.12, style: style)
            let final = try render(text, time: 102, style: style)
            XCTAssertGreaterThan(intermediate.ink, 0)
            XCTAssertNotEqual(intermediate.pixels, instant.pixels)
            XCTAssertEqual(final.pixels, instant.pixels)
            snapshots.insert(intermediate.pixels)
        }
        XCTAssertEqual(snapshots.count, 6)
    }
    @MainActor private func render(_ text: Text, time: Double, style: ReplyAnimationStyle) throws -> (pixels: Data, ink: Int) {
        let view = ReplyRenderSurface(text: text, now: time, style: style)
            .font(.system(size: 24)).foregroundStyle(.black).padding(12)
            .frame(width: 320, height: 100, alignment: .topLeading).background(.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view); renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let cg = try XCTUnwrap(image.cgImage)
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var ink = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            ink += 765 - red - green - blue
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Rift-render-\(style.rawValue)-\(time)"; attachment.lifetime = .keepAlways; add(attachment)
        return (Data(pixels), ink)
    }
}
