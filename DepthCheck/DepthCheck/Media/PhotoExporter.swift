import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class PhotoExporter {
    private let source: MediaSource
    private let options: ConversionOptions
    private let outputDirectory: URL
    private let renderer: StereoRenderer

    init(source: MediaSource, options: ConversionOptions, outputDirectory: URL, renderer: StereoRenderer) {
        self.source = source
        self.options = options
        self.outputDirectory = outputDirectory
        self.renderer = renderer
    }

    func export(predictDepth: DepthPrediction,
                onProgress: @Sendable (ConversionProgress) -> Void) throws -> ExportResult {
        try Task.checkCancellation()
        onProgress(.init(fraction: 0.08, stage: "Opening full-resolution photo"))
        let decoded = try Self.decodePhoto(at: source.url)
        let size = PixelSize(width: Int(decoded.image.extent.width.rounded()),
                             height: Int(decoded.image.extent.height.rounded()))
        guard size.width > 0, size.height > 0 else {
            throw DepthCheckError.message("The photo has no readable full-resolution image.")
        }
        onProgress(.init(fraction: 0.20, stage: "Estimating depth"))
        let depth = try predictDepth(decoded.image, false)
        try Task.checkCancellation()
        onProgress(.init(fraction: 0.60, stage: "Rendering every source pixel"))
        let files: [URL]
        if options.format == .depthMap {
            let buffer = try renderer.depthPixelBuffer(depth: depth, size: size)
            files = [try writeImage(renderer.cgImage(from: buffer), name: "Depth-Map")]
        } else {
            let metadata = VirtualStereoMetadata(options: options)
            let spatial = options.format == .spatial
            let pair = try renderer.render(source: decoded.image,
                                           depth: spatial ? metadata.spatialDepth(depth) : depth,
                                           options: spatial ? metadata.unshiftedOptions : options)
            try Task.checkCancellation()
            switch options.format {
            case .spatial:
                files = [try writeSpatialPhoto(pair: pair, metadata: metadata, size: size)]
            case .separateEyes:
                // Encode one eye at a time instead of retaining two CGImages.
                let left = try autoreleasepool { try writeImage(renderer.cgImage(from: pair.left), name: "Left-Eye") }
                let right = try autoreleasepool { try writeImage(renderer.cgImage(from: pair.right), name: "Right-Eye") }
                files = [left, right]
            case .sideBySide, .overUnder, .anaglyph:
                let buffer = try renderer.packed(pair: pair, format: options.format)
                files = [try writeImage(renderer.cgImage(from: buffer), name: "Depth-Check")]
            case .depthMap:
                preconditionFailure("Depth-map export is handled before stereo rendering")
            }
        }
        try Task.checkCancellation()
        onProgress(.init(fraction: 0.96, stage: "Checking image dimensions"))
        let outputSize = options.format.outputSize(for: size)
        for file in files {
            try Self.verify(file, expectedSize: outputSize, spatial: options.format == .spatial)
        }
        var note = "Full source pixel dimensions retained. Rendered in SDR; the original is unchanged."
        if decoded.wasRAW { note += " RAW sensor data was developed at native resolution before stereo rendering." }
        if options.format == .spatial { note += " Spatial metadata describes the synthetic virtual cameras." }
        if options.format == .depthMap { note += " Estimated depth is upsampled to the source dimensions." }
        return ExportResult(files: files, sourceName: source.name, format: options.format,
                            size: outputSize, note: note)
    }

    struct DecodedPhoto {
        let image: CIImage
        let wasRAW: Bool
    }

    static func decodePhoto(at url: URL) throws -> DecodedPhoto {
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let identifier = imageSource.flatMap { CGImageSourceGetType($0) as String? }
        let type = identifier.flatMap { UTType($0) } ?? UTType(filenameExtension: url.pathExtension)
        let isRAW = type?.conforms(to: .rawImage) == true
        let image: CIImage
        if isRAW {
            guard let raw = CIRAWFilter(imageURL: url) else {
                throw DepthCheckError.message("Apple's RAW decoder does not support this photo. Export a full-resolution TIFF, HEIC, or PNG from your camera software and import that file.")
            }
            // Never select an embedded preview, draft decode or reduced scale.
            raw.scaleFactor = 1
            raw.isDraftModeEnabled = false
            raw.extendedDynamicRangeAmount = 0
            guard let fullImage = raw.outputImage else {
                throw DepthCheckError.message("The RAW file could not be developed at its native resolution.")
            }
            image = fullImage
        } else {
            guard let fullImage = CIImage(contentsOf: url, options: [
                .applyOrientationProperty: true, .toneMapHDRtoSDR: true
            ]) else {
                throw DepthCheckError.message("This image format could not be opened at full resolution.")
            }
            image = fullImage
        }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isNull, extent.width.isFinite, extent.height.isFinite else {
            throw DepthCheckError.message("The photo has invalid dimensions.")
        }
        let normalized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        return DecodedPhoto(image: normalized, wasRAW: isRAW)
    }

    private func writeImage(_ image: CGImage, name: String) throws -> URL {
        let type: UTType
        switch options.photoEncoding {
        case .heic: type = .heic
        case .jpeg: type = .jpeg
        case .png: type = .png
        }
        let url = outputDirectory.appendingPathComponent(name).appendingPathExtension(options.photoEncoding.rawValue)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw DepthCheckError.message("This device cannot create a \(options.photoEncoding.title) image at the requested size. Try PNG or Separate Eyes; the source will not be resized.")
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.98,
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyHasAlpha: false
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw DepthCheckError.message("The \(options.photoEncoding.title) encoder could not save the full-resolution photo. Try PNG or Separate Eyes.")
        }
        return url
    }

    private func writeSpatialPhoto(pair: StereoPair, metadata: VirtualStereoMetadata, size: PixelSize) throws -> URL {
        let url = outputDirectory.appendingPathComponent("Depth-Check-Spatial.heic")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString,
            2, [kCGImagePropertyPrimaryImage: 0] as CFDictionary) else {
            throw DepthCheckError.message("Spatial HEIC encoding is unavailable for this photo. Try Separate Eyes or PNG side-by-side.")
        }
        let focalLength = (Double(size.width) / 2) / tan(options.horizontalFieldOfViewDegrees * .pi / 360)
        let intrinsics: [Double] = [focalLength, 0, Double(size.width) / 2,
                                   0, focalLength, Double(size.height) / 2, 0, 0, 1]
        let identity: [Double] = [1, 0, 0, 0, 1, 0, 0, 0, 1]
        for (isLeft, buffer) in [(true, pair.left), (false, pair.right)] {
            try Task.checkCancellation()
            try autoreleasepool {
                let position: [Double] = [isLeft ? 0 : options.virtualBaselineMillimeters / 1_000, 0, 0]
                let properties: [CFString: Any] = [
                    kCGImagePropertyGroups: [
                        kCGImagePropertyGroupIndex: 0,
                        kCGImagePropertyGroupType: kCGImagePropertyGroupTypeStereoPair,
                        (isLeft ? kCGImagePropertyGroupImageIsLeftImage : kCGImagePropertyGroupImageIsRightImage): true,
                        kCGImagePropertyGroupImageDisparityAdjustment: Int((metadata.disparityAdjustment * 10_000).rounded())
                    ],
                    kCGImagePropertyHEIFDictionary: [
                        kIIOMetadata_CameraExtrinsicsKey: [kIIOCameraExtrinsics_Position: position, kIIOCameraExtrinsics_Rotation: identity],
                        kIIOMetadata_CameraModelKey: [kIIOCameraModel_Intrinsics: intrinsics,
                                                    kIIOCameraModel_ModelType: kIIOCameraModelType_SimplifiedPinhole]
                    ],
                    kCGImagePropertyOrientation: 1,
                    kCGImagePropertyHasAlpha: false,
                    kCGImageDestinationLossyCompressionQuality: 0.98
                ]
                CGImageDestinationAddImage(destination, try renderer.cgImage(from: buffer), properties as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else {
            throw DepthCheckError.message("The spatial HEIC encoder could not preserve this image's dimensions. Try Separate Eyes; no reduced image was saved.")
        }
        return url
    }

    static func verify(_ url: URL, expectedSize: PixelSize, spatial: Bool) throws {
        guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(image) == (spatial ? 2 : 1) else {
            throw DepthCheckError.message("The exported photo is incomplete and was not kept.")
        }
        for index in 0..<CGImageSourceGetCount(image) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any],
                  (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expectedSize.width,
                  (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expectedSize.height else {
                throw DepthCheckError.message("The image encoder changed the requested dimensions. The export was rejected.")
            }
        }
        if spatial {
            // AddImage takes per-image group membership instructions, but on
            // readback ImageIO exposes the resulting relationship in the
            // container properties. Its left/right indices identify the two
            // member images; CopyPropertiesAtIndex is only for an image's
            // individual properties and does not expose this file-level group.
            // https://developer.apple.com/documentation/imageio/image-properties
            // https://developer.apple.com/documentation/imageio/writing-spatial-photos
            let properties = CGImageSourceCopyProperties(image, nil) as? [CFString: Any]
            let groups = properties?[kCGImagePropertyGroups] as? [[CFString: Any]] ?? []
            let count = CGImageSourceGetCount(image)
            let hasStereoPair = groups.contains { group in
                guard (group[kCGImagePropertyGroupType] as? String) == (kCGImagePropertyGroupTypeStereoPair as String),
                      let leftIndex = group[kCGImagePropertyGroupImageIndexLeft] as? Int,
                      let rightIndex = group[kCGImagePropertyGroupImageIndexRight] as? Int else { return false }
                return leftIndex != rightIndex && (0..<count).contains(leftIndex) && (0..<count).contains(rightIndex)
            }
            guard hasStereoPair else {
                #if DEBUG
                // Restrict diagnostics to group relationships, not image data
                // or unrelated EXIF properties, if an OS changes this contract.
                let imageGroups: [Any] = (0..<count).map { index in
                    let item = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any]
                    return item?[kCGImagePropertyGroups] ?? "missing"
                }
                print("Spatial HEIC verification: container groups = \(String(describing: properties?[kCGImagePropertyGroups])); image groups = \(imageGroups)")
                #endif
                throw DepthCheckError.message("ImageIO did not write the required stereo-pair metadata. The incomplete spatial photo was rejected.")
            }
        }
    }
}
