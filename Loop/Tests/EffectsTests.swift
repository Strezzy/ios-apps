import XCTest
@testable import Loop

final class EffectsTests: XCTestCase {
    func testCatalogIsUniqueAndEveryCategoryHasEffects() {
        XCTAssertEqual(Set(EffectLibrary.presets.map(\.id)).count, EffectLibrary.presets.count)
        for category in EffectCategory.allCases { XCTAssertGreaterThan(EffectLibrary.inCategory(category).count, 0) }
    }
    func testStackIsBoundedAndReplacesOnlyTheChosenCategory() throws {
        var settings = EffectSettings()
        settings.select("noir", category: .looks)
        settings.select("cat", category: .face)
        settings.select("goldenHour", category: .looks)
        XCTAssertEqual(settings.activeLayers.count, 2)
        XCTAssertEqual(settings.layer(.face)?.preset, "cat")
        settings.bypass = true
        XCTAssertTrue(settings.activeLayers.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(EffectSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
    func testNewProjectsUseFullVideoAndOldProjectsRetainTheirTrim() throws {
        let metadata = VideoMetadata(name: "Clip", duration: 21.5, size: PixelSize(width: 1920, height: 1080), nominalFrameRate: 60, isHDR: false, byteCount: 100)
        var project = LoopProject(name: "Clip", sourceFilename: "source.mov", metadata: metadata)
        XCTAssertEqual(project.trimEnd, 21.5)
        project.trimEnd = 6
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        object.removeValue(forKey: "effects")
        let old = try JSONDecoder().decode(LoopProject.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(old.trimEnd, 6); XCTAssertNil(old.effects)
    }
    func testVideoFormatsAndAlignedSize() throws {
        XCTAssertTrue(AnimationFormat.mp4.isVideo); XCTAssertTrue(AnimationFormat.hevc.isVideo)
        XCTAssertEqual(AnimationFormat.hevc.fileExtension, "mp4")
        XCTAssertFalse(AnimationFormat.gif.isVideo)
        XCTAssertEqual(PixelSize(width: 1081, height: 1919).videoAligned, PixelSize(width: 1080, height: 1918))
    }
}
