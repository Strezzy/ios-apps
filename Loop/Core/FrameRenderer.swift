import Foundation
import CoreGraphics
import CoreImage
@preconcurrency import UIKit

/// The same compositor renders scrub previews and exported frames.
/// Input frames are upright SDR images; all edit positions refer to that source.
enum FrameRenderer {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        .outputColorSpace: colorSpace,
        .cacheIntermediates: false,
        .highQualityDownsample: true
    ])

    static func outputSize(project: LoopProject, maximumDimension: Int? = nil) -> PixelSize {
        let crop = project.crop.rect(source: project.metadata.size)
        let width = max(1, Double(project.metadata.size.width) * crop.width)
        let height = max(1, Double(project.metadata.size.height) * crop.height)
        let longEdge = max(width, height)
        var target = Double(project.export.maximumDimension == 0
            ? min(4096, Int(longEdge.rounded())) : project.export.maximumDimension)
        if let maximumDimension { target = min(target, Double(max(1, maximumDimension))) }
        let scale = project.export.allowUpscaling ? target / longEdge : min(1, target / longEdge)
        return PixelSize(width: max(1, Int((width * scale).rounded())),
                         height: max(1, Int((height * scale).rounded())))
    }

    static func render(_ image: CGImage, project: LoopProject, time: Double,
                       maximumDimension: Int? = nil) throws -> CGImage {
        try autoreleasepool {
            var frame = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: max(-1, min(1, project.adjustments.brightness)),
                kCIInputContrastKey: max(0, min(4, project.adjustments.contrast)),
                kCIInputSaturationKey: max(0, min(4, project.adjustments.saturation))
            ])
            let crop = project.crop.rect(source: project.metadata.size)
            let sourceWidth = Double(image.width), sourceHeight = Double(image.height)
            let cropRect = CGRect(x: crop.x * sourceWidth, y: (1 - crop.y - crop.height) * sourceHeight,
                                  width: crop.width * sourceWidth, height: crop.height * sourceHeight)
            frame = frame.cropped(to: cropRect).transformed(by:
                CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            let output = outputSize(project: project, maximumDimension: maximumDimension)
            let scaleX = Double(output.width) / cropRect.width
            let scaleY = Double(output.height) / cropRect.height
            frame = frame.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scaleY, kCIInputAspectRatioKey: scaleX / scaleY
            ])
            let extent = CGRect(x: 0, y: 0, width: output.width, height: output.height)
            frame = frame.cropped(to: extent)
            let width = Double(output.width), height = Double(output.height)
            // Map source positions into the final crop before compositing. Captions and emoji
            // are rasterized at the actual export resolution, even when video is upscaled.
            for overlay in project.overlays where overlay.isActive(at: time) {
                let normalized = overlay.rect(at: time)
                let rectangle = CGRect(x: (normalized.x - crop.x) / crop.width * width,
                                       y: (1 - (normalized.y - crop.y + normalized.height) / crop.height) * height,
                                       width: normalized.width / crop.width * width,
                                       height: normalized.height / crop.height * height)
                if !rectangle.intersects(extent) { continue }
                switch overlay.kind {
                case .blur, .pixelate, .cover:
                    let mask = try makeMask(size: output, rectangle: rectangle,
                                            shape: overlay.shape, opacity: overlay.opacity)
                    let strength = max(0, min(1, overlay.strength))
                    let effect: CIImage
                    if overlay.kind == .blur {
                        let radius = max(2, min(width, height) * (0.005 + strength * 0.055))
                        effect = frame.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [
                            kCIInputRadiusKey: radius
                        ]).cropped(to: extent)
                    } else if overlay.kind == .pixelate {
                        effect = frame.clampedToExtent().applyingFilter("CIPixellate", parameters: [
                            kCIInputScaleKey: max(3, min(width, height) * (0.005 + strength * 0.05)),
                            kCIInputCenterKey: CIVector(x: rectangle.midX, y: rectangle.midY)
                        ]).cropped(to: extent)
                    } else {
                        effect = CIImage(color: .black).cropped(to: extent)
                    }
                    frame = effect.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: frame,
                        kCIInputMaskImageKey: mask
                    ])
                case .emoji, .text:
                    guard let decoration = drawText(overlay, canvas: output, rectangle: rectangle) else {
                        throw LoopError.encoding("The caption could not be rendered.")
                    }
                    let texture = CIImage(cgImage: decoration)
                    frame = texture.composited(over: frame)
                }
            }
            if project.crop.mirror {
                frame = frame.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                               tx: CGFloat(output.width), ty: 0))
            }
            frame = frame.cropped(to: extent)
            guard let result = context.createCGImage(frame, from: extent, format: .RGBA8,
                                                      colorSpace: colorSpace) else {
                throw LoopError.encoding("The frame could not be rendered. Try a smaller resolution.")
            }
            return result
        }
    }

    static func clearCaches() { context.clearCaches() }

    private static func makeMask(size: PixelSize, rectangle: CGRect,
                                 shape: OverlayShape, opacity: Double) throws -> CIImage {
        let bounds = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let value = min(1, max(0, opacity))
        let white = CIColor(red: value, green: value, blue: value, alpha: 1)
        let background = CIImage(color: .black).cropped(to: bounds)
        if shape == .rectangle {
            return CIImage(color: white).cropped(to: rectangle).composited(over: background).cropped(to: bounds)
        }
        // Keep mask generation in Core Image's coordinate space. This also avoids a
        // full-resolution CPU mask allocation for every tracked overlay and frame.
        guard let radial = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputRadius0": 1.0,
            "inputRadius1": 1.0 + 1.0 / max(1, min(rectangle.width, rectangle.height)),
            "inputColor0": white,
            "inputColor1": CIColor.black
        ])?.outputImage else {
            throw LoopError.encoding("The circular overlay mask could not be generated.")
        }
        return radial.transformed(by: CGAffineTransform(scaleX: rectangle.width / 2, y: rectangle.height / 2))
            .transformed(by: CGAffineTransform(translationX: rectangle.midX, y: rectangle.midY))
            .cropped(to: bounds)
    }

    private static func drawText(_ overlay: OverlayItem, canvas: PixelSize, rectangle: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        // UIKit drawing has top-left coordinates; Core Image's rectangles use bottom-left.
        let textRect = CGRect(x: rectangle.minX, y: CGFloat(canvas.height) - rectangle.maxY,
                              width: rectangle.width, height: rectangle.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let string = String(overlay.content.prefix(500)) as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        var fontSize = min(textRect.height * 0.8, textRect.width)
        var attributes: [NSAttributedString.Key: Any] = [:]
        var measured = CGRect.zero
        for _ in 0..<15 {
            attributes = [.font: UIFont.systemFont(ofSize: max(5, fontSize), weight: .bold),
                          .foregroundColor: UIColor.white,
                          .paragraphStyle: paragraph]
            if overlay.kind == .text {
                attributes[.strokeColor] = UIColor.black.withAlphaComponent(0.85)
                attributes[.strokeWidth] = -4
            }
            measured = string.boundingRect(with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
                                            options: [.usesLineFragmentOrigin, .usesFontLeading],
                                            attributes: attributes, context: nil)
            if measured.height <= textRect.height * 0.96 && measured.width <= textRect.width { break }
            fontSize *= 0.84
        }
        return renderer.image { draw in
            draw.cgContext.setAlpha(min(1, max(0, overlay.opacity)))
            draw.cgContext.clip(to: textRect)
            string.draw(in: CGRect(x: textRect.minX, y: textRect.minY + max(0, (textRect.height - measured.height) / 2),
                                   width: textRect.width, height: textRect.height), withAttributes: attributes)
        }.cgImage
    }
}
