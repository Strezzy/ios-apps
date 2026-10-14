import Foundation
import AVFoundation
import CoreVideo

struct EnhanceSettings: Codable, Equatable, Sendable {
    var enhance = true
    var strength: Double = 0.65
    var scale = 1
    var fps = 0
    var preserveAudio = true
    var gentleProcessing = true
    var usesRestoration: Bool { enhance || scale > 1 }
    var summary: String {
        "\(enhance ? "Enhance" : "Original detail") · \(scale == 1 ? "Original size" : "\(scale)×") · \(fps == 0 ? "Original FPS" : "\(fps) FPS")"
    }
    func validate(width: Int, height: Int, sourceFPS: Double) throws {
        guard [1, 2, 4].contains(scale), [0, 30, 60].contains(fps),
              strength.isFinite, (0...1).contains(strength),
              width > 0, height > 0, width % 2 == 0, height % 2 == 0,
              sourceFPS.isFinite, sourceFPS > 0, sourceFPS <= 120 else {
            throw LiftError.message("This video format or these settings are not supported.")
        }
        let w = width * scale, h = height * scale
        guard max(w, h) <= 3840, min(w, h) <= 2160 else {
            throw LiftError.message("Choose a smaller scale. This release exports up to 3840 × 2160, including portrait video.")
        }
        if fps != 0 && width * height > 1920 * 1080 {
            throw LiftError.message("AI motion currently supports input up to 1080p, including portrait video. Choose Original FPS for this clip.")
        }
    }
}

enum LiftError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): return text } }
}

struct ClipInfo: @unchecked Sendable {
    let url: URL
    let title: String
    let width: Int
    let height: Int
    let fps: Double
    let duration: Double
    let transform: CGAffineTransform
    let timeRange: CMTimeRange
    let audioTracks: Int
    var displaySize: CGSize {
        let rect = CGRect(x: 0, y: 0, width: width, height: height).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
    var dimensions: String { "\(Int(displaySize.width)) × \(Int(displaySize.height))" }
    var durationLabel: String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
    static func inspect(_ url: URL) async throws -> ClipInfo {
        guard url.isFileURL else { throw LiftError.message("Choose a video stored on your device.") }
        let asset = AVURLAsset(url: url)
        guard !(try await asset.load(.hasProtectedContent)),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw LiftError.message("This file has no readable, unprotected video track.")
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first else { throw LiftError.message("The video format could not be read.") }
        for format in descriptions {
            let ext = CMFormatDescriptionGetExtensions(format) as NSDictionary
            let transfer = ext[kCMFormatDescriptionExtension_TransferFunction] as? String ?? ""
            let primaries = ext[kCMFormatDescriptionExtension_ColorPrimaries] as? String ?? ""
            guard !transfer.contains("2084"), !transfer.contains("HLG"), !transfer.contains("2100"),
                  !primaries.contains("2020"), !primaries.contains("P3") else {
                throw LiftError.message("This first release supports standard-color SDR video. HDR, Dolby Vision and wide-color clips need a separate SDR export first; LumaLift will not silently damage their colors.")
            }
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        let range = try await track.load(.timeRange)
        let duration = range.duration.seconds
        let nominal = Double(try await track.load(.nominalFrameRate))
        guard duration.isFinite, duration > 0, nominal.isFinite, nominal > 0 else {
            throw LiftError.message("The video has invalid timing.")
        }
        let audio = try await asset.loadTracks(withMediaType: .audio)
        return ClipInfo(url: url, title: url.deletingPathExtension().lastPathComponent,
                        width: Int(dimensions.width), height: Int(dimensions.height), fps: nominal,
                        duration: duration, transform: try await track.load(.preferredTransform),
                        timeRange: range, audioTracks: audio.count)
    }
}

struct WorkProgress: Sendable {
    var fraction: Double
    var stage: String
    var frames: Int = 0
}

/// Shared cancellation and thermal gate. Heavy processing never runs on the UI thread.
final class WorkControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var paused = false
    private var background = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func setPaused(_ value: Bool) { lock.lock(); paused = value; lock.unlock() }
    func setBackground(_ value: Bool) { lock.lock(); background = value; lock.unlock() }
    var userPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    func checkpoint(gentle: Bool = true, onWait: ((String) -> Void)? = nil) throws {
        while true {
            lock.lock()
            let stop = cancelled, hold = paused, away = background
            lock.unlock()
            if stop || Task.isCancelled { throw CancellationError() }
            let thermal = ProcessInfo.processInfo.thermalState
            let hot = thermal == .critical || (gentle && thermal == .serious)
            if !hold && !away && !hot { return }
            onWait?(hot ? "Cooling down safely" : (away ? "Paused while in background" : "Paused"))
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
}

/// Integer output clock, including arbitrary source frame rates and VFR input.
struct FrameClock {
    let fps: Int
    private(set) var index: Int64 = 0
    var time: CMTime { CMTime(value: index, timescale: Int32(fps)) }
    mutating func advance() { index += 1 }
    static func fraction(at time: CMTime, between a: CMTime, and b: CMTime) -> Float {
        let gap = CMTimeSubtract(b, a).seconds
        guard gap > 0 else { return 0 }
        return Float(min(1, max(0, CMTimeSubtract(time, a).seconds / gap)))
    }
}

struct TileRegion {
    let x: Int, y: Int, width: Int, height: Int
    static let inputSize = 256
    static let padding = 40
    static let step = inputSize - 2 * padding
    static func regions(width: Int, height: Int) -> [TileRegion] {
        stride(from: 0, to: height, by: step).flatMap { y in
            stride(from: 0, to: width, by: step).map { x in
                TileRegion(x: x, y: y, width: min(step, width - x), height: min(step, height - y))
            }
        }
    }
}

func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
    var value: CVPixelBuffer?
    let attributes: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
    ]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                              attributes as CFDictionary, &value) == kCVReturnSuccess,
          let value else { throw LiftError.message("There is not enough memory for this frame. Try a smaller output.") }
    return value
}
