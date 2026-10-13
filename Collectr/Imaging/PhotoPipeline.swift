import UIKit
import CoreImage
import ImageIO
import Photos

struct PhotoEdits: Equatable {
    var exposure = 0.0
    var saturation = 1.0
    var warmth = 0.0
    var cropX = 0.5
    var cropY = 0.5
}

final class PhotoPipeline: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func render(_ source: Data, edits: PhotoEdits) throws -> UIImage {
        guard let src = CGImageSourceCreateWithData(source as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CollectrError.message("This photo could not be opened.") }
        var image = CIImage(cgImage: cg)
        let width = min(image.extent.width, image.extent.height * 5 / 7)
        let height = width * 7 / 5
        let rect = CGRect(x: (image.extent.width - width) * edits.cropX, y: (image.extent.height - height) * (1 - edits.cropY), width: width, height: height).integral
        image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        let scale = min(1, 2200 / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: edits.exposure])
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: edits.saturation])
            .applyingFilter("CITemperatureAndTint", parameters: ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 6500 + edits.warmth * 1800, y: 0)])
        guard let output = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { throw CollectrError.message("This photo could not be prepared.") }
        return UIImage(cgImage: output)
    }
    func depth(_ image: UIImage) async throws -> UIImage {
        try await DepthJobs.shared.predict(image)
    }
    // Same bounded, saturation-weighted three-cluster method as Music's ArtworkPalette.h.
    static func palette(_ image: UIImage) -> [RGB] {
        guard let cg = image.cgImage else { return RGB.defaults }
        var bytes = [UInt8](repeating: 0, count: 48 * 48 * 4)
        let ok = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 192, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 48, height: 48)); return true
        }
        guard ok else { return RGB.defaults }
        var bins = Array(repeating: SIMD4<Double>.zero, count: 512)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[i+3]) / 255
            guard alpha > 0.125 else { continue }
            let c = SIMD3<Double>(Double(bytes[i]), Double(bytes[i+1]), Double(bytes[i+2])) / (255 * alpha)
            let hi = max(c.x, max(c.y,c.z)), lo = min(c.x,min(c.y,c.z))
            var weight = alpha * (0.3 + 0.7 * (hi > 0.01 ? (hi-lo)/hi : 0))
            if hi < 0.07 || lo > 0.94 { weight *= 0.2 }
            let key = (min(7,Int(c.x*7.999)) << 6) | (min(7,Int(c.y*7.999)) << 3) | min(7,Int(c.z*7.999))
            bins[key] += SIMD4(c.x*weight,c.y*weight,c.z*weight,weight)
        }
        func rgb(_ b: SIMD4<Double>) -> SIMD3<Double> { SIMD3(b.x,b.y,b.z) / max(0.00001,b.w) }
        func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { let d = a-b; return d.x*d.x+d.y*d.y+d.z*d.z }
        var colors: [SIMD3<Double>] = []
        for _ in 0..<3 {
            let chosen = bins.max { a,b in
                func score(_ v: SIMD4<Double>) -> Double { v.w * (colors.map { distance(rgb(v),$0) }.min() ?? 1) }
                return score(a) < score(b)
            } ?? .zero
            colors.append(rgb(chosen))
        }
        var weights = [Double](repeating: 0,count: 3)
        for _ in 0..<6 {
            var sums = Array(repeating: SIMD4<Double>.zero,count: 3)
            for bin in bins where bin.w > 0 {
                let nearest = (0..<3).min { distance(rgb(bin),colors[$0]) < distance(rgb(bin),colors[$1]) }!
                sums[nearest] += bin
            }
            for k in 0..<3 { weights[k] = sums[k].w; if weights[k] > 0 { colors[k] = rgb(sums[k]) } }
        }
        return (0..<3).sorted { weights[$0] > weights[$1] }.map { RGB(r: colors[$0].x,g: colors[$0].y,b: colors[$0].z) }
    }
}

// Serialize model lifetimes even when an edit supersedes an in-flight prediction.
// Discarding a task result must not load another 233 MB model alongside it.
private actor DepthJobs {
    static let shared = DepthJobs()
    private var tail: Task<UIImage, Error>?
    func predict(_ image: UIImage) async throws -> UIImage {
        let previous = tail
        let job = Task<UIImage, Error> {
            _ = try? await previous?.value
            guard let cg = image.cgImage else { throw CollectrError.message("This photo could not be read.") }
            let estimator = try await DepthEstimator(choice: .detailed)
            let map = try estimator.predict(CIImage(cgImage: cg))
            let bytes = Data(map.values.map { UInt8((min(1, max(0, $0)) * 255).rounded()) })
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let output = CGImage(width: map.width, height: map.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: map.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CollectrError.message("Depth could not be prepared.") }
            return UIImage(cgImage: output)
        }
        tail = job
        return try await job.value
    }
}

@MainActor
final class PhotoLibraryGate {
    static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw CollectrError.message("Allow photo access in Settings to import a photo and remove its original before sealing.") }
    }
    static func deleteOriginal(identifier: String) async throws {
        try await authorize()
        guard !identifier.isEmpty else { throw CollectrError.message("Choose the original from your photo library again so Collectr can request its deletion.") }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard assets.count == 1 else {
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized { return }
            throw CollectrError.message("The original is not accessible. Allow full photo access in Settings, then try sealing again.")
        }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.deleteAssets(assets) }
    }
}
