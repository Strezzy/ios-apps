import Foundation
@preconcurrency import AVFoundation
import CoreImage
import CoreTransferable
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Photos supplies a temporary file; copy it before the transfer closure returns.
/// FileRepresentation deliberately avoids loading a movie into one large Data value.
struct ImportedMediaFile: Transferable, Sendable {
    let url: URL
    let originalName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copied = try MediaImporter.copyIntoImports(received.file)
            return Self(url: copied, originalName: received.file.lastPathComponent)
        }
        FileRepresentation(importedContentType: .image) { received in
            let copied = try MediaImporter.copyIntoImports(received.file)
            return Self(url: copied, originalName: received.file.lastPathComponent)
        }
    }
}

enum MediaImporter {
    static let allowedContentTypes: [UTType] = [.image, .rawImage, .movie]

    static func importFile(_ externalURL: URL) async throws -> MediaSource {
        let access = externalURL.startAccessingSecurityScopedResource()
        defer { if access { externalURL.stopAccessingSecurityScopedResource() } }
        let localURL = try copyIntoImports(externalURL)
        do {
            return try await inspect(localURL, originalName: externalURL.lastPathComponent)
        } catch {
            try? FileManager.default.removeItem(at: localURL)
            throw error
        }
    }

    static func copyIntoImports(_ source: URL) throws -> URL {
        let suffix = source.pathExtension.lowercased()
        var destination = try AppPaths.directory("Imports").appendingPathComponent(UUID().uuidString)
        if !suffix.isEmpty { destination.appendPathExtension(suffix) }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            // File-provider failures may leave a partially copied large movie behind.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return destination
    }

    static func inspect(_ url: URL, originalName: String) async throws -> MediaSource {
        try Task.checkCancellation()
        let contentType = UTType(filenameExtension: url.pathExtension)
        if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .video) == true {
            return try await inspectVideo(url, name: originalName)
        }
        if let photo = inspectPhoto(url, name: originalName, type: contentType) { return photo }
        // Providers sometimes return an extensionless movie. Its tracks are the authority.
        return try await inspectVideo(url, name: originalName)
    }

    private static func inspectPhoto(_ url: URL, name: String, type: UTType?) -> MediaSource? {
        var size: PixelSize?

        if type?.conforms(to: .rawImage) == true, let raw = CIRAWFilter(imageURL: url) {
            // Embedded JPEG previews can be smaller than the actual RAW sensor image.
            // nativeSize reports the full image, before orientation is applied.
            let native = raw.nativeSize
            let rotated = [5, 6, 7, 8].contains(Int(raw.orientation.rawValue))
            size = PixelSize(
                width: Int((rotated ? native.height : native.width).rounded()),
                height: Int((rotated ? native.width : native.height).rounded())
            )
        }

        if size == nil,
           let imageSource = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
           let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue {
            let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            let rotated = [5, 6, 7, 8].contains(orientation)
            size = PixelSize(width: rotated ? height : width, height: rotated ? width : height)
        }

        guard let size, size.width > 0, size.height > 0 else { return nil }
        return MediaSource(url: url, name: name.isEmpty ? "Photo" : name, kind: .photo, size: size)
    }

    private static func inspectVideo(_ url: URL, name: String) async throws -> MediaSource {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw DepthCheckError.message("This file does not contain a supported photo or video. Try an original HEIC, JPEG, PNG, RAW, MOV, or MP4 file.")
        }
        let (naturalSize, transform, nominalRate, minFrameDuration, descriptions) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .minFrameDuration, .formatDescriptions
        )
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform).standardized
        let size = PixelSize(width: Int(bounds.width.rounded()), height: Int(bounds.height.rounded()))
        guard size.width > 0, size.height > 0 else {
            throw DepthCheckError.message("The video's dimensions could not be read.")
        }
        let time = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(time)
        guard duration.isFinite, duration > 0 else {
            throw DepthCheckError.message("The video has no readable duration.")
        }
        let minimumDuration = CMTimeGetSeconds(minFrameDuration)
        let frameRate = nominalRate > 0 ? Double(nominalRate) : (minimumDuration.isFinite && minimumDuration > 0 ? 1 / minimumDuration : 0)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let isHDR = descriptions.contains { description in
            guard let value = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String else { return false }
            return value == kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
                || value == kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
        }
        return MediaSource(
            url: url,
            name: name.isEmpty ? "Video" : name,
            kind: .video,
            size: size,
            frameRate: frameRate,
            duration: duration,
            hasAudio: !audio.isEmpty,
            isHDR: isHDR
        )
    }

    /// This is a small interface preview only. Conversion always reads the original file.
    static func thumbnail(for source: MediaSource, maximumDimension: CGFloat = 1200) async -> UIImage? {
        if source.kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source.url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
            guard let frame = try? await generator.image(at: .zero) else { return nil }
            return UIImage(cgImage: frame.image)
        }
        return imageThumbnail(at: source.url, maximumDimension: maximumDimension)
    }

    static func imageThumbnail(at url: URL, maximumDimension: CGFloat = 1200) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maximumDimension),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
