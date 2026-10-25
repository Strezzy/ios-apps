import SwiftUI
import MetalKit
import CoreVideo
import CoreMedia
import QuartzCore
import simd

struct SpatialVideoSurface: UIViewRepresentable {
    @ObservedObject var player: SpatialPlaybackController
    let motion: TiltMotionController

    func makeCoordinator() -> Coordinator { Coordinator(player: player, motion: motion) }

    func makeUIView(context: Context) -> OrbitMetalView {
        let view = OrbitMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.backgroundColor = .black
        view.isOpaque = true
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.autoResizeDrawable = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 60
        view.accessibilityLabel = "Spatial video"
        view.accessibilityIdentifier = "orbit.video.surface"
        view.coordinator = context.coordinator
        (view.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ view: OrbitMetalView, context: Context) {
        context.coordinator.player = player
    }

    static func dismantleUIView(_ view: OrbitMetalView, coordinator: Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.stop()
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var player: SpatialPlaybackController
        let motion: TiltMotionController
        private var renderer: OrbitRenderer?
        private weak var view: OrbitMetalView?
        private var observers: [NSObjectProtocol] = []

        init(player: SpatialPlaybackController, motion: TiltMotionController) {
            self.player = player
            self.motion = motion
        }

        func attach(_ view: OrbitMetalView) {
            self.view = view
            do {
                renderer = try OrbitRenderer(view: view)
                view.delegate = self
            } catch {
                Task { @MainActor [weak self] in self?.player.reportRenderingError(error.localizedDescription) }
            }
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setVisible(false) }
            })
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.setVisible(self.view?.window != nil)
                }
            })
            observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.updateBudget() }
            })
            observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.renderer?.purgeTransientCaches() }
            })
            updateBudget()
        }

        func setVisible(_ visible: Bool) {
            view?.isPaused = !visible || renderer == nil
            if visible { motion.start() }
            else { motion.stop() }
        }

        private func updateBudget() {
            let constrained = ProcessInfo.processInfo.thermalState == .serious ||
                              ProcessInfo.processInfo.thermalState == .critical ||
                              ProcessInfo.processInfo.isLowPowerModeEnabled
            view?.preferredFramesPerSecond = constrained ? 30 : 60
            view?.maximumDimension = constrained ? 1920 : 2560
            view?.setNeedsLayout()
            renderer?.analysisDimension = constrained ? 256 : 384
        }

        func draw(in view: MTKView) {
            guard let renderer else { return }
            let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            let tilt = motion.sample(orientation: orientation, includeDeviceMotion: player.tiltEnabled)
            do {
                try renderer.draw(in: view, player: player, tilt: tilt)
            } catch {
                view.isPaused = true
                player.reportRenderingError(error.localizedDescription)
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func stop() {
            motion.stop()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            renderer = nil
        }
    }
}

final class OrbitMetalView: MTKView {
    weak var coordinator: SpatialVideoSurface.Coordinator?
    var maximumDimension: CGFloat = 2560

    override func didMoveToWindow() {
        super.didMoveToWindow()
        coordinator?.setVisible(window != nil && UIApplication.shared.applicationState == .active)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let screenScale = window?.screen.scale ?? traitCollection.displayScale
        let longest = max(bounds.width, bounds.height) * screenScale
        let scale = screenScale * min(1, maximumDimension / max(1, longest))
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()),
                          height: max(1, (bounds.height * scale).rounded()))
        if drawableSize != size { drawableSize = size }
    }
}

private struct OrbitRenderParameters {
    var textureTransform: simd_float3x3
    var contentScale: SIMD2<Float>
    var motion: SIMD2<Float>
    var strength: Float
    var aspect: Float
    var spatial: UInt32
    var hasDepth: UInt32
}

private struct OrbitMatchParameters {
    var width: UInt32
    var height: UInt32
    var radius: Int32
    var padding: UInt32 = 0
}

private struct OrbitFilterParameters {
    var historyWeight: Float
    var disparityLimit: Float = 0.07
    var historyValid: UInt32
    var padding: UInt32 = 0
}

private struct OrbitFrameTextures {
    let frame: StereoVideoFrame
    let left: MTLTexture
    let right: MTLTexture
    let references: [CVMetalTexture]
}

/// One serial command queue, two in-flight commands, and one current stereo pair.
/// Analysis is reduced; decoded color remains at the video's original resolution.
@MainActor
private final class OrbitRenderer {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private var cache: CVMetalTextureCache!
    private let lumaPipeline: MTLComputePipelineState
    private let censusPipeline: MTLComputePipelineState
    private let coarsePipeline: MTLComputePipelineState
    private let refinePipeline: MTLComputePipelineState
    private let smoothPipeline: MTLComputePipelineState
    private let renderPipeline: MTLRenderPipelineState
    private let inFlight = DispatchSemaphore(value: 2)
    private var current: OrbitFrameTextures?
    private var work: OrbitDepthTextures?
    private var depthIndex = 0
    private var lastDepthTime: CMTime?
    private var gpuError: String?
    var analysisDimension = 384

    init(view: MTKView) throws {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else {
            throw OrbitRenderError.message("The video renderer could not start on this device.")
        }
        self.device = device
        self.queue = queue
        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw OrbitRenderError.message("The installed app is missing its depth renderer. Please reinstall Orbit.")
            }
            return try device.makeComputePipelineState(function: function)
        }
        lumaPipeline = try compute("orbitLuma")
        censusPipeline = try compute("orbitCensus")
        coarsePipeline = try compute("orbitCoarseMatch")
        refinePipeline = try compute("orbitRefineDepth")
        smoothPipeline = try compute("orbitStabilizeDepth")
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbitVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbitFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            throw OrbitRenderError.message("The video texture cache could not be created.")
        }
    }

    func draw(in view: MTKView, player: SpatialPlaybackController, tilt: SIMD2<Float>) throws {
        if let gpuError { throw OrbitRenderError.message(gpuError) }
        // Never queue rendering work behind the display: skip a tick if the GPU is busy.
        guard inFlight.wait(timeout: .now()) == .success else { return }
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable, let command = queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        if player.duration <= 0 { current = nil; lastDepthTime = nil }
        if let frame = player.frame(atHostTime: CACurrentMediaTime()) {
            current = try wrap(frame)
            if let current, frame.isSpatial, frame.right != nil {
                try ensureDepthTextures(width: current.left.width, height: current.left.height)
                if let work {
                    let delta = lastDepthTime.map { CMTimeSubtract(frame.presentationTime, $0).seconds } ?? 0
                    let historyValid = delta > 0 && delta < 0.20
                    try encodeDepth(command: command, frame: current, work: work, historyValid: historyValid)
                    lastDepthTime = frame.presentationTime
                    if player.depthStatus != "Depth ready" { player.depthStatus = "Depth ready" }
                }
            } else {
                lastDepthTime = nil
            }
        }

        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else {
            throw OrbitRenderError.message("The video frame could not be displayed.")
        }
        if let current {
            let rawSize = CGSize(width: current.left.width, height: current.left.height)
            let display = OrbitGeometry.displaySize(source: rawSize, transform: current.frame.transform)
            var params = OrbitRenderParameters(
                textureTransform: OrbitGeometry.textureTransform(source: rawSize, transform: current.frame.transform),
                contentScale: OrbitGeometry.contentScale(source: display, viewport: view.drawableSize, fill: player.fillScreen),
                motion: tilt, strength: Float(min(1, max(0, player.depthStrength))),
                aspect: Float(display.width / display.height),
                spatial: current.frame.isSpatial ? 1 : 0, hasDepth: lastDepthTime == nil ? 0 : 1)
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(current.left, index: 0)
            encoder.setFragmentTexture(current.right, index: 1)
            // A valid texture is bound even for flat playback; the shader does not sample it.
            encoder.setFragmentTexture(work?.depth[depthIndex] ?? current.left, index: 2)
            encoder.setFragmentBytes(&params, length: MemoryLayout<OrbitRenderParameters>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        command.present(drawable)
        let retainedFrame = current
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] buffer in
            withExtendedLifetime(retainedFrame) {}
            semaphore.signal()
            if buffer.status == .error {
                let message = buffer.error?.localizedDescription ?? "The GPU could not display this video."
                Task { @MainActor [weak self] in self?.gpuError = message }
            }
        }
        submitted = true
        command.commit()
    }

    func purgeTransientCaches() {
        CVMetalTextureCacheFlush(cache, 0)
        analysisDimension = 256
    }

    private func wrap(_ frame: StereoVideoFrame) throws -> OrbitFrameTextures {
        func texture(_ pixelBuffer: CVPixelBuffer) throws -> (MTLTexture, CVMetalTexture) {
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
                throw OrbitRenderError.message("This video could not be converted to a supported display format.")
            }
            var reference: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer,
                nil, .bgra8Unorm, CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer), 0, &reference)
            guard status == kCVReturnSuccess, let reference, let value = CVMetalTextureGetTexture(reference) else {
                throw OrbitRenderError.message("There isn't enough available memory to display this video. Close other apps and try again.")
            }
            return (value, reference)
        }
        let left = try texture(frame.left)
        if let rightBuffer = frame.right {
            let right = try texture(rightBuffer)
            return OrbitFrameTextures(frame: frame, left: left.0, right: right.0, references: [left.1, right.1])
        }
        return OrbitFrameTextures(frame: frame, left: left.0, right: left.0, references: [left.1])
    }

    private func ensureDepthTextures(width: Int, height: Int) throws {
        let ratio = min(1, Double(analysisDimension) / Double(max(width, height)))
        let w = max(32, Int((Double(width) * ratio).rounded()) / 2 * 2)
        let h = max(32, Int((Double(height) * ratio).rounded()) / 2 * 2)
        if work?.width == w && work?.height == h { return }
        work = try OrbitDepthTextures(device: device, width: w, height: h)
        depthIndex = 0
        lastDepthTime = nil
    }

    private func encodeDepth(command: MTLCommandBuffer, frame: OrbitFrameTextures,
                             work: OrbitDepthTextures, historyValid: Bool) throws {
        func encoder(_ pipeline: MTLComputePipelineState) throws -> MTLComputeCommandEncoder {
            guard let encoder = command.makeComputeCommandEncoder() else {
                throw OrbitRenderError.message("The depth frame could not be prepared.")
            }
            encoder.setComputePipelineState(pipeline)
            return encoder
        }
        for (color, luma, coarseLuma, census, coarseCensus) in [
            (frame.left, work.leftLuma, work.coarseLeftLuma, work.leftCensus, work.coarseLeftCensus),
            (frame.right, work.rightLuma, work.coarseRightLuma, work.rightCensus, work.coarseRightCensus)
        ] {
            for destination in [luma, coarseLuma] {
                let e = try encoder(lumaPipeline)
                e.setTexture(color, index: 0); e.setTexture(destination, index: 1)
                dispatch(e, pipeline: lumaPipeline, texture: destination)
                e.endEncoding()
            }
            for (source, destination) in [(luma, census), (coarseLuma, coarseCensus)] {
                let e = try encoder(censusPipeline)
                e.setTexture(source, index: 0); e.setTexture(destination, index: 1)
                dispatch(e, pipeline: censusPipeline, texture: destination)
                e.endEncoding()
            }
        }
        for (a, b, result) in [
            (work.coarseLeftCensus, work.coarseRightCensus, work.coarseLeftDepth),
            (work.coarseRightCensus, work.coarseLeftCensus, work.coarseRightDepth)
        ] {
            let e = try encoder(coarsePipeline)
            e.setTexture(a, index: 0); e.setTexture(b, index: 1); e.setTexture(result, index: 2)
            var params = OrbitMatchParameters(width: UInt32(result.width), height: UInt32(result.height),
                                               radius: Int32(max(6, min(24, Int(Double(result.width) * 0.085)))))
            e.setBytes(&params, length: MemoryLayout<OrbitMatchParameters>.stride, index: 0)
            dispatch(e, pipeline: coarsePipeline, texture: result)
            e.endEncoding()
        }
        let refine = try encoder(refinePipeline)
        for (i, texture) in [work.leftCensus, work.rightCensus, work.coarseLeftDepth,
                              work.coarseRightDepth, work.leftLuma, work.rawDepth].enumerated() {
            refine.setTexture(texture, index: i)
        }
        dispatch(refine, pipeline: refinePipeline, texture: work.rawDepth)
        refine.endEncoding()
        let previous = depthIndex
        depthIndex = 1 - depthIndex
        let filter = try encoder(smoothPipeline)
        for (i, texture) in [work.rawDepth, work.leftLuma, work.depth[previous],
                              work.previousLuma, work.depth[depthIndex]].enumerated() {
            filter.setTexture(texture, index: i)
        }
        var params = OrbitFilterParameters(historyWeight: 0.48, historyValid: historyValid ? 1 : 0)
        filter.setBytes(&params, length: MemoryLayout<OrbitFilterParameters>.stride, index: 0)
        dispatch(filter, pipeline: smoothPipeline, texture: work.depth[depthIndex])
        filter.endEncoding()
        guard let copy = command.makeBlitCommandEncoder() else {
            throw OrbitRenderError.message("The depth history could not be updated.")
        }
        copy.copy(from: work.leftLuma, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: work.width, height: work.height, depth: 1),
                  to: work.previousLuma, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        copy.endEncoding()
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, texture: MTLTexture) {
        let width = pipeline.threadExecutionWidth
        let height = min(8, max(1, pipeline.maxTotalThreadsPerThreadgroup / width))
        encoder.dispatchThreads(MTLSize(width: texture.width, height: texture.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
    }
}

private final class OrbitDepthTextures {
    let width: Int, height: Int
    let leftLuma: MTLTexture, rightLuma: MTLTexture, previousLuma: MTLTexture
    let coarseLeftLuma: MTLTexture, coarseRightLuma: MTLTexture
    let leftCensus: MTLTexture, rightCensus: MTLTexture
    let coarseLeftCensus: MTLTexture, coarseRightCensus: MTLTexture
    let coarseLeftDepth: MTLTexture, coarseRightDepth: MTLTexture
    let rawDepth: MTLTexture
    let depth: [MTLTexture]

    init(device: MTLDevice, width: Int, height: Int) throws {
        self.width = width; self.height = height
        func texture(_ format: MTLPixelFormat, _ scale: Int = 1) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                width: width / scale, height: height / scale, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw OrbitRenderError.message("There isn't enough available memory for spatial depth.")
            }
            return texture
        }
        leftLuma = try texture(.r16Float); rightLuma = try texture(.r16Float)
        previousLuma = try texture(.r16Float)
        coarseLeftLuma = try texture(.r16Float, 2); coarseRightLuma = try texture(.r16Float, 2)
        leftCensus = try texture(.r32Uint); rightCensus = try texture(.r32Uint)
        coarseLeftCensus = try texture(.r32Uint, 2); coarseRightCensus = try texture(.r32Uint, 2)
        coarseLeftDepth = try texture(.rg16Float, 2); coarseRightDepth = try texture(.rg16Float, 2)
        rawDepth = try texture(.rg16Float)
        depth = [try texture(.rg16Float), try texture(.rg16Float)]
    }
}

private enum OrbitRenderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
