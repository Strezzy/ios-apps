import XCTest
import Metal
@testable import Rift

final class HistoryDissolveTests: XCTestCase {
    func testParticleShaderIsIncludedInTheAppLibrary() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try device.makeDefaultLibrary(bundle: Bundle.main)
        XCTAssertNotNil(library.makeFunction(name: "historyDissolve"), "The shipping message effect must have a compiled Metal function")
    }
}
