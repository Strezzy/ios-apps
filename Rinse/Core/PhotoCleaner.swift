import Foundation
import ImageIO
import CoreImage
import UniformTypeIdentifiers

/// Reconstructs a fresh SDR raster. No source metadata dictionary is copied.
enum PhotoCleaner {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static let allowedExif: Set<String> = ["ColorSpace", "PixelXDimension", "PixelYDimension", "ComponentsConfiguration", "ExifVersion", "FlashPixVersion"]
    private static let allowedTIFF: Set<String> = ["Orientation", "XResolution", "YResolution", "ResolutionUnit", "WhitePoint", "PrimaryChromaticities"]
    static func audit(_ url: URL) throws -> Audit {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw RinseError.message("This photo could not be opened.")
        }
        var paths = Set<String>()
        func inspect(_ dictionary: [String: Any], prefix: String = "") {
            for (key, value) in dictionary {
                let path = prefix.isEmpty ? key : prefix + "." + key
                // ColorModel describes RGB/CMYK pixels, not a camera model.
                // Limit this exception to ImageIO's top-level technical property;
                // arbitrary nested fields and camera Model tags remain inspected.
                if prefix.isEmpty && key == (kCGImagePropertyColorModel as String) { continue }
                if let nested = value as? [String: Any] {
                    if key == "{Exif}" {
                        for field in nested.keys where !allowedExif.contains(field) { paths.insert(path + "." + field) }
                    } else if key == "{TIFF}" {
                        for field in nested.keys where !allowedTIFF.contains(field) { paths.insert(path + "." + field) }
                    } else if ["{GPS}", "{IPTC}", "{ExifAux}", "{MakerApple}", "{XMP}"].contains(key) {
                        for field in nested.keys { paths.insert(path + "." + field) }
                    } else { inspect(nested, prefix: path) }
                } else {
                    let normalized = key.lowercased()
                    let sensitive = ["gps", "location", "latitude", "longitude", "date", "time", "author", "artist", "creator", "copyright", "description", "comment", "keyword", "software", "serial", "owner", "camera", "lens", "make", "model", "document", "identifier", "title"]
                    if sensitive.contains(where: { normalized.contains($0) }) { paths.insert(path) }
                }
            }
        }
        if let global = CGImageSourceCopyProperties(source, nil) as? [String: Any] { inspect(global) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        inspect(properties)
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
           let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] {
            let technical = allowedExif.union(allowedTIFF).union(["BitsPerSample", "ImageWidth", "ImageLength", "SamplesPerPixel", "PhotometricInterpretation", "YCbCrPositioning", "YCbCrSubSampling", "Compression", "PlanarConfiguration"])
            for tag in tags {
                let name = (CGImageMetadataTagCopyName(tag) as String?) ?? "Unknown"
                if !technical.contains(name) {
                    let prefix = (CGImageMetadataTagCopyPrefix(tag) as String?) ?? "metadata"
                    paths.insert(prefix + ":" + name)
                }
            }
        }
        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        return Audit(fields: paths.sorted(), mediaDescription: "\(width) × \(height)")
    }
    static func rebuild(_ input: URL, options: CleanOptions) throws -> (URL, [String]) {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let sourceType = CGImageSourceGetType(source) as String?,
              [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier, UTType.heif.identifier].contains(sourceType),
              CGImageSourceGetCount(source) == 1 else {
            throw RinseError.message("Choose a single-frame JPEG, PNG or HEIC. RAW, animated and multi-image files are not supported in version 1.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        guard width > 0, height > 0, Double(width) * Double(height) <= Double(options.maxPhotoPixels) else {
            throw RinseError.message("This photo exceeds this import's memory-safe pixel limit. Use the main app for photos up to 64 megapixels.")
        }
        let orientation = (properties[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true, kCGImageSourceShouldAllowFloat: false] as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw RinseError.message("The photo's pixels could not be decoded.")
        }
        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: orientation)
        guard let rendered = context.createCGImage(oriented, from: oriented.extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw RinseError.message("The photo could not be rendered.")
        }
        let targetType: String
        switch options.photoFormat {
        case .jpeg: targetType = UTType.jpeg.identifier
        case .png: targetType = UTType.png.identifier
        case .original: targetType = sourceType == UTType.heif.identifier ? UTType.heic.identifier : sourceType
        }
        let suffix = targetType == UTType.jpeg.identifier ? "jpg" : (targetType == UTType.png.identifier ? "png" : "heic")
        let output = Workspace.destination(extension: suffix)
        do {
            guard let destination = CGImageDestinationCreateWithURL(output as CFURL, targetType as CFString, 1, nil) else {
                throw RinseError.message("This photo encoder is unavailable on this device. Choose PNG or JPEG in Settings.")
            }
            let settings: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95,
                kCGImagePropertyOrientation: 1, kCGImageDestinationEmbedThumbnail: false]
            CGImageDestinationAddImage(destination, rendered, settings as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw RinseError.message("The cleaned photo could not be saved.") }
            try Task.checkCancellation()
            var notes = ["Rebuilt at full pixel dimensions with orientation applied. Color is standardized to 8-bit sRGB.",
                         "HDR, depth, spatial and Live Photo motion data are not retained. Visible content is not redacted."]
            notes.append(suffix == "png" ? "PNG is lossless for the rendered SDR pixels." : "This format is re-encoded at high quality, not losslessly copied.")
            return (output, notes)
        } catch { try? FileManager.default.removeItem(at: output); throw error }
    }
}
