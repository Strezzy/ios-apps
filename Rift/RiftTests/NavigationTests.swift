import XCTest
@testable import Rift

final class NavigationTests: XCTestCase {
    func testDrawerDragClampsAndSettlesInBothDirections() {
        XCTAssertEqual(DrawerMotion.progress(open: false, translation: 150, width: 300), 0.5)
        XCTAssertEqual(DrawerMotion.progress(open: false, translation: -50, width: 300), 0)
        XCTAssertEqual(DrawerMotion.progress(open: true, translation: 50, width: 300), 1)
        XCTAssertEqual(DrawerMotion.progress(open: true, translation: -75, width: 300), 0.75)
        XCTAssertFalse(DrawerMotion.shouldOpen(open: false, projected: 100, width: 300))
        XCTAssertTrue(DrawerMotion.shouldOpen(open: false, projected: 220, width: 300))
        XCTAssertTrue(DrawerMotion.shouldOpen(open: true, projected: -80, width: 300))
        XCTAssertFalse(DrawerMotion.shouldOpen(open: true, projected: -220, width: 300))
    }
    func testComposerMorphPreservesCloseAndStopPriority() {
        XCTAssertEqual(ComposerAction.resolve(draft: " \n", voice: false, generating: false), .voice)
        XCTAssertEqual(ComposerAction.resolve(draft: "Hey", voice: false, generating: false), .send)
        XCTAssertEqual(ComposerAction.resolve(draft: "", voice: false, generating: true), .stop)
        XCTAssertEqual(ComposerAction.resolve(draft: "Next", voice: false, generating: true), .stop)
        XCTAssertEqual(ComposerAction.resolve(draft: "", voice: true, generating: true), .close)
        XCTAssertEqual(ComposerAction.resolve(draft: "", voice: true, generating: false), .close)
        XCTAssertEqual(ComposerAction.resolve(draft: "", voice: false, generating: false), .voice)
    }
}
