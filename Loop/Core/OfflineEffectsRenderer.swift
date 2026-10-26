import Foundation
import CoreImage
import CoreGraphics
import CoreVideo
import ImageIO
@preconcurrency import Vision

struct EffectsAnalysis: @unchecked Sendable {
    var faces: [VNFaceObservation] = []
    var personMask: CIImage?
}

/// All effects are local Core Image / Vision operations. No network or downloaded models.
enum OfflineEffectsRenderer {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.cacheIntermediates: false, .highQualityDownsample: true])

    static func analyze(_ image: CIImage, faces: Bool, person: Bool, preview: Bool) throws -> EffectsAnalysis {
        guard faces || person else { return EffectsAnalysis() }
        let extent = image.extent
        let scale = min(1, (preview ? 512.0 : 768.0) / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let raster = context.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw LoopError.encoding("The effect's analysis frame could not be prepared.")
        }
        let faceRequest = VNDetectFaceLandmarksRequest()
        let maskRequest = VNGeneratePersonSegmentationRequest()
        maskRequest.qualityLevel = preview ? .balanced : .accurate
        maskRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        var requests: [VNRequest] = []
        if faces { requests.append(faceRequest) }
        if person { requests.append(maskRequest) }
        do { try VNImageRequestHandler(cgImage: raster, orientation: .up, options: [:]).perform(requests) }
        catch { throw LoopError.encoding("On-device effect analysis failed: \(error.localizedDescription)") }
        var result = EffectsAnalysis(faces: Array((faceRequest.results ?? []).filter { $0.confidence >= 0.35 }.prefix(6)))
        if let buffer = maskRequest.results?.first?.pixelBuffer {
            let mask = CIImage(cvPixelBuffer: buffer)
            result.personMask = mask.transformed(by: CGAffineTransform(
                scaleX: extent.width / mask.extent.width, y: extent.height / mask.extent.height))
                .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
                .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(0.5, extent.width / 2400)])
                .cropped(to: extent)
        }
        return result
    }

    static func apply(_ input: CIImage, settings: EffectSettings, time: Double,
                      preview: Bool, analysis supplied: EffectsAnalysis? = nil) throws -> CIImage {
        let layers = settings.activeLayers
        guard !layers.isEmpty else { return input }
        let needsFaces = layers.contains { EffectLibrary.preset($0.preset)?.category == .face }
        let needsPerson = layers.contains { let c = EffectLibrary.preset($0.preset)?.category; return c == .body || c == .background }
        let analysis = try supplied ?? analyze(input, faces: needsFaces, person: needsPerson, preview: preview)
        let extent = input.extent
        var image = input
        // Masks refer to the original upright source. Finish with grades, optics and atmosphere.
        for category in [EffectCategory.background, .body, .face, .looks, .lens, .atmosphere] {
            guard let layer = layers.first(where: { EffectLibrary.preset($0.preset)?.category == category }) else { continue }
            let amount = min(1, max(0, layer.amount))
            var output = image
            switch category {
            case .looks: output = look(image, id: layer.preset)
            case .lens: output = lens(image, id: layer.preset, time: time)
            case .face: output = FaceEffects.apply(image, id: layer.preset, faces: analysis.faces, time: time)
            case .body:
                if let mask = analysis.personMask {
                    let styled = body(image, id: layer.preset, time: time)
                    output = styled.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])
                    if layer.preset == "neonBody" || layer.preset == "electricBody" {
                        let glow = mask.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3])
                            .applyingFilter("CIFalseColor", parameters: ["inputColor0": CIColor(red: 0, green: 0, blue: 0), "inputColor1": CIColor(red: 0.1, green: 0.85, blue: 1)])
                            .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: extent.width * 0.006, kCIInputIntensityKey: 1])
                        output = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: output])
                    }
                }
            case .background:
                if let mask = analysis.personMask {
                    let background = background(image, id: layer.preset, time: time, custom: settings.backgroundImage)
                    output = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: background, kCIInputMaskImageKey: mask])
                }
            case .atmosphere:
                let overlay = ProceduralEffects.overlay(id: layer.preset, extent: extent, time: time)
                output = overlay.composited(over: image)
            }
            image = blend(image, output.cropped(to: extent), amount: amount).cropped(to: extent)
        }
        return image
    }

    static func thumbnail(_ source: CGImage, preset: EffectPreset, time: Double,
                          analysis: EffectsAnalysis? = nil, custom: Data? = nil) throws -> CGImage {
        var settings = EffectSettings()
        settings.select(preset.id, category: preset.category); settings.backgroundImage = custom
        let image = CIImage(cgImage: source)
        let output = try apply(image, settings: settings, time: time, preview: true, analysis: analysis)
        guard let result = context.createCGImage(output, from: image.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw LoopError.encoding("The filter preview could not be drawn.")
        }
        return result
    }

    static func boundedImage(_ image: CGImage, edge: CGFloat) -> CGImage? {
        let scale = min(1, edge / CGFloat(max(image.width, image.height)))
        let small = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: colorSpace)
    }
    static func clearCaches() { context.clearCaches() }
    static func blend(_ original: CIImage, _ modified: CIImage, amount: Double) -> CIImage {
        if amount >= 0.9999 { return modified }
        if amount <= 0 { return original }
        return original.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: modified, kCIInputTimeKey: amount])
    }
    private static func controls(_ image: CIImage, saturation: Double = 1, contrast: Double = 1, brightness: Double = 0) -> CIImage {
        image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputContrastKey: contrast, kCIInputBrightnessKey: brightness])
    }
    private static func tint(_ image: CIImage, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat, bias: CGFloat = 0) -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0), "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)])
    }
    private static func falseColor(_ image: CIImage, dark: CIColor, light: CIColor) -> CIImage {
        image.applyingFilter("CIFalseColor", parameters: ["inputColor0": dark, "inputColor1": light])
    }
    static func look(_ image: CIImage, id: String) -> CIImage {
        switch id {
        case "cinema": return tint(controls(image, saturation: 0.85, contrast: 1.12, brightness: -0.015), 1.03, 1, 0.96)
        case "tealGold": return splitTone(image, shadows: (0.0, 0.09, 0.12), highlights: (0.13, 0.05, -0.05))
        case "goldenHour": return tint(controls(image, saturation: 1.08, brightness: 0.025), 1.12, 1.03, 0.85)
        case "moonlight": return tint(controls(image, saturation: 0.6, contrast: 1.12, brightness: -0.06), 0.79, 0.94, 1.16)
        case "neonNight": return splitTone(controls(image, saturation: 1.22, contrast: 1.12), shadows: (0.1, -0.02, 0.13), highlights: (-0.04, 0.08, 0.1))
        case "roseFilm": return tint(controls(image, saturation: 0.83, contrast: 0.94, brightness: 0.035), 1.07, 0.94, 1.02)
        case "emerald": return tint(controls(image, saturation: 1.1, contrast: 1.06), 0.9, 1.08, 0.97)
        case "desert": return tint(controls(image, saturation: 0.8, contrast: 1.1, brightness: 0.02), 1.11, 1.03, 0.82)
        case "arctic": return tint(controls(image, saturation: 0.65, contrast: 1.05, brightness: 0.045), 0.9, 1.03, 1.12)
        case "noir": return image.applyingFilter("CIPhotoEffectNoir")
        case "silver": return image.applyingFilter("CIPhotoEffectTonal")
        case "matte": return controls(image, saturation: 0.85, contrast: 0.84, brightness: 0.035)
        case "instant": return image.applyingFilter("CIPhotoEffectInstant")
        case "faded": return image.applyingFilter("CIPhotoEffectFade")
        case "sepia": return image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.88])
        case "chrome": return image.applyingFilter("CIPhotoEffectChrome")
        case "vivid": return controls(image.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.7]), saturation: 1.15, contrast: 1.06)
        case "pastel": return tint(controls(image, saturation: 0.67, contrast: 0.83, brightness: 0.06), 1.03, 1, 1.03)
        case "bleach": return controls(image, saturation: 0.32, contrast: 1.4, brightness: 0.015)
        case "horror": return tint(controls(image, saturation: 0.38, contrast: 1.24, brightness: -0.04), 0.89, 1.07, 0.87)
        case "vampire": return splitTone(controls(image, saturation: 0.4, contrast: 1.24), shadows: (0.08, -0.02, 0.02), highlights: (0.1, -0.01, -0.03))
        case "underwater": return tint(controls(image, saturation: 0.8, contrast: 0.94), 0.66, 1.08, 1.17)
        case "peach": return tint(controls(image, saturation: 0.88, brightness: 0.04), 1.08, 0.99, 0.91)
        case "lavender": return tint(controls(image, saturation: 0.75, contrast: 0.94, brightness: 0.03), 1.04, 0.94, 1.1)
        case "autumn": return tint(controls(image, saturation: 1.13, contrast: 1.09), 1.14, 0.98, 0.79)
        case "forest": return tint(controls(image, saturation: 0.78, contrast: 1.19, brightness: -0.025), 0.88, 1.05, 0.86)
        case "sunset": return splitTone(image, shadows: (0.07, -0.02, 0.09), highlights: (0.14, 0.05, -0.07))
        case "infrared": return falseColor(image, dark: CIColor(red: 0.12, green: 0.02, blue: 0.22), light: CIColor(red: 1, green: 0.57, blue: 0.58))
        case "duotone": return falseColor(image, dark: CIColor(red: 0.05, green: 0.04, blue: 0.22), light: CIColor(red: 1, green: 0.78, blue: 0.62))
        case "crossProcess": return image.applyingFilter("CIPhotoEffectProcess")
        default: return image
        }
    }
    private static func splitTone(_ image: CIImage, shadows: (CGFloat, CGFloat, CGFloat), highlights: (CGFloat, CGFloat, CGFloat)) -> CIImage {
        // Per-channel quadratics preserve highlights rather than placing a flat tint over the frame.
        func vector(_ s: CGFloat, _ h: CGFloat) -> CIVector { CIVector(x: s, y: 1 - s + h, z: -h, w: 0) }
        return image.applyingFilter("CIColorPolynomial", parameters: [
            "inputRedCoefficients": vector(shadows.0, highlights.0),
            "inputGreenCoefficients": vector(shadows.1, highlights.1),
            "inputBlueCoefficients": vector(shadows.2, highlights.2)])
    }
    static func lens(_ image: CIImage, id: String, time: Double) -> CIImage {
        let e = image.extent, edge = min(e.width, e.height)
        switch id {
        case "bloom": return image.clampedToExtent().applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: edge * 0.018, kCIInputIntensityKey: 0.55]).cropped(to: e)
        case "softFocus":
            let blur = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: edge * 0.005]).cropped(to: e)
            return blend(image, blur, amount: 0.35)
        case "vignette": return image.applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 1.25, kCIInputRadiusKey: edge * 0.65])
        case "grain": return ProceduralEffects.overlay(id: "grain", extent: e, time: time).composited(over: image)
        case "vhs": return ProceduralEffects.overlay(id: "vhs", extent: e, time: time).composited(over: tint(controls(image, saturation: 0.8, contrast: 0.93), 1.03, 1, 0.95))
        case "scanlines": return ProceduralEffects.overlay(id: "scanlines", extent: e, time: time).composited(over: image)
        case "comic": return image.applyingFilter("CIComicEffect")
        case "poster": return image.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 5.0])
        case "halftone": return image.applyingFilter("CIDotScreen", parameters: [kCIInputWidthKey: max(3, edge * 0.009), kCIInputSharpnessKey: 0.75])
        case "crystal": return image.applyingFilter("CICrystallize", parameters: [kCIInputRadiusKey: max(3, edge * 0.018)])
        case "kaleidoscope": return image.applyingFilter("CIKaleidoscope", parameters: ["inputCount": 6, kCIInputCenterKey: CIVector(x: e.midX, y: e.midY), kCIInputAngleKey: 0.2])
        case "prism":
            let shifted = image.clampedToExtent().transformed(by: CGAffineTransform(translationX: edge * 0.008, y: 0)).cropped(to: e)
            let red = tint(shifted, 1, 0, 0), cyan = tint(image, 0, 1, 1)
            return red.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: cyan]).cropped(to: e)
        default: return image
        }
    }
    private static func body(_ image: CIImage, id: String, time: Double) -> CIImage {
        let e = image.extent
        switch id {
        case "hologram": return ProceduralEffects.overlay(id: "scanlines", extent: e, time: time).composited(over: falseColor(image, dark: CIColor(red: 0, green: 0.07, blue: 0.2), light: CIColor(red: 0.3, green: 1, blue: 1)))
        case "goldStatue": return falseColor(controls(image, saturation: 0, contrast: 1.3), dark: CIColor(red: 0.12, green: 0.06, blue: 0.01), light: CIColor(red: 1, green: 0.84, blue: 0.3))
        case "silverStatue": return controls(image, saturation: 0, contrast: 1.45, brightness: 0.04)
        case "galaxyBody": return blend(image, ProceduralEffects.background(id: "deepSpace", extent: e, time: time), amount: 0.86)
        case "thermalBody": return image.applyingFilter("CIThermal")
        case "neonBody": return falseColor(image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 3]), dark: .black, light: CIColor(red: 0.1, green: 0.9, blue: 1))
        case "ghostBody": return blend(image, controls(image, saturation: 0, contrast: 0.65, brightness: 0.2), amount: 0.8)
        case "inkBody": return image.applyingFilter("CILineOverlay", parameters: ["inputNRNoiseLevel": 0.07, "inputEdgeIntensity": 1.7, "inputContrast": 40])
        case "pixelBody": return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(4, e.width * 0.015)])
        case "silhouette": return CIImage(color: CIColor(red: 0.015, green: 0.02, blue: 0.04)).cropped(to: e)
        case "paperBody": return controls(image.applyingFilter("CIColorPosterize", parameters: ["inputLevels": 4]), saturation: 0.6, brightness: 0.08)
        case "electricBody": return image.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 5]).applyingFilter("CIBloom", parameters: [kCIInputIntensityKey: 1, kCIInputRadiusKey: e.width * 0.005])
        case "auroraBody": return blend(image, ProceduralEffects.background(id: "auroraSky", extent: e, time: time), amount: 0.75)
        case "rainbowBody": return image.applyingFilter("CIFalseColor", parameters: ["inputColor0": CIColor(red: 0.65, green: 0.05, blue: 1), "inputColor1": CIColor(red: 0.1, green: 1, blue: 0.45)])
        default: return image
        }
    }
    private static func background(_ image: CIImage, id: String, time: Double, custom: Data?) -> CIImage {
        let e = image.extent
        switch id {
        case "portraitBlur": return image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(e.width, e.height) * 0.025]).cropped(to: e)
        case "monoBackground": return controls(image, saturation: 0)
        case "comicBackdrop": return image.applyingFilter("CIComicEffect")
        case "pixelBackdrop": return image.applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(5, e.width * 0.025)])
        case "customBackground":
            guard let custom, custom.count <= 8_000_000, let photo = CIImage(data: custom, options: [.applyOrientationProperty: true]) else { return image }
            let scale = max(e.width / photo.extent.width, e.height / photo.extent.height)
            let scaled = photo.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            return scaled.transformed(by: CGAffineTransform(translationX: e.midX - scaled.extent.midX, y: e.midY - scaled.extent.midY)).cropped(to: e)
        default: return ProceduralEffects.background(id: id, extent: e, time: time)
        }
    }
}
