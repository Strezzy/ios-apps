import Foundation
import CoreML
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import MetalPerformanceShaders
import RifeMetal

final class FrameProcessor {
    let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var restoration: MLModel?
    private var motion: RifeInterpolator?
    private let bundle: Bundle

    /// Do not initialize MPSGraph on the hosted simulator's virtual GPU. Its
    /// device descriptor raises an Objective-C exception before inference starts.
    /// The device build retains the real RIFE implementation, not frame blending.
    static var motionUnavailableReason: String? {
        #if targetEnvironment(simulator)
        return "RIFE GPU motion is not enabled in simulator builds. Test frame interpolation on a physical iPhone or iPad."
        #else
        guard let device = MTLCreateSystemDefaultDevice(), MPSSupportsMTLDevice(device) else {
            return "This device does not provide the Metal Performance Shaders support required for AI motion. Choose Original FPS."
        }
        return nil
        #endif
    }
    static func requireMotionSupport() throws {
        if let reason = motionUnavailableReason { throw LiftError.message(reason) }
    }
    init(bundle: Bundle = .main) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LiftError.message("This device could not start Metal. No cloud or fake-processing fallback is used.")
        }
        self.bundle = bundle
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
    }
    func loadRestoration() throws {
        if restoration != nil { return }
        guard let url = bundle.url(forResource: "LumaGeneral", withExtension: "mlmodelc") else {
            throw LiftError.message("The bundled enhancement model is missing. Reinstall the complete LumaLift release.")
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: url, configuration: configuration)
        guard let input = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint,
              input.pixelsWide == TileRegion.inputSize, input.pixelsHigh == TileRegion.inputSize,
              model.modelDescription.outputDescriptionsByName["enhanced"]?.type == .image else {
            throw LiftError.message("The bundled model is not compatible with this build.")
        }
        restoration = model
    }
    func interpolate(_ a: CVPixelBuffer, _ b: CVPixelBuffer, fraction: Float) throws -> CVPixelBuffer {
        guard fraction.isFinite, (0...1).contains(fraction),
              CVPixelBufferGetWidth(a) == CVPixelBufferGetWidth(b),
              CVPixelBufferGetHeight(a) == CVPixelBufferGetHeight(b) else {
            throw LiftError.message("AI motion received incompatible frames or an invalid timestamp.")
        }
        if fraction <= 0.00001 { return a }
        if fraction >= 0.99999 { return b }
        try Self.requireMotionSupport()
        if motion == nil { motion = try RifeInterpolator(configuration: .bundled(qualityTier: .fast)) }
        guard let motion else { throw LiftError.message("The motion model could not start.") }
        let results = try motion.interpolate(previous: a, current: b, timesteps: [fraction])
        guard let result = results.first else { throw LiftError.message("The motion model returned no frame.") }
        return result
    }
    func restore(_ input: CVPixelBuffer, settings: EnhanceSettings, control: WorkControl,
                 onWait: ((String) -> Void)? = nil) throws -> CVPixelBuffer {
        guard settings.usesRestoration else { return input }
        try loadRestoration()
        guard let restoration else { throw LiftError.message("Enhancement is unavailable.") }
        let width = CVPixelBufferGetWidth(input), height = CVPixelBufferGetHeight(input)
        let scale = settings.scale
        let output = try makePixelBuffer(width: width * scale, height: height * scale)
        let tile = try makePixelBuffer(width: TileRegion.inputSize, height: TileRegion.inputSize)
        let source = CIImage(cvPixelBuffer: input, options: [.colorSpace: colorSpace])
        let pad = TileRegion.padding
        // Process one padded tile at a time, without a full 4x intermediate frame.
        for region in TileRegion.regions(width: width, height: height) {
            try control.checkpoint(gentle: settings.gentleProcessing, onWait: onWait)
            try autoreleasepool {
                let tileRect = CGRect(x: region.x - pad, y: region.y - pad,
                                      width: TileRegion.inputSize, height: TileRegion.inputSize)
                let local = source.clampedToExtent().cropped(to: tileRect)
                    .transformed(by: CGAffineTransform(translationX: -tileRect.minX, y: -tileRect.minY))
                context.render(local, to: tile, bounds: CGRect(x: 0, y: 0, width: TileRegion.inputSize,
                                                              height: TileRegion.inputSize), colorSpace: colorSpace)
                let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: tile)])
                let prediction = try restoration.prediction(from: provider)
                guard let enhanced = prediction.featureValue(for: "enhanced")?.imageBufferValue else {
                    throw LiftError.message("The enhancement model returned an invalid frame.")
                }
                let crop = CGRect(x: pad * 4, y: pad * 4, width: region.width * 4, height: region.height * 4)
                let restored = CIImage(cvPixelBuffer: enhanced, options: [.colorSpace: colorSpace])
                    .cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
                let resized = resize(restored, factor: Double(scale) / 4)
                let originalRect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
                let original = source.cropped(to: originalRect)
                    .transformed(by: CGAffineTransform(translationX: -originalRect.minX, y: -originalRect.minY))
                let originalResized = resize(original, factor: Double(scale))
                let amount = settings.enhance ? settings.strength : 0.5
                let blend = CIFilter.dissolveTransition()
                blend.inputImage = originalResized
                blend.targetImage = resized
                blend.time = Float(amount)
                guard let blended = blend.outputImage else { throw LiftError.message("Could not compose the enhanced frame.") }
                let w = region.width * scale, h = region.height * scale
                let result = try makePixelBuffer(width: w, height: h)
                context.render(blended, to: result, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: colorSpace)
                // Core Image coordinates are bottom-left; BGRA storage is top-first.
                try copyTile(result, into: output, x: region.x * scale,
                             top: (height - region.y - region.height) * scale)
            }
        }
        return output
    }
    private func resize(_ image: CIImage, factor: Double) -> CIImage {
        guard factor != 1 else { return image }
        return image.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: factor, kCIInputAspectRatioKey: 1.0])
    }
    private func copyTile(_ source: CVPixelBuffer, into destination: CVPixelBuffer, x: Int, top: Int) throws {
        guard x >= 0, top >= 0,
              x + CVPixelBufferGetWidth(source) <= CVPixelBufferGetWidth(destination),
              top + CVPixelBufferGetHeight(source) <= CVPixelBufferGetHeight(destination) else {
            throw LiftError.message("An enhanced tile exceeded the output bounds.")
        }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else {
            throw LiftError.message("Could not read an enhanced tile.")
        }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else {
            throw LiftError.message("Could not write the output frame.")
        }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let src = CVPixelBufferGetBaseAddress(source), let dst = CVPixelBufferGetBaseAddress(destination) else {
            throw LiftError.message("A pixel buffer became unavailable.")
        }
        let width = CVPixelBufferGetWidth(source), height = CVPixelBufferGetHeight(source)
        for row in 0..<height {
            memcpy(dst.advanced(by: (top + row) * CVPixelBufferGetBytesPerRow(destination) + x * 4),
                   src.advanced(by: row * CVPixelBufferGetBytesPerRow(source)), width * 4)
        }
    }
    /// Conservative cut guard: skip large flashes or very fast movement rather
    /// than inventing a transition between unrelated images.
    func isSceneCut(_ a: CVPixelBuffer, _ b: CVPixelBuffer) -> Bool {
        func thumbnail(_ buffer: CVPixelBuffer) -> [UInt8] {
            let image = CIImage(cvPixelBuffer: buffer)
                .transformed(by: CGAffineTransform(scaleX: 32 / Double(CVPixelBufferGetWidth(buffer)),
                                                   y: 18 / Double(CVPixelBufferGetHeight(buffer))))
            var pixels = [UInt8](repeating: 0, count: 32 * 18 * 4)
            pixels.withUnsafeMutableBytes {
                if let pointer = $0.baseAddress {
                    context.render(image, toBitmap: pointer, rowBytes: 32 * 4,
                                   bounds: CGRect(x: 0, y: 0, width: 32, height: 18), format: .RGBA8, colorSpace: colorSpace)
                }
            }
            return pixels
        }
        let first = thumbnail(a), second = thumbnail(b)
        var difference = 0.0
        for index in stride(from: 0, to: first.count, by: 4) {
            for channel in 0..<3 { difference += abs(Double(first[index + channel]) - Double(second[index + channel])) }
        }
        return difference / (Double(32 * 18 * 3) * 255) > 0.28
    }
}
