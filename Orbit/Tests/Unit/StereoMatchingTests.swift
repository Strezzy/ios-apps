import XCTest
import Metal
@testable import Orbit

final class StereoMatchingTests: XCTestCase {
    /// Known camera displacement checks direction and scale of the actual GPU matcher.
    /// This catches a depth inversion even when shader compilation succeeds.
    func testRecordedStereoShiftProducesCorrectDepth() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("This runtime does not provide a Metal device for the stereo-depth check.")
        }
        let library = try device.makeDefaultLibrary(bundle: Bundle(for: SpatialPlaybackController.self))
        let censusFunction = try XCTUnwrap(library.makeFunction(name: "orbitCensus"))
        let matchFunction = try XCTUnwrap(library.makeFunction(name: "orbitCoarseMatch"))
        let census = try device.makeComputePipelineState(function: censusFunction)
        let match = try device.makeComputePipelineState(function: matchFunction)
        let width = 96, height = 64, shift = 6
        func texture(_ format: MTLPixelFormat) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                       height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        }
        let left = try texture(.r32Float), right = try texture(.r32Float)
        let leftCensus = try texture(.r32Uint), rightCensus = try texture(.r32Uint)
        let output = try texture(.rg32Float)
        var pixels = [Float](repeating: 0, count: width * height)
        var state: UInt32 = 0x31415926
        for index in pixels.indices {
            state = state &* 1664525 &+ 1013904223
            pixels[index] = Float(state & 65535) / 65535
        }
        var rightPixels = pixels
        for y in 0..<height { for x in 0..<width {
            rightPixels[y * width + x] = pixels[y * width + min(width - 1, x + shift)]
        } }
        let region = MTLRegionMake2D(0, 0, width, height)
        pixels.withUnsafeBytes { left.replace(region: region, mipmapLevel: 0,
                                              withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        rightPixels.withUnsafeBytes { right.replace(region: region, mipmapLevel: 0,
                                                    withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState) {
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: pipeline.threadExecutionWidth,
                                                                   height: 4, depth: 1))
        }
        for (source, destination) in [(left, leftCensus), (right, rightCensus)] {
            let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
            encoder.setComputePipelineState(census)
            encoder.setTexture(source, index: 0); encoder.setTexture(destination, index: 1)
            dispatch(encoder, census)
            encoder.endEncoding()
        }
        let encoder = try XCTUnwrap(command.makeComputeCommandEncoder())
        encoder.setComputePipelineState(match)
        encoder.setTexture(leftCensus, index: 0); encoder.setTexture(rightCensus, index: 1)
        encoder.setTexture(output, index: 2)
        var parameters = SIMD4<Int32>(Int32(width), Int32(height), 12, 0)
        encoder.setBytes(&parameters, length: 16, index: 0)
        dispatch(encoder, match)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed, command.error?.localizedDescription ?? "GPU check failed")
        var values = [Float](repeating: 0, count: width * height * 2)
        values.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 8,
                                                        from: region, mipmapLevel: 0) }
        var good = 0, total = 0
        for y in 8..<(height - 8) { for x in 20..<(width - 12) {
            let measured = values[(y * width + x) * 2] * Float(width)
            if abs(measured - Float(shift)) < 0.6 { good += 1 }
            total += 1
        } }
        XCTAssertGreaterThan(Double(good) / Double(total), 0.98,
                             "Stereo matching must recover the recorded left-to-right baseline without depth inversion.")
    }
}
