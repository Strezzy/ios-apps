import CoreImage
import CoreML
import CoreVideo
import Foundation

/// Use one instance on one serial export task. Core ML, the reusable input
/// buffer, and temporal state must not be shared between concurrent exports.
final class DepthEstimator: @unchecked Sendable {
    private let model: MLModel
    private let choice: DepthModelChoice
    private let inputWidth: Int
    private let inputHeight: Int
    private let inputBuffer: CVPixelBuffer
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let inputColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let normalization = DepthNormalization()

    init(choice: DepthModelChoice) async throws {
        let name = "Detailed"
        let resourceURL = Bundle.main.resourceURL
        let candidates = [
            resourceURL?.appendingPathComponent("Models/\(name).mlmodelc", isDirectory: true),
            resourceURL?.appendingPathComponent("Models/\(name).mlmodelc", isDirectory: true),
            Bundle.main.url(forResource: name, withExtension: "mlmodelc")
        ].compactMap { $0 }
        guard let modelURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw DepthCheckError.message("The \(choice.title) model is missing from this installation. Install the complete Depth Check release, which includes both offline models.")
        }

        let configuration = MLModelConfiguration()
        // These specific packages were published for .all. Do not silently
        // switch compute units: changing FP16 execution can change numerics.
        configuration.computeUnits = .all
        let loadedModel = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        guard let constraint = loadedModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else {
            throw DepthCheckError.message("The bundled depth model has an unsupported input. Reinstall the complete release.")
        }
        let width = constraint.pixelsWide
        let height = constraint.pixelsHigh
        let expectedWidth = choice == .balanced ? 518 : 504
        let expectedHeight = choice == .balanced ? 392 : 504
        guard width == expectedWidth, height == expectedHeight,
              loadedModel.modelDescription.outputDescriptionsByName["depth"] != nil else {
            throw DepthCheckError.message("The bundled depth model does not match the verified model interface.")
        }

        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                        kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw DepthCheckError.message("There is not enough memory to prepare depth estimation.")
        }
        self.choice = choice
        model = loadedModel
        inputWidth = width
        inputHeight = height
        inputBuffer = buffer
    }

    func resetTemporalState() { normalization.reset() }

    func predict(_ image: CIImage, temporal: Bool = false) throws -> DepthMap {
        try Task.checkCancellation()
        let extent = image.extent
        guard extent.width.isFinite, extent.height.isFinite, extent.width >= 1, extent.height >= 1 else {
            throw DepthCheckError.message("This image has invalid dimensions.")
        }

        // Keep the entire image. Neither a 16:9 movie nor a portrait photo is
        // stretched to the neural network's fixed aspect ratio or center-cropped.
        let scale = min(CGFloat(inputWidth) / extent.width, CGFloat(inputHeight) / extent.height)
        let fittedWidth = min(inputWidth, max(1, Int((extent.width * scale).rounded())))
        let fittedHeight = min(inputHeight, max(1, Int((extent.height * scale).rounded())))
        let offsetX = (inputWidth - fittedWidth) / 2
        let offsetY = (inputHeight - fittedHeight) / 2
        let fittedRect = CGRect(x: CGFloat(offsetX), y: CGFloat(offsetY),
                                width: CGFloat(fittedWidth), height: CGFloat(fittedHeight))
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(inputWidth), height: CGFloat(inputHeight))
        let fitted = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(fittedWidth) / extent.width,
                                               y: CGFloat(fittedHeight) / extent.height))
            .transformed(by: CGAffineTransform(translationX: CGFloat(offsetX), y: CGFloat(offsetY)))
        let background = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: bounds)
        context.render(fitted.composited(over: background), to: inputBuffer, bounds: bounds, colorSpace: inputColorSpace)

        let provider = try MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: inputBuffer)])
        let prediction = try model.prediction(from: provider)
        guard let feature = prediction.featureValue(for: "depth") else {
            throw DepthCheckError.message("The model did not return a depth image.")
        }
        let raw: RawDepth
        if let buffer = feature.imageBufferValue {
            raw = try readDepthBuffer(buffer)
        } else if let array = feature.multiArrayValue {
            raw = try readDepthArray(array)
        } else {
            throw DepthCheckError.message("The model returned an unsupported depth format.")
        }

        // Crop in Core Image coordinates so the model's padding is removed using
        // the same transform used to letterbox its input. Source image pixels are
        // never resized here; only the depth-estimation copy is small.
        let crop = try cropDepth(raw, fittedRect: fittedRect)
        let normalized = try normalization.normalize(crop.values, isInverseDepth: choice == .balanced,
                                                       luma: temporal ? lumaSamples(in: fittedRect) : [],
                                                       temporal: temporal, width: crop.width, height: crop.height)
        try Task.checkCancellation()
        return DepthMap(width: crop.width, height: crop.height, values: normalized)
    }

    private struct RawDepth {
        var width: Int
        var height: Int
        var values: [Float]
    }

    private func readDepthBuffer(_ buffer: CVPixelBuffer) throws -> RawDepth {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_OneComponent16Half || format == kCVPixelFormatType_OneComponent32Float else {
            throw DepthCheckError.message("The model returned an unsupported depth pixel format.")
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            throw DepthCheckError.message("The model depth image could not be read.")
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            throw DepthCheckError.message("The model returned an empty depth buffer.")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow)
            if format == kCVPixelFormatType_OneComponent16Half {
                let pixels = row.assumingMemoryBound(to: UInt16.self)
                for x in 0..<width { values[y * width + x] = Float(Float16(bitPattern: pixels[x])) }
            } else {
                let pixels = row.assumingMemoryBound(to: Float.self)
                for x in 0..<width { values[y * width + x] = pixels[x] }
            }
        }
        return RawDepth(width: width, height: height, values: values)
    }

    private func readDepthArray(_ array: MLMultiArray) throws -> RawDepth {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count >= 2, shape.dropLast(2).allSatisfy({ $0 == 1 }),
              let width = shape.last, width > 0, shape[shape.count - 2] > 0 else {
            throw DepthCheckError.message("The model returned an unsupported depth tensor shape.")
        }
        let height = shape[shape.count - 2]
        let xStride = strides[strides.count - 1]
        let yStride = strides[strides.count - 2]
        var values = [Float](repeating: 0, count: width * height)
        switch array.dataType {
        case .float16:
            let base = array.dataPointer.assumingMemoryBound(to: UInt16.self)
            for y in 0..<height {
                for x in 0..<width { values[y * width + x] = Float(Float16(bitPattern: base[y * yStride + x * xStride])) }
            }
        case .float32:
            let base = array.dataPointer.assumingMemoryBound(to: Float.self)
            for y in 0..<height {
                for x in 0..<width { values[y * width + x] = base[y * yStride + x * xStride] }
            }
        case .double:
            let base = array.dataPointer.assumingMemoryBound(to: Double.self)
            for y in 0..<height {
                for x in 0..<width { values[y * width + x] = Float(base[y * yStride + x * xStride]) }
            }
        default:
            throw DepthCheckError.message("The model returned an unsupported depth tensor precision.")
        }
        return RawDepth(width: width, height: height, values: values)
    }

    private func cropDepth(_ raw: RawDepth, fittedRect: CGRect) throws -> RawDepth {
        guard raw.width == inputWidth, raw.height == inputHeight else {
            throw DepthCheckError.message("The model depth resolution does not match its verified interface.")
        }
        // Core ML arrays and pixel buffers are top-to-bottom. Core Image bounds
        // are bottom-to-top, so account for any odd bottom/top padding difference.
        let xOrigin = Int(fittedRect.minX)
        let yOrigin = inputHeight - Int(fittedRect.maxY)
        let width = Int(fittedRect.width)
        let height = Int(fittedRect.height)
        var cropped = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let offset = (yOrigin + y) * raw.width + xOrigin
            cropped.replaceSubrange((y * width)..<((y + 1) * width), with: raw.values[offset..<(offset + width)])
        }
        return RawDepth(width: width, height: height, values: cropped)
    }

    /// Match the cropped depth pixel for pixel. Temporal filtering needs local
    /// appearance to reject moving regions; a sparse whole-frame signature
    /// cannot safely distinguish a moving edge from an unchanged surface.
    private func lumaSamples(in fittedRect: CGRect) -> [Float] {
        guard CVPixelBufferLockBaseAddress(inputBuffer, .readOnly) == kCVReturnSuccess else { return [] }
        defer { CVPixelBufferUnlockBaseAddress(inputBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(inputBuffer) else { return [] }
        let stride = CVPixelBufferGetBytesPerRow(inputBuffer)
        let xOrigin = Int(fittedRect.minX)
        let yOrigin = inputHeight - Int(fittedRect.maxY)
        let width = Int(fittedRect.width)
        let height = Int(fittedRect.height)
        var samples = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: (yOrigin + y) * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let pixel = (xOrigin + x) * 4
                samples[y * width + x] = (0.2126 * Float(row[pixel + 2]) + 0.7152 * Float(row[pixel + 1]) + 0.0722 * Float(row[pixel])) / 255
            }
        }
        return samples
    }
}
