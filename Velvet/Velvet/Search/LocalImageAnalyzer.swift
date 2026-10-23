import Foundation
import CoreGraphics
import ImageIO
import UIKit
import Vision

enum LocalImageAnalyzer {
    /// Decodes only a bounded analysis image. The original data is never re-encoded for storage.
    static func analyze(imageData: Data, itemID: UUID, mediaKind: String) throws -> (SearchDocument, Data) {
        guard imageData.count <= 160 * 1_024 * 1_024 else { throw LocalSearchError.imageTooLarge }
        return try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_024,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw LocalSearchError.invalidImage }

            let classification = VNClassifyImageRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.usesLanguageCorrection = true
            let feature = VNGenerateImageFeaturePrintRequest()
            feature.imageCropAndScaleOption = .scaleFit
            let faces = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            try handler.perform([classification, text, feature, faces])

            var labels = (classification.results ?? []).filter { $0.confidence >= 0.10 }
                .prefix(24).map { SearchLabel(name: $0.identifier.replacingOccurrences(of: "_", with: " "), confidence: $0.confidence) }
            if !(faces.results ?? []).isEmpty {
                labels.append(SearchLabel(name: "person face portrait", confidence: 0.9))
            }
            let words = (text.results ?? []).prefix(100)
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let observation = feature.results?.first
            let archive = try observation.map { try NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
            let colors = colorDescriptors(image)
            guard let analysisData = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else {
                throw LocalSearchError.invalidImage
            }
            return (SearchDocument(id: itemID, labels: labels, recognizedText: String(words.prefix(12_000)),
                                   colors: colors, featurePrint: archive, mediaKind: mediaKind), analysisData)
        }
    }

    static func featureSimilarity(_ lhs: Data, _ rhs: Data) -> Double? {
        do {
            guard let left = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: lhs),
                  let right = try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: rhs),
                  left.elementType == right.elementType, left.elementCount == right.elementCount else { return nil }
            var distance: Float = 0
            try left.computeDistance(&distance, to: right)
            guard distance.isFinite, distance >= 0 else { return nil }
            return 1 / (1 + Double(distance))
        } catch { return nil }
    }

    private static func colorDescriptors(_ image: CGImage) -> [String] {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard rendered else { return [] }
        var counts: [String: Int] = [:], border: [String: Int] = [:]
        var luminance = 0.0, red = 0.0, blue = 0.0
        for y in 0..<side {
            for x in 0..<side {
                let offset = (y * side + x) * 4
                let r = Double(pixels[offset]) / 255, g = Double(pixels[offset + 1]) / 255, b = Double(pixels[offset + 2]) / 255
                let color = colorName(red: r, green: g, blue: b)
                counts[color, default: 0] += 1
                if x < 3 || y < 3 || x >= side - 3 || y >= side - 3 { border[color, default: 0] += 1 }
                luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
                red += r; blue += b
            }
        }
        let total = Double(side * side)
        var result = counts.filter { Double($0.value) / total >= 0.08 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(5).map(\.key)
        let borderCount = border.values.reduce(0, +)
        if let dominantBorder = border.max(by: { $0.value < $1.value }), Double(dominantBorder.value) / Double(borderCount) > 0.62 {
            result.append("\(dominantBorder.key) background")
        }
        if luminance / total < 0.19 { result.append("dark low light") }
        if luminance / total > 0.72 { result.append("bright light") }
        // Simple image-wide color casts, not a claim about the actual light source.
        if (red - blue) / total > 0.13 { result.append("warm color") }
        if (blue - red) / total > 0.13 { result.append("cool color") }
        return result
    }

    private static func colorName(red r: Double, green g: Double, blue b: Double) -> String {
        let high = max(r, max(g, b)), low = min(r, min(g, b)), delta = high - low
        if high < 0.16 { return "black" }
        if delta < 0.10 { return high > 0.81 ? "white" : "gray" }
        var hue: Double
        if high == r { hue = (g - b) / delta }
        else if high == g { hue = 2 + (b - r) / delta }
        else { hue = 4 + (r - g) / delta }
        hue *= 60
        if hue < 0 { hue += 360 }
        switch hue {
        case 0..<18, 345..<360: return "red"
        case 18..<45: return high < 0.6 ? "brown" : "orange"
        case 45..<75: return "yellow"
        case 75..<165: return "green"
        case 165..<195: return "cyan"
        case 195..<265: return "blue"
        case 265..<310: return "purple"
        default: return "pink"
        }
    }
}
