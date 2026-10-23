import AVFoundation
import Foundation
import UIKit

enum PhotoFormat: String, CaseIterable, Identifiable {
    case heif, jpeg, raw
    var id: String { rawValue }
    var label: String { self == .raw ? "RAW + JPEG" : rawValue.uppercased() }
}

enum CameraFlash: String, CaseIterable, Identifiable {
    case off, auto, on
    var id: String { rawValue }
    var avMode: AVCaptureDevice.FlashMode {
        switch self { case .off: return .off; case .auto: return .auto; case .on: return .on }
    }
}

enum CameraFocusState: Equatable { case idle, adjusting, settled }

struct CameraLens: Identifiable, Equatable {
    let id: String
    let label: String
    let isFront: Bool
    let nativeZoomFactor: Double
}

struct VideoMode: Identifiable, Hashable {
    let width: Int
    let height: Int
    let fps: Int
    let codec: String
    var id: String { "\(width)x\(height)-\(fps)-\(codec)" }
    var label: String { "\(height == 2160 ? "4K" : "\(height)p") · \(fps) · \(codec == "hevc" ? "HEVC" : "H.264")" }
    static let standard = VideoMode(width: 1920, height: 1080, fps: 30, codec: "h264")
    var codecType: AVVideoCodecType { codec == "hevc" ? .hevc : .h264 }
    var outputSettings: [String: Any] {
        [AVVideoCodecKey: codecType, AVVideoWidthKey: width, AVVideoHeightKey: height,
         AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: min(60_000_000, max(5_000_000, width * height * fps / 5)),
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0
         ]]
    }
}

enum CameraError: LocalizedError {
    case permission, unavailable, unsupported, configurationLost, recordingFailed, noSamples, interrupted, invalidRange
    var errorDescription: String? {
        switch self {
        case .permission: return "Allow camera access in iPhone Settings to take photographs."
        case .unavailable: return "The camera is unavailable. Close other camera apps and try again."
        case .unsupported: return "This capture combination is unavailable on the active camera."
        case .configurationLost: return "The camera could not restore its previous settings. Restart the camera to continue."
        case .recordingFailed: return "Recording could not be saved securely. The incomplete recording was discarded."
        case .noSamples: return "No video frames were captured. Try recording again."
        case .interrupted: return "Camera capture was interrupted. Any incomplete recording was discarded."
        case .invalidRange: return "The encrypted movie could not be read."
        }
    }
}

struct CapturedPhoto {
    let data: Data
    let fileExtension: String
    let width: Int
    let height: Int
}

struct CameraCapabilities {
    let lenses: [CameraLens]
    let selectedLens: String
    let modes: [VideoMode]
    let supportsRAW: Bool
    let supportsHEIF: Bool
    let resolution: String
    let minimumExposureBias: Float
    let maximumExposureBias: Float
    let currentExposureBias: Float
    let activeVideoMode: VideoMode?
}

/// Shared policy for device configuration and its UI; the selected value always
/// comes from the active physical camera's capability list.
enum CameraConfigurationPolicy {
    static func videoMode(in supported: [VideoMode], retaining requested: VideoMode?, isFront: Bool) -> VideoMode? {
        if let requested, supported.contains(requested) { return requested }
        let preferred = VideoMode(width: isFront ? 1920 : 3840, height: isFront ? 1080 : 2160,
                                  fps: isFront ? 30 : 60, codec: "hevc")
        if supported.contains(preferred) { return preferred }
        let alternate = VideoMode(width: preferred.width, height: preferred.height, fps: preferred.fps, codec: "h264")
        if supported.contains(alternate) { return alternate }
        // High frame rates are an explicit choice, including on cameras whose
        // supported modes do not include our preferred 4K60 combination.
        let normalRates = supported.filter { $0.fps <= 60 }
        return normalRates.sorted {
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.fps != $1.fps { return $0.fps > $1.fps }
            return $0.codec == "hevc" && $1.codec != "hevc"
        }.first
    }

    static func captureCodecs(width: Int, height: Int, fps: Int) -> [String] {
        // Keep high-throughput 4K in the hardware-efficient HEVC path.
        width >= 3840 && height >= 2160 && fps > 60 ? ["hevc"] : ["h264", "hevc"]
    }

    static func isProcessedVideoSource(_ pixelFormat: OSType) -> Bool {
        pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    }

    static func clampedFocusPoint(_ point: CGPoint) -> CGPoint? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }

    static func nativeZoomFactors(constituentIDs: [String], switchFactors: [Double]) -> [String: Double] {
        let factors = [1.0] + switchFactors
        guard factors.count == constituentIDs.count, Set(constituentIDs).count == constituentIDs.count,
              factors.allSatisfy({ $0.isFinite && $0 >= 1 }),
              zip(factors, factors.dropFirst()).allSatisfy({ pair in pair.0 <= pair.1 }) else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(constituentIDs, factors))
    }

    static func zoomLabel(nativeFactor: Double) -> String {
        guard nativeFactor.isFinite, nativeFactor > 0 else { return "Tele" }
        let rounded = (nativeFactor * 2).rounded() / 2
        if rounded.rounded() == rounded { return "\(Int(rounded))×" }
        return String(format: "%.1f×", rounded)
    }
}

/// Physical device orientation is deliberately independent of UIWindowScene.
/// RotationCoordinator supplies capture angles on hardware; these values are a
/// deterministic fallback and also define the only glyph rotations in the UI.
struct CameraPhysicalOrientation: Equatable {
    let captureDegrees: CGFloat
    let controlDegrees: Double
    static func quarterTurn(_ degrees: CGFloat, fallback: CGFloat = 90) -> CGFloat {
        guard degrees.isFinite else { return fallback }
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return (normalized / 90).rounded().truncatingRemainder(dividingBy: 4) * 90
    }
    static func from(_ orientation: UIDeviceOrientation) -> Self? {
        switch orientation {
        case .portrait: return .init(captureDegrees: 90, controlDegrees: 0)
        case .landscapeLeft: return .init(captureDegrees: 0, controlDegrees: 90)
        case .landscapeRight: return .init(captureDegrees: 180, controlDegrees: -90)
        case .portraitUpsideDown: return .init(captureDegrees: 270, controlDegrees: 180)
        default: return nil
        }
    }
}

struct CameraManualCapabilities: Equatable {
    let exposureBias: Float
    let supportsExposure: Bool
    let minimumISO: Float
    let maximumISO: Float
    let minimumShutterSeconds: Double
    let maximumShutterSeconds: Double
    let currentISO: Float
    let currentShutterSeconds: Double
    let exposureIsManual: Bool
    let supportsWhiteBalance: Bool
    let maximumWhiteBalanceGain: Float
    let redGain: Float
    let greenGain: Float
    let blueGain: Float
    let whiteBalanceIsLocked: Bool
}
