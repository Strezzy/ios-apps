import Foundation
import CoreImage
import CoreVideo
import Metal

struct StereoPair {
    let left: CVPixelBuffer
    let right: CVPixelBuffer
}

/// Serial, full-resolution stereo synthesis. Only depth inference is reduced;
/// the source image, eye buffers and packed export retain their original pixels.
final class StereoRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let context: CIContext
    private var cache: CVMetalTextureCache!
    private let splat: MTLComputePipelineState
    private let resolve: MTLComputePipelineState
    private let pack: MTLComputePipelineState
    private let depthDisplay: MTLComputePipelineState
    private var pools: [String: CVPixelBufferPool] = [:]
    private var leftKeys: MTLBuffer?
    private var rightKeys: MTLBuffer?
    private var keyLength = 0
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private struct Uniforms {
        var width: UInt32
        var height: UInt32
        var amount: Float
        var convergence: Float
    }

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw DepthCheckError.message("Metal is unavailable on this device.")
        }
        self.device = device
        self.queue = queue
        self.context = CIContext(mtlDevice: device, options: [
            .cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ])
        guard let library = device.makeDefaultLibrary() else {
            throw DepthCheckError.message("The stereo rendering shaders are missing from this build.")
        }
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw DepthCheckError.message("Missing stereo shader: \(name).")
            }
            return try device.makeComputePipelineState(function: function)
        }
        splat = try pipeline("depthCheckSplat")
        resolve = try pipeline("depthCheckResolve")
        pack = try pipeline("depthCheckPack")
        depthDisplay = try pipeline("depthCheckDepthDisplay")
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw DepthCheckError.message("Could not create the Metal image cache.")
        }
    }

    func render(source: CIImage, depth: DepthMap, options: ConversionOptions) throws -> StereoPair {
        let size = PixelSize(width: Int(source.extent.width.rounded()), height: Int(source.extent.height.rounded()))
        try validate(size)
        let input = try buffer(size)
        let normalized = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        context.render(normalized, to: input, bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height), colorSpace: colorSpace)
        let left = try buffer(size)
        let right = try buffer(size)
        let sourceTexture = try texture(input)
        let leftTexture = try texture(left)
        let rightTexture = try texture(right)
        let depthTexture = try makeDepthTexture(depth)
        let length = size.width * size.height * MemoryLayout<UInt32>.stride
        if keyLength != length {
            guard length <= device.maxBufferLength,
                  let l = device.makeBuffer(length: length, options: .storageModePrivate),
                  let r = device.makeBuffer(length: length, options: .storageModePrivate) else {
                throw DepthCheckError.message("This image exceeds the device's available stereo-rendering memory. The source was not resized.")
            }
            leftKeys = l; rightKeys = r; keyLength = length
        }
        guard let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() else {
            throw DepthCheckError.message("Could not begin stereo rendering.")
        }
        blit.fill(buffer: leftKeys!, range: 0..<length, value: 0)
        blit.fill(buffer: rightKeys!, range: 0..<length, value: 0)
        blit.endEncoding()
        var uniforms = Uniforms(width: UInt32(size.width), height: UInt32(size.height),
                                amount: Float(options.depthAmount), convergence: Float(options.convergence))
        guard let encoder = command.makeComputeCommandEncoder() else {
            throw DepthCheckError.message("Could not encode stereo rendering.")
        }
        encoder.setComputePipelineState(splat)
        encoder.setTexture(sourceTexture.texture, index: 0)
        encoder.setTexture(depthTexture, index: 1)
        encoder.setBuffer(leftKeys, offset: 0, index: 0)
        encoder.setBuffer(rightKeys, offset: 0, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)
        dispatch(encoder, pipeline: splat, size: size)
        encoder.endEncoding()
        for (keys, output, direction) in [(leftKeys!, leftTexture.texture, Float(1)), (rightKeys!, rightTexture.texture, Float(-1))] {
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw DepthCheckError.message("Could not resolve stereo rendering.")
            }
            var sign = direction
            encoder.setComputePipelineState(resolve)
            encoder.setTexture(sourceTexture.texture, index: 0)
            encoder.setTexture(depthTexture, index: 1)
            encoder.setTexture(output, index: 2)
            encoder.setBuffer(keys, offset: 0, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setBytes(&sign, length: MemoryLayout<Float>.stride, index: 2)
            dispatch(encoder, pipeline: resolve, size: size)
            encoder.endEncoding()
        }
        try finish(command)
        // These wrappers must remain alive until GPU completion.
        withExtendedLifetime([sourceTexture.reference, leftTexture.reference, rightTexture.reference]) {}
        return options.swapEyes ? StereoPair(left: right, right: left) : StereoPair(left: left, right: right)
    }

    func packed(pair: StereoPair, format: OutputFormat) throws -> CVPixelBuffer {
        let sourceSize = PixelSize(width: CVPixelBufferGetWidth(pair.left), height: CVPixelBufferGetHeight(pair.left))
        let size = format.outputSize(for: sourceSize)
        let output = try buffer(size)
        let left = try texture(pair.left), right = try texture(pair.right), destination = try texture(output)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw DepthCheckError.message("Could not compose the stereo export.")
        }
        var mode: UInt32 = format == .sideBySide ? 0 : (format == .overUnder ? 1 : 2)
        encoder.setComputePipelineState(pack)
        encoder.setTexture(left.texture, index: 0)
        encoder.setTexture(right.texture, index: 1)
        encoder.setTexture(destination.texture, index: 2)
        encoder.setBytes(&mode, length: MemoryLayout<UInt32>.stride, index: 0)
        dispatch(encoder, pipeline: pack, size: size)
        encoder.endEncoding()
        try finish(command)
        withExtendedLifetime([left.reference, right.reference, destination.reference]) {}
        return output
    }

    func depthPixelBuffer(depth: DepthMap, size: PixelSize) throws -> CVPixelBuffer {
        let output = try buffer(size)
        let destination = try texture(output)
        let source = try makeDepthTexture(depth)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw DepthCheckError.message("Could not render the depth image.")
        }
        encoder.setComputePipelineState(depthDisplay)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination.texture, index: 1)
        dispatch(encoder, pipeline: depthDisplay, size: size)
        encoder.endEncoding()
        try finish(command)
        withExtendedLifetime(destination.reference) {}
        return output
    }

    func cgImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let result = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw DepthCheckError.message("Could not create the full-resolution photo.")
        }
        return result
    }

    func purgeCaches() {
        context.clearCaches()
        CVMetalTextureCacheFlush(cache, 0)
        for pool in pools.values { CVPixelBufferPoolFlush(pool, .excessBuffers) }
    }

    private func validate(_ size: PixelSize) throws {
        guard size.width > 0, size.height > 0, size.width <= 16384, size.height <= 16384 else {
            throw DepthCheckError.message("The requested \(size.label) image exceeds this renderer's texture dimensions. Use Separate Eyes for very large stereo photos. No pixels were resized.")
        }
    }

    private func buffer(_ size: PixelSize) throws -> CVPixelBuffer {
        try validate(size)
        let key = size.label
        if pools[key] == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferMetalCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var pool: CVPixelBufferPool?
            guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess,
                  let pool else { throw DepthCheckError.message("Not enough memory for a \(size.label) image buffer.") }
            pools[key] = pool
        }
        var value: CVPixelBuffer?
        // The writer owns submitted buffers until it finishes encoding. The pool
        // recycles only released buffers; never overwrite an in-flight frame.
        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pools[key]!,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 10] as CFDictionary, &value)
        guard result == kCVReturnSuccess, let value else {
            throw DepthCheckError.message("The full-resolution buffer pool is busy or memory is exhausted. Enable Memory Saver and close other large apps, then retry. The export resolution was not reduced.")
        }
        CVBufferSetAttachment(value, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(value, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        CVBufferSetAttachment(value, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        return value
    }

    private func texture(_ buffer: CVPixelBuffer) throws -> (texture: MTLTexture, reference: CVMetalTexture) {
        var reference: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &reference)
        guard status == kCVReturnSuccess, let reference, let texture = CVMetalTextureGetTexture(reference) else {
            throw DepthCheckError.message("The device could not allocate the full-resolution Metal texture.")
        }
        return (texture, reference)
    }

    private func makeDepthTexture(_ depth: DepthMap) throws -> MTLTexture {
        guard depth.width > 0, depth.height > 0, depth.values.count == depth.width * depth.height else {
            throw DepthCheckError.message("The depth model returned an invalid image.")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: depth.width, height: depth.height, mipmapped: false)
        descriptor.usage = .shaderRead; descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw DepthCheckError.message("Not enough memory for the estimated depth.")
        }
        depth.values.withUnsafeBytes { bytes in
            texture.replace(region: MTLRegionMake2D(0, 0, depth.width, depth.height), mipmapLevel: 0,
                            withBytes: bytes.baseAddress!, bytesPerRow: depth.width * MemoryLayout<Float>.stride)
        }
        return texture
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, size: PixelSize) {
        let width = pipeline.threadExecutionWidth
        let height = max(1, min(8, pipeline.maxTotalThreadsPerThreadgroup / width))
        encoder.dispatchThreads(MTLSize(width: size.width, height: size.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
    }

    private func finish(_ command: MTLCommandBuffer) throws {
        command.commit(); command.waitUntilCompleted()
        guard command.status == .completed else {
            throw DepthCheckError.message("Metal rendering failed: \(command.error?.localizedDescription ?? "unknown GPU error").")
        }
    }
}
