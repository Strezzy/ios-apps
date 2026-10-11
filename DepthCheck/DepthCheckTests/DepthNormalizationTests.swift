import CoreImage
import XCTest
@testable import DepthCheck

final class DepthNormalizationTests: XCTestCase {
    func testMetricDepthAndInverseDepthHaveCorrectNearDirection() throws {
        let values: [Float] = [1, 2, 4, 8]
        let metric = try DepthNormalization().normalize(values, isInverseDepth: false, luma: [], temporal: false)
        let inverse = try DepthNormalization().normalize(values, isInverseDepth: true, luma: [], temporal: false)
        XCTAssertGreaterThan(metric[0], metric[3], "A smaller DA3 distance must appear nearer.")
        XCTAssertLessThan(inverse[0], inverse[3], "A larger DA2 disparity must appear nearer.")
        XCTAssertTrue((metric + inverse).allSatisfy { $0.isFinite && (0...1).contains($0) })
    }

    func testFlatDepthStaysOnScreenPlaneAndInvalidInferenceFails() throws {
        let flat = try DepthNormalization().normalize([Float](repeating: 12, count: 100),
                                                     isInverseDepth: true, luma: [], temporal: false)
        XCTAssertEqual(flat, [Float](repeating: 0.5, count: 100))
        XCTAssertThrowsError(try DepthNormalization().normalize([.nan, .infinity],
                                                                isInverseDepth: true, luma: [], temporal: false))
        XCTAssertThrowsError(try DepthNormalization().normalize([0, -1, 0],
                                                                isInverseDepth: false, luma: [], temporal: false))
    }

    func testTemporalStabilityDoesNotBlendOldObjectSilhouettes() throws {
        let stabilizer = DepthNormalization()
        let first = (0..<100).map { Float($0) / 99 }
        let second = Array(first.reversed())
        _ = try stabilizer.normalize(first, isInverseDepth: true, luma: [0.5, 0.5], temporal: true)
        let moving = try stabilizer.normalize(second, isInverseDepth: true, luma: [0.5, 0.5], temporal: true)
        let independent = try DepthNormalization().normalize(second, isInverseDepth: true, luma: [], temporal: false)
        for index in moving.indices { XCTAssertEqual(moving[index], independent[index], accuracy: 0.000_001) }
    }

    func testSceneCutResetsNormalizationInsteadOfCarryingPreviousScene() throws {
        let stabilizer = DepthNormalization()
        let first = (0..<100).map { Float($0) / 99 }
        let second = first.map { $0 + 0.25 }
        _ = try stabilizer.normalize(first, isInverseDepth: true, luma: [0, 0, 0], temporal: true)
        let cut = try stabilizer.normalize(second, isInverseDepth: true, luma: [1, 1, 1], temporal: true)
        let independent = try DepthNormalization().normalize(second, isInverseDepth: true, luma: [], temporal: false)
        for index in cut.indices { XCTAssertEqual(cut[index], independent[index], accuracy: 0.000_001) }
    }

    func testBundledModelsRunAndKeepTheSourceAspectRatio() async throws {
        let background = CIImage(color: CIColor(red: 0.12, green: 0.24, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
        let foreground = CIImage(color: CIColor(red: 0.9, green: 0.6, blue: 0.3))
            .cropped(to: CGRect(x: 30, y: 4, width: 32, height: 52))
        let image = foreground.composited(over: background)
        for choice in DepthModelChoice.allCases {
            let estimator = try await DepthEstimator(choice: choice)
            let depth = try estimator.predict(image, temporal: false)
            XCTAssertGreaterThan(depth.width, 100)
            XCTAssertGreaterThan(depth.height, 100)
            XCTAssertEqual(depth.values.count, depth.width * depth.height)
            XCTAssertEqual(Double(depth.width) / Double(depth.height), 1.5, accuracy: 0.01)
            XCTAssertTrue(depth.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }
}
