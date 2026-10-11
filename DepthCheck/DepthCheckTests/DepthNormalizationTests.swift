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

    func testAffinePredictionGaugeDoesNotMoveStereoDepth() throws {
        let base = scene()
        let luma = texture()
        let reference = try independent(base)
        let stabilizer = DepthNormalization()
        let gauges: [(Float, Float)] = [(1, 0), (1.6, 0.35), (0.72, -0.1), (1.02, 0.4), (2.2, -0.08)]
        for (scale, shift) in gauges {
            let prediction = base.map { $0 * scale + shift }
            let actual = try stabilizer.normalize(prediction, isInverseDepth: true, luma: luma,
                                                   temporal: true, width: 32, height: 24)
            assertSame(actual, reference)
            let maximumDepthChange = zip(actual, reference).map { abs($0 - $1) }.max() ?? .infinity
            let maximumEyeShift = maximumDepthChange * 3_840 * 0.027 * 0.5
            XCTAssertLessThan(maximumEyeShift, 0.001,
                              "An arbitrary model scale/offset must not make the same 4K scene wobble.")
        }

        // DA3 emits distance. Changing its arbitrary positive metric scale must
        // also cancel after inversion, before any history enters the pipeline.
        let metricStabilizer = DepthNormalization()
        for scale in [Float(1), 0.7, 1.8, 0.35, 2.1] {
            let distance = base.map { scale / $0 }
            let actual = try metricStabilizer.normalize(distance, isInverseDepth: false, luma: luma,
                                                         temporal: true, width: 32, height: 24)
            assertSame(actual, reference)
        }
    }

    func testStaticInteriorFlickerIsReducedWithoutFreezingRealDepthChanges() throws {
        let stabilizer = DepthNormalization()
        let luma = texture()
        _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: luma,
                                       temporal: true, width: 32, height: 24)
        let center = 12 * 32 + 16
        var filtered = [Float]()
        var original = [Float]()
        for frame in 0..<30 {
            let prediction = scene(offset: frame.isMultiple(of: 2) ? 0.012 : -0.012)
            let current = try independent(prediction)
            let actual = try stabilizer.normalize(prediction, isInverseDepth: true, luma: luma,
                                                   temporal: true, width: 32, height: 24)
            filtered.append(actual[center])
            original.append(current[center])
            XCTAssertLessThanOrEqual(abs(actual[center] - current[center]), 0.012_001)
        }
        let originalRange = original.max()! - original.min()!
        let filteredRange = filtered.max()! - filtered.min()!
        XCTAssertLessThan(filteredRange, originalRange * 0.8,
                          "The temporal option must actually reduce small static-region depth flicker.")
        XCTAssertGreaterThan(filteredRange, originalRange * 0.2,
                             "Static filtering must not freeze the depth map.")

        let changed = scene(offset: 0.15)
        let actual = try stabilizer.normalize(changed, isInverseDepth: true, luma: luma,
                                               temporal: true, width: 32, height: 24)
        XCTAssertEqual(actual[center], try independent(changed)[center], accuracy: 0.000_001,
                       "A real depth innovation must use the current prediction, even with unchanged luma.")
    }

    func testTemporalStabilityDoesNotBlendOldObjectSilhouettes() throws {
        let stabilizer = DepthNormalization()
        let luma = texture()
        func movingEdge(at edge: Int) -> [Float] {
            (0..<(32 * 24)).map { index in
                let x = index % 32
                if x < 3 { return 0.1 }
                if x >= 29 { return 0.9 }
                return x >= edge ? 0.54 : 0.5
            }
        }
        _ = try stabilizer.normalize(movingEdge(at: 16), isInverseDepth: true, luma: luma,
                                       temporal: true, width: 32, height: 24)
        let current = movingEdge(at: 18)
        let actual = try stabilizer.normalize(current, isInverseDepth: true, luma: luma,
                                               temporal: true, width: 32, height: 24)
        // Even adversarially identical image samples must not carry a previous
        // depth edge into the two newly exposed columns. The change is smaller
        // than the large-innovation cutoff, exercising edge rejection itself.
        assertSame(actual, try independent(current))
    }

    func testLocalImageMotionAndUntexturedRegionsUseCurrentDepth() throws {
        let luma = texture()
        var movingLuma = luma
        for y in 7...17 {
            for x in 9...22 { movingLuma[y * 32 + x] = 1 - luma[y * 32 + x] }
        }
        for (firstLuma, currentLuma) in [(luma, movingLuma),
                                       ([Float](repeating: 0.5, count: luma.count),
                                        [Float](repeating: 0.5, count: luma.count))] {
            let stabilizer = DepthNormalization()
            _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: firstLuma,
                                           temporal: true, width: 32, height: 24)
            let current = scene(offset: 0.012)
            let actual = try stabilizer.normalize(current, isInverseDepth: true, luma: currentLuma,
                                                   temporal: true, width: 32, height: 24)
            assertSame(actual, try independent(current))
        }
    }

    func testSceneCutResetsNormalizationInsteadOfCarryingPreviousScene() throws {
        let stabilizer = DepthNormalization()
        let firstLuma = texture().map { $0 * 0.2 }
        let secondLuma = firstLuma.map { $0 + 0.8 }
        _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: firstLuma,
                                       temporal: true, width: 32, height: 24)
        let current = scene(offset: 0.012)
        let actual = try stabilizer.normalize(current, isInverseDepth: true, luma: secondLuma,
                                               temporal: true, width: 32, height: 24)
        assertSame(actual, try independent(current))
    }

    func testResetFlatInvalidAndDisabledInputsDiscardTemporalHistory() throws {
        let luma = texture()
        let current = scene(offset: 0.012)
        let reference = try independent(current)
        for resetKind in 0..<6 {
            let stabilizer = DepthNormalization()
            _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: luma,
                                           temporal: true, width: 32, height: 24)
            switch resetKind {
            case 0:
                stabilizer.reset()
            case 1:
                _ = try stabilizer.normalize([Float](repeating: 0.5, count: luma.count), isInverseDepth: true,
                                               luma: luma, temporal: true, width: 32, height: 24)
            case 2:
                XCTAssertThrowsError(try stabilizer.normalize([Float](repeating: .nan, count: luma.count),
                                                               isInverseDepth: true, luma: luma,
                                                               temporal: true, width: 32, height: 24))
            case 3:
                _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: luma,
                                               temporal: false, width: 32, height: 24)
            case 4:
                _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: [0.5],
                                               temporal: true, width: 32, height: 24)
            default:
                XCTAssertThrowsError(try stabilizer.normalize([], isInverseDepth: true, luma: [], temporal: true))
            }
            let actual = try stabilizer.normalize(current, isInverseDepth: true, luma: luma,
                                                   temporal: true, width: 32, height: 24)
            assertSame(actual, reference)
        }
    }

    func testChangedDimensionsDiscardHistoryEvenWhenPixelCountMatches() throws {
        let stabilizer = DepthNormalization()
        let luma = texture()
        _ = try stabilizer.normalize(scene(), isInverseDepth: true, luma: luma,
                                       temporal: true, width: 32, height: 24)
        let current = scene(offset: 0.012)
        let actual = try stabilizer.normalize(current, isInverseDepth: true, luma: luma,
                                               temporal: true, width: 24, height: 32)
        assertSame(actual, try independent(current))
    }

    private func scene(offset: Float = 0) -> [Float] {
        (0..<(32 * 24)).map { index in
            let x = index % 32
            let y = index / 32
            if x < 3 { return 0.1 }
            if x >= 29 { return 0.9 }
            return (10...21).contains(x) && (8...15).contains(y) ? 0.5 + offset : 0.5
        }
    }

    private func texture() -> [Float] {
        (0..<(32 * 24)).map { (($0 % 32) + ($0 / 32)).isMultiple(of: 2) ? 0.25 : 0.75 }
    }

    private func independent(_ values: [Float]) throws -> [Float] {
        try DepthNormalization().normalize(values, isInverseDepth: true, luma: [], temporal: false)
    }

    private func assertSame(_ actual: [Float], _ expected: [Float],
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        let maximumDifference = zip(actual, expected).map { abs($0 - $1) }.max() ?? .infinity
        XCTAssertLessThanOrEqual(maximumDifference, 0.000_01, file: file, line: line)
    }

    func testBundledModelsRunAndKeepTheSourceAspectRatio() async throws {
        let background = CIImage(color: CIColor(red: 0.12, green: 0.24, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 96, height: 64))
        let foreground = CIImage(color: CIColor(red: 0.9, green: 0.6, blue: 0.3))
            .cropped(to: CGRect(x: 30, y: 4, width: 32, height: 52))
        let image = foreground.composited(over: background)
        for choice in DepthModelChoice.allCases {
            let estimator = try await DepthEstimator(choice: choice)
            let depth = try estimator.predict(image, temporal: true)
            XCTAssertGreaterThan(depth.width, 100)
            XCTAssertGreaterThan(depth.height, 100)
            XCTAssertEqual(depth.values.count, depth.width * depth.height)
            XCTAssertEqual(Double(depth.width) / Double(depth.height), 1.5, accuracy: 0.01)
            XCTAssertTrue(depth.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
            XCTAssertGreaterThan((depth.values.max() ?? 0) - (depth.values.min() ?? 0), 0.01,
                                 "The bundled model must return non-flat depth for this two-layer image.")
            let repeated = try estimator.predict(image, temporal: true)
            XCTAssertEqual(repeated.width, depth.width)
            XCTAssertEqual(repeated.height, depth.height)
            XCTAssertEqual(repeated.values.count, depth.values.count)
            XCTAssertTrue(repeated.values.allSatisfy { $0.isFinite && (0...1).contains($0) })
            let maximumChange = zip(repeated.values, depth.values).map { abs($0 - $1) }.max() ?? .infinity
            XCTAssertLessThan(maximumChange, 0.002,
                              "Repeating the identical image must remain stable through full-crop luma and temporal filtering.")
        }
    }
}
