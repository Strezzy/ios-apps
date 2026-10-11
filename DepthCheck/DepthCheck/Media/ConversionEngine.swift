import Foundation
import CoreImage

/// Coordinates a single, cancellable conversion away from the main actor.
/// All model, renderer and AVFoundation objects stay inside the worker task.
final class ConversionEngine: Sendable {
    func convert(
        source: MediaSource,
        options: ConversionOptions,
        onProgress: @escaping @Sendable (ConversionProgress) -> Void
    ) async throws -> ExportResult {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            try Self.validate(options)
            let directory = try AppPaths.exportDirectory()
            do {
                let renderer = try StereoRenderer()
                defer { renderer.purgeCaches() }

                // Check real encoder support before loading a large model.
                let videoExporter: VideoExporter?
                if source.kind == .video {
                    let exporter = VideoExporter(source: source, options: options,
                                                 outputDirectory: directory, renderer: renderer)
                    try await exporter.prepare(onProgress: onProgress)
                    videoExporter = exporter
                } else {
                    videoExporter = nil
                }

                onProgress(.init(fraction: 0.03, stage: "Loading depth model"))
                let estimator = try await DepthEstimator(choice: options.model)
                try Task.checkCancellation()
                estimator.resetTemporalState()
                let prediction: DepthPrediction = { image, temporal in
                    try estimator.predict(image, temporal: temporal)
                }

                let result: ExportResult
                if let videoExporter {
                    result = try await videoExporter.export(predictDepth: prediction, onProgress: onProgress)
                } else {
                    result = try PhotoExporter(source: source, options: options,
                                               outputDirectory: directory, renderer: renderer)
                        .export(predictDepth: prediction, onProgress: onProgress)
                }
                try Task.checkCancellation()
                onProgress(.init(fraction: 1, stage: "Ready to share", framesProcessed: result.frameCount))
                return result
            } catch {
                // A failed or canceled result must never appear as a usable export.
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func validate(_ options: ConversionOptions) throws {
        guard options.depthAmount.isFinite, (0...0.15).contains(options.depthAmount),
              options.convergence.isFinite, (0...1).contains(options.convergence),
              options.horizontalFieldOfViewDegrees.isFinite,
              (1..<179).contains(options.horizontalFieldOfViewDegrees),
              options.virtualBaselineMillimeters.isFinite,
              (0.01...1_000).contains(options.virtualBaselineMillimeters) else {
            throw DepthCheckError.message("The depth or virtual-camera settings are outside their supported range.")
        }
    }
}

/// Dependency injection keeps the media pipeline testable without loading AI weights.
typealias DepthPrediction = (CIImage, Bool) throws -> DepthMap

/// Spatial files hold the unshifted virtual views. The spatial player applies
/// the convergence metadata once; packed files have convergence baked in.
struct VirtualStereoMetadata {
    let options: ConversionOptions

    var disparityAdjustment: Double {
        options.depthAmount * (options.swapEyes ? 1 - options.convergence : options.convergence)
    }

    var unshiftedOptions: ConversionOptions {
        var value = options
        value.convergence = 0
        value.swapEyes = false
        return value
    }

    func spatialDepth(_ depth: DepthMap) -> DepthMap {
        guard options.swapEyes else { return depth }
        return DepthMap(width: depth.width, height: depth.height, values: depth.values.map { 1 - $0 })
    }
}
