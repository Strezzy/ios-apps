import SwiftUI
import MetalKit
import CoreMotion

@MainActor
final class CardMotion: ObservableObject {
    @Published var tilt = SIMD2<Float>.zero
    private let manager = CMMotionManager()
    private var origin: CMAttitude?
    func start() {
        guard !manager.isDeviceMotionActive, manager.isDeviceMotionAvailable else { return }
        origin = nil; manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion,_ in
            guard let self, let motion else { return }
            if self.origin == nil { self.origin = motion.attitude.copy() as? CMAttitude }
            guard let attitude = motion.attitude.copy() as? CMAttitude, let origin = self.origin else { return }
            attitude.multiply(byInverseOf: origin)
            let target = SIMD2(Float(max(-1,min(1,attitude.roll * 2.4))), Float(max(-1,min(1,attitude.pitch * 2.4))))
            self.tilt += (target-self.tilt) * 0.16
        }
    }
    func stop() { manager.stopDeviceMotionUpdates(); origin = nil; tilt = .zero }
    deinit { manager.stopDeviceMotionUpdates() }
}

struct DepthPhoto: UIViewRepresentable {
    var image: UIImage
    var depth: UIImage?
    var tilt: SIMD2<Float>
    var amount: Double
    var onFailure: ((String) -> Void)? = nil
    func makeCoordinator() -> Renderer { Renderer() }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero,device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false; view.backgroundColor = .clear; view.clearColor = MTLClearColorMake(0,0,0,0)
        view.isPaused = true; view.enableSetNeedsDisplay = true; view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        do { try context.coordinator.configure(view) } catch { DispatchQueue.main.async { onFailure?(error.localizedDescription) } }
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        do { try context.coordinator.update(image: image,depth: depth,tilt: tilt,amount: amount) }
        catch { DispatchQueue.main.async { onFailure?(error.localizedDescription) } }
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Renderer) { view.delegate = nil; coordinator.photo = nil; coordinator.depth = nil }
    final class Renderer: NSObject, MTKViewDelegate {
        struct Uniforms { var tilt: SIMD2<Float>; var amount: Float; var hasDepth: Float }
        var device: MTLDevice?
        var queue: MTLCommandQueue?
        var pipeline: MTLRenderPipelineState?
        var photo: MTLTexture?
        var depth: MTLTexture?
        var lastPhoto: UIImage?
        var lastDepth: UIImage?
        var uniforms = Uniforms(tilt: .zero,amount: 0,hasDepth: 0)
        func configure(_ view: MTKView) throws {
            guard let device = view.device, let queue = device.makeCommandQueue(), let lib = device.makeDefaultLibrary(), let vertex = lib.makeFunction(name: "cardVertex"), let fragment = lib.makeFunction(name: "cardFragment") else { throw CollectrError.message("Live depth is unavailable on this device.") }
            let desc = MTLRenderPipelineDescriptor(); desc.vertexFunction = vertex; desc.fragmentFunction = fragment; desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            self.device = device; self.queue = queue; pipeline = try device.makeRenderPipelineState(descriptor: desc)
        }
        func update(image: UIImage,depth map: UIImage?,tilt: SIMD2<Float>,amount: Double) throws {
            guard let device else { return }
            let loader = MTKTextureLoader(device: device)
            let options: [MTKTextureLoader.Option: Any] = [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft]
            if lastPhoto !== image, let cg = image.cgImage { photo = try loader.newTexture(cgImage: cg,options: options); lastPhoto = image }
            if lastDepth !== map {
                if let cg = map?.cgImage { depth = try loader.newTexture(cgImage: cg,options: options) } else { depth = nil }; lastDepth = map
            }
            uniforms = Uniforms(tilt: tilt,amount: Float(amount),hasDepth: map == nil ? 0 : 1)
        }
        func draw(in view: MTKView) {
            guard let pipeline, let photo, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor, let buffer = queue?.makeCommandBuffer(), let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            enc.setRenderPipelineState(pipeline); enc.setFragmentTexture(photo,index: 0); enc.setFragmentTexture(depth ?? photo,index: 1)
            enc.setFragmentBytes(&uniforms,length: MemoryLayout<Uniforms>.stride,index: 0)
            enc.drawPrimitives(type: .triangleStrip,vertexStart: 0,vertexCount: 4); enc.endEncoding(); buffer.present(drawable); buffer.commit()
        }
        func mtkView(_ view: MTKView,drawableSizeWillChange size: CGSize) {}
    }
}
